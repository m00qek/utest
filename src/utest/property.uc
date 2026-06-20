import * as math from 'math';
import * as fs from 'fs';
import * as dsl from 'utest.dsl';
import { parse_thrown, mkdir_p } from 'utest.util';
import { root, stack } from 'utest.runner.worker.registry';

const OVERRUN_MSG = sprintf('%J', { __utest__: { kind: 'property_overrun' } });

// Every 1-in-N draws, force a 0 instead of a uniform sample.  Zero maps to
// "interesting" edge values across all generators, surfacing bugs faster.
const BIAS_DENOM = 8;

function record_source(seed) {
	math.srand(seed);
	const choices = [];
	return {
		seed,
		choices,
		draw: function(bound) {
			if (bound <= 1) { push(choices, 0); return 0; }
			const r = int(math.rand());
			const v = (r % BIAS_DENOM === 0) ? 0 : (r % bound);
			push(choices, v);
			return v;
		}
	};
}

function replay_source(choices) {
	let i = 0;
	return {
		choices,
		draw: function(bound) {
			if (i >= length(choices)) die(OVERRUN_MSG);
			if (bound <= 1) { i++; return 0; }
			return choices[i++] % bound;
		}
	};
}

function caught_msg(e) {
	return (type(e) === 'object' && e.message) ? e.message : sprintf('%s', e);
}

function utest_kind(e) {
	const m = caught_msg(e);
	let parsed = null;
	try { parsed = json(m); } catch (_) {}
	if (type(parsed) === 'object' && parsed.__utest__) return parsed.__utest__.kind;
	return null;
}

function is_property_sentinel(kind) {
	return kind === 'property_overrun' || kind === 'property_discard';
}

// Replays skip classify/discards counters — only original generation runs count.
const NOOP_CTX = { classify: function(_label, _cond) {} };

function try_choices(g, prop_fn, choices) {
	const s = replay_source(choices);
	let value;
	try { value = g.generate(s); }
	catch (e) {
		if (is_property_sentinel(utest_kind(e))) return { kind: 'invalid' };
		die(e);
	}
	try { prop_fn(value, NOOP_CTX); return { kind: 'pass' }; }
	catch (e) {
		if (is_property_sentinel(utest_kind(e))) return { kind: 'invalid' };
		return { kind: 'fail', value, error: e };
	}
}

function without_range(arr, idx, n) {
	const c = [];
	for (let i = 0; i < length(arr); i++)
		if (i < idx || i >= idx + n) push(c, arr[i]);
	return c;
}

function lex_smaller(a, b) {
	if (length(a) !== length(b)) return length(a) < length(b);
	for (let i = 0; i < length(a); i++) {
		if (a[i] !== b[i]) return a[i] < b[i];
	}
	return false;
}

// Tries a shrink candidate; returns true and updates ctx if it became the new minimum.
function shrink_step(g, prop_fn, ctx, cand) {
	if (!lex_smaller(cand, ctx.cur)) return false;
	const r = try_choices(g, prop_fn, cand);
	ctx.evals++;
	if (ctx.evals >= ctx.max_evals) ctx.capped = true;
	if (r.kind !== 'fail') return false;
	ctx.cur = cand;
	return true;
}

function sorted_copy(arr, len) {
	const slice = [];
	for (let k = 0; k < len; k++) push(slice, arr[k]);
	sort(slice);
	const out = [...arr];
	for (let k = 0; k < len; k++) out[k] = slice[k];
	return out;
}

// Greedy shrinker.  Move classes, cheapest first:
//   (1) delete a contiguous span                — collapses lengths
//   (2) sort a prefix                            — canonicalizes order
//   (3) swap adjacent out-of-order pairs         — local reordering
//   (4) lower a single value (binary search)     — reduces magnitudes
//   (5) redistribute weight between two positions — preserves sums
// Loops until a full pass finds no improvement OR max_evals is hit.
function shrink(g, prop_fn, failing, max_evals) {
	const ctx = { cur: failing, evals: 0, capped: false, max_evals };
	let progress = true;
	while (progress && !ctx.capped) {
		progress = false;

		// (1) deletions: try larger spans first, then singles.
		// span /= 2 in ucode is integer division, so span reaches 0 and the loop exits.
		for (let span = length(ctx.cur); span >= 1 && !progress && !ctx.capped; span /= 2) {
			for (let i = 0; i + span <= length(ctx.cur) && !progress; i++) {
				if (shrink_step(g, prop_fn, ctx, without_range(ctx.cur, i, span))) progress = true;
			}
		}
		if (progress) continue;

		// (2) sort a prefix — wins big for order-invariant properties.
		for (let len = length(ctx.cur); len >= 2 && !progress && !ctx.capped; len /= 2) {
			if (shrink_step(g, prop_fn, ctx, sorted_copy(ctx.cur, len))) progress = true;
		}
		if (progress) continue;

		// (3) swap adjacent out-of-order pairs.
		for (let i = 0; i < length(ctx.cur) - 1 && !progress && !ctx.capped; i++) {
			if (ctx.cur[i] <= ctx.cur[i+1]) continue;
			const cand = [...ctx.cur];
			cand[i] = ctx.cur[i+1]; cand[i+1] = ctx.cur[i];
			if (shrink_step(g, prop_fn, ctx, cand)) progress = true;
		}
		if (progress) continue;

		// (4) lower individual values — binary search per position toward 0.
		for (let i = 0; i < length(ctx.cur) && !progress && !ctx.capped; i++) {
			if (ctx.cur[i] === 0) continue;
			let cand = [...ctx.cur]; cand[i] = 0;
			if (shrink_step(g, prop_fn, ctx, cand)) { progress = true; continue; }
			// Binary search: lo known-pass, hi known-fail.
			let lo = 0, hi = ctx.cur[i];
			while (lo + 1 < hi && !ctx.capped) {
				const mid = int((lo + hi) / 2);
				const c2 = [...ctx.cur]; c2[i] = mid;
				const r2 = try_choices(g, prop_fn, c2);
				ctx.evals++;
				if (ctx.evals >= ctx.max_evals) ctx.capped = true;
				if (r2.kind === 'fail') hi = mid;
				else lo = mid;
			}
			if (hi < ctx.cur[i]) {
				const c3 = [...ctx.cur]; c3[i] = hi;
				ctx.cur = c3;
				progress = true;
			}
		}
		if (progress) continue;

		// (5) redistribute pairs (a, b) → (a-k, b+k) for k = 1, 2, 4, ...
		// Preserves the value sum — the only move that can reduce a sum-constrained
		// shrunken structure further.
		for (let i = 0; i < length(ctx.cur) - 1 && !progress && !ctx.capped; i++) {
			if (ctx.cur[i] === 0) continue;
			for (let j = i + 1; j < length(ctx.cur) && !progress && !ctx.capped; j++) {
				for (let k = 1; k <= ctx.cur[i] && !progress; k *= 2) {
					const cand = [...ctx.cur];
					cand[i] -= k; cand[j] += k;
					if (shrink_step(g, prop_fn, ctx, cand)) progress = true;
				}
			}
		}
	}
	return { choices: ctx.cur, evals: ctx.evals, capped: ctx.capped };
}

function persist_dir() {
	const base = replace(root.test_file || "", /\/[^\/]+$/, "") || ".";
	return base + "/.utest/property";
}

function str_hash(s) {
	let h = 0;
	for (let i = 0; i < length(s); i++)
		h = (h * 31 + ord(substr(s, i, 1))) % 0x7fffffff;
	return h;
}

function persist_filename(test_name) {
	let slug = "";
	for (let i = 0; i < length(test_name) && length(slug) < 40; i++) {
		const c = substr(test_name, i, 1);
		const code = ord(c);
		const ok = (code >= 48 && code <= 57)
		        || (code >= 65 && code <= 90)
		        || (code >= 97 && code <= 122);
		if (ok) slug += c;
		else if (length(slug) > 0 && substr(slug, length(slug) - 1, 1) !== "_") slug += "_";
	}
	while (length(slug) > 0 && substr(slug, length(slug) - 1, 1) === "_")
		slug = substr(slug, 0, length(slug) - 1);
	return slug + "_" + sprintf("%08x", str_hash(test_name)) + ".json";
}

function persist_path(test_name) {
	return persist_dir() + "/" + persist_filename(test_name);
}

function ensure_persist_dir() {
	return mkdir_p(persist_dir());
}

function save_example(test_name, data) {
	if (!ensure_persist_dir()) return null;
	const path = persist_path(test_name);
	try {
		const f = fs.open(path, "w");
		if (!f) return null;
		f.write(sprintf('%J', data));
		f.close();
		return path;
	} catch (_) { return null; }
}

function load_example(test_name) {
	const path = persist_path(test_name);
	try {
		if (!fs.access(path, "r")) return null;
		const f = fs.open(path, "r");
		if (!f) return null;
		const content = f.read("all");
		f.close();
		return json(content);
	} catch (_) { return null; }
}

function delete_example(test_name) {
	try { fs.unlink(persist_path(test_name)); } catch (_) {}
}

function make_ctx(stats) {
	return {
		classify: function(label, cond) {
			if (cond === false) return;
			stats.classifications[label] = (stats.classifications[label] ?? 0) + 1;
		}
	};
}

function fmt_stats(stats, runs) {
	const lines = [];
	if (stats.discards > 0)
		push(lines, sprintf("  Discards: %d (filter rejections)", stats.discards));
	const ks = keys(stats.classifications);
	if (length(ks) > 0) {
		push(lines, "  Coverage:");
		for (let k in ks) {
			const pct = (stats.classifications[k] * 100) / runs;
			push(lines, sprintf("    %-20s %d (%d%%)", k, stats.classifications[k], pct));
		}
	}
	return join("\n", lines);
}

function indent_continuation(s, n) {
	let pad = "";
	for (let i = 0; i < n; i++) pad += " ";
	return replace(s, "\n", "\n" + pad);
}

function report_failure(info, runs) {
	const lines = [];
	if (info.replayed) {
		push(lines, "Property failed (replayed saved counterexample)");
		push(lines, sprintf("  Replayed from:  %s", info.persist_path));
		if (info.saved_at)
			push(lines, sprintf("  Saved at:       %d (epoch seconds)", info.saved_at));
		push(lines, sprintf("  Seed:           %d", info.seed));
		push(lines, sprintf("  Value:          %J", info.shrunk_value));
		push(lines, "  Error:          " + indent_continuation(parse_thrown(info.error).message, 18));
	} else {
		push(lines, sprintf("Property failed after %d case(s)", info.cases_tried));
		push(lines, sprintf("  Seed:           %d", info.seed));
		push(lines, sprintf("  Original value: %J", info.original_value));
		push(lines, sprintf("  Shrunk value:   %J", info.shrunk_value));
		push(lines, sprintf("  Shrink evals:   %d%s",
			info.shrink_evals,
			info.shrink_capped ? " (capped — may not be minimal)" : ""));
		push(lines, "  Error:          " + indent_continuation(parse_thrown(info.error).message, 18));
		if (info.persist_path)
			push(lines, sprintf("  Saved to:       %s (will replay on next run)", info.persist_path));
		const s = fmt_stats(info.stats, runs);
		if (length(s) > 0) push(lines, s);
	}
	die(sprintf('%J', { __utest__: { kind: 'fail', message: join("\n", lines) } }));
}

/**
 * Labels a generated test case for coverage statistics. The first argument
 * is the label to record (e.g. "empty array", "negative number"). The
 * optional second argument is a condition; pass `false` (strictly) to
 * suppress recording for this run. Omitting it or passing `true` always
 * records. Other falsy values (0, null) are treated as "record".
 *
 * @typedef {function(string, ?boolean): void} ClassifyFn
 */

/**
 * @typedef {{classify: ClassifyFn}} PropertyContext
 */

/**
 * Executes a property test iteratively against generated values.
 * 
 * @template T
 * @param {Generator<T>} generator - The generator to produce values.
 * @param {function(T, PropertyContext): void} prop_fn - The property test logic.
 * @param {Object} [opts] - Execution options.
 * @param {int} [opts.runs=100] - Number of successful cases to test.
 * @param {int} [opts.shrink_max=1000] - Maximum property evaluations during shrinking.
 * @param {int} [opts.seed] - Fixed random seed for reproduction.
 * @param {string} [opts.persist_id] - Unique ID for saving/replaying failing cases.
 * @param {boolean} [opts.persist=true] - Whether to save and replay failing cases.
 */
export function forall(generator, prop_fn, opts) {
	opts ??= {};
	const runs       = opts.runs       ?? 100;
	const shrink_max = opts.shrink_max ?? 1000;
	const persist_id = opts.persist_id ?? null;
	const persist    = (persist_id !== null) && (opts.persist !== false);
	const t = clock();
	const id_hash    = (persist_id !== null) ? str_hash(persist_id) : 0;
	const base_seed  = (opts.seed !== null)
	                 ? opts.seed
	                 : (root.prop_seed !== null ? (root.prop_seed ^ id_hash) : (t[0] * 1000000000 + t[1]));
	const stats = { classifications: {}, discards: 0 };
	const ctx = make_ctx(stats);

	// Replay any saved counterexample first; drop it if it now passes or is stale.
	if (persist) {
		const saved = load_example(persist_id);
		if (saved && type(saved.choices) === 'array') {
			const r = try_choices(generator, prop_fn, saved.choices);
			if (r.kind === 'fail') {
				report_failure({
					replayed: true,
					persist_path: persist_path(persist_id),
					saved_at: saved.saved_at,
					seed: saved.seed,
					shrunk_value: r.value,
					error: r.error
				}, runs);
			}
			if (r.kind === 'invalid') {
				warn(sprintf("[utest] forall: saved counterexample for '%s' is stale (generator overrun or filter exhausted); dropping and re-running from scratch\n", persist_id));
			}
			delete_example(persist_id);
		}
	}

	for (let i = 0; i < runs; i++) {
		const seed = base_seed + i;
		const s = record_source(seed);
		let value;
		try { value = generator.generate(s); }
		catch (e) {
			if (utest_kind(e) === 'property_discard') { stats.discards++; continue; }
			die(e);
		}
		try { prop_fn(value, ctx); }
		catch (e) {
			if (is_property_sentinel(utest_kind(e))) { stats.discards++; continue; }
			const shrunk = shrink(generator, prop_fn, s.choices, shrink_max);
			const replay = try_choices(generator, prop_fn, shrunk.choices);
			const shrunk_value = (replay.kind === 'fail') ? replay.value : '<unreproducible>';
			// Use the error from the shrunk replay — the original references the unshrunken value.
			const reported_error = (replay.kind === 'fail') ? replay.error : e;
			let saved_path = null;
			if (persist) {
				const failure_t = clock();
				saved_path = save_example(persist_id, {
					test:     persist_id,
					seed:     seed,
					choices:  shrunk.choices,
					saved_at: failure_t[0]
				});
			}
			report_failure({
				cases_tried: i + 1,
				seed,
				original_value: value,
				shrunk_value,
				shrink_evals: shrunk.evals,
				shrink_capped: shrunk.capped,
				stats,
				error: reported_error,
				persist_path: saved_path
			}, runs);
		}
	}
};

// Qualifies persist_id with file + describe path so identically-named props
// in different files or describes don't share a persistence file.
function current_describe_path() {
	const parts = [];
	for (let i = 0; i < length(stack); i++)
		if (stack[i].id !== 0) push(parts, stack[i].name);
	return join(" > ", parts);
}

/**
 * Defines a property test case as an `it` block.
 * 
 * @template T
 * @param {string} name - The name of the property.
 * @param {Generator<T>} generator - The generator to produce values.
 * @param {function(T, PropertyContext): void} prop_fn - The property test logic.
 * @param {Object} [opts] - Execution options.
 * @param {int} [opts.runs=100] - Number of successful cases to test.
 * @param {int} [opts.shrink_max=1000] - Maximum property evaluations during shrinking.
 * @param {int} [opts.seed] - Fixed random seed for reproduction.
 * @param {string} [opts.persist_id] - Unique ID for saving/replaying failing cases.
 * @param {boolean} [opts.persist=true] - Whether to save and replay failing cases.
 */
export function prop(name, generator, prop_fn, opts) {
	opts ??= {};
	const effective = { persist_id: null, ...opts };
	if (effective.persist_id === null) {
		const file = root.test_file || "";
		const path = current_describe_path();
		const prefix = (file !== "" ? file + " :: " : "")
		             + (path !== "" ? path + " > " : "");
		effective.persist_id = prefix + name;
	}
	dsl.it(name, function() { forall(generator, prop_fn, effective); });
};
