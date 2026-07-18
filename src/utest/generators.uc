/**
 * Generator factories for property-based testing.
 * All generators must read randomness only through `source.draw(bound)`,
 * never via `math.rand()` directly — bypassing the source silently corrupts shrinking.
 *
 * @module utest.generators
 */

import * as math from 'math';

// Thrown by gen.filter when the predicate fails `attempts` times in a row;
// caught and counted as a discarded case by forall.
const DISCARD_MSG = sprintf('%J', { __utest__: { kind: 'property_discard' } });

// A float bound is usable only if finite. Detect NaN via math.isnan (the reliable
// test — never eyeball it through a comparison, whose result varies) and catch
// +/-Inf too, since Inf - Inf is NaN while any finite x - x is 0.
function is_finite_num(x) { return !math.isnan(x) && !math.isnan(x - x); }

// Capture before export function int() shadows it — float() uses int() to truncate.
const _int = int;

/**
 * @typedef {{ draw: function(int): int, choices: int[], seed: int | null }} RandomSource
 */

/**
 * @template T
 * @typedef {{ generate: function(RandomSource): T }} Generator
 */
const Generator = { __utest__: { kind: 'generator' } };

function gen_from(fn) { return proto({ generate: fn }, Generator); }

/**
 * Checks if a value is a valid utest generator.
 *
 * @param {any} v - The value to check.
 * @returns {boolean} True if the value is a generator.
 */
export function is_generator(v) {
	return type(v) === 'object' && v.__utest__ && v.__utest__.kind === 'generator';
};

// Small draws map to values near the "zero point" — the endpoint of [lo, hi]
// closest to 0 — so gen.int(-100, 100) shrinks toward 0, not toward -100.
/**
 * Generates an integer in the inclusive range [lo, hi], shrinking toward 0.
 * The distribution is near-uniform but deliberately over-samples the zero-point
 * (the in-range value closest to 0) so boundary cases are hit more often.
 *
 * @example
 * forall(gen.int(1, 100), n => {
 *     assert.match(between(1, 100), n);
 * });
 *
 * @param {int} lo - The minimum bound.
 * @param {int} hi - The maximum bound.
 * @returns {Generator<int>} The configured generator.
 */
export function int(lo, hi) {
	// Require integer bounds. A NaN bound (e.g. gen.int(0, sqrt(-1))) would slip
	// past every range guard below — all NaN comparisons are false — and make
	// `bits % NaN` NaN, so every draw is NaN and the property passes vacuously.
	// A double bound (gen.int(1.5, 10)) draws via a non-integer span and can
	// return values below lo. Rejecting non-ints closes both.
	if (type(lo) !== 'int' || type(hi) !== 'int')
		die(sprintf("gen.int: bounds must be integers; got lo (%s), hi (%s)", type(lo), type(hi)));
	if (lo > hi) die(sprintf("gen.int: lo (%d) must be <= hi (%d)", lo, hi));
	const span = hi - lo + 1;
	// draw() produces 62-bit values, so a span wider than 2^62 can't be sampled
	// across its whole range, and a span for a range >= 2^63 overflows int64 to
	// <= 0 (which would otherwise degenerate to always-0). Reject both rather than
	// silently truncate or collapse. Realistic ranges are nowhere near this.
	if (span <= 0 || span > (1 << 62))
		die(sprintf("gen.int: range [%d, %d] is too wide to sample; span must be <= 2^62", lo, hi));
	const zp = (lo > 0) ? lo : ((hi < 0) ? hi : 0);
	const pos_room = hi - zp;
	return gen_from(function(source) {
		const d = source.draw(span);
		if (d <= pos_room) return zp + d;
		return zp - (d - pos_room);
	});
};

/**
 * Generates a boolean value (true or false).
 *
 * @example
 * forall(gen.bool(), b => {
 *     assert.match(is_type('boolean'), b);
 * });
 *
 * @returns {Generator<boolean>} The configured generator.
 */
export function bool() {
	return gen_from(function(source) { return source.draw(2) === 1; });
};

// Same zero-point shrinking as int; precision controls the number of
// discrete steps across [lo, hi], split proportionally between each side.
/**
 * Generates a floating-point number in the inclusive range [lo, hi].
 * Shrinks toward 0.
 *
 * @example
 * forall(gen.float(0.0, 1.0), x => {
 *     assert.match(between(0.0, 1.0), x);
 * });
 *
 * @param {float} lo - The minimum bound.
 * @param {float} hi - The maximum bound.
 * @param {dict<any>} [opts] - Configuration options.
 * @param {int} [opts.precision=10000] - The number of discrete steps across the range.
 * @returns {Generator<float>} The configured generator.
 */
export function float(lo, hi, opts) {
	if (!is_finite_num(lo) || !is_finite_num(hi))
		die(sprintf("gen.float: bounds must be finite; got lo (%g), hi (%g)", lo, hi));
	if (lo > hi) die(sprintf("gen.float: lo (%g) must be <= hi (%g)", lo, hi));
	const precision = (opts !== null && opts.precision !== null) ? opts.precision : 10000;
	if (type(precision) !== 'int')
		die(sprintf("gen.float: precision must be an integer, got %s", type(precision)));
	if (precision < 1) die(sprintf("gen.float: precision (%d) must be >= 1", precision));
	// Force double arithmetic so an all-int range (e.g. gen.float(3, 3)) still
	// yields a double. Otherwise a degenerate range returns zp unchanged as an int,
	// which then fails is_type('double')/equals(3.0) in a framework that
	// deliberately distinguishes 3 from 3.0.
	lo *= 1.0; hi *= 1.0;
	const zp = (lo > 0) ? lo : ((hi < 0) ? hi : 0.0);
	const pos_room = hi - zp;
	const neg_room = zp - lo;
	const total = pos_room + neg_room;
	// Clamp to 1 so a non-zero pos_room (or neg_room) always gets at least one
	// draw slot — without this, _int() truncation erases the smaller side entirely
	// when pos_room / total < 1/precision (e.g. gen.float(-1000, 0.001)).
	const pos_quota_raw = (total <= 0) ? 0 :
	                      (neg_room === 0) ? precision :
	                      _int(precision * pos_room / (total * 1.0));
	const pos_quota = (pos_room > 0 && pos_quota_raw === 0) ? 1 : pos_quota_raw;
	const neg_quota = precision - pos_quota;
	return gen_from(function(source) {
		const d = source.draw(precision + 1);
		if (total <= 0) return zp;
		if (pos_quota > 0 && d <= pos_quota) {
			return zp + (d / (pos_quota * 1.0)) * pos_room;
		}
		return zp - ((d - pos_quota) / (neg_quota * 1.0)) * neg_room;
	});
};

/**
 * Generates a constant value unconditionally.
 * Useful as a fixed alternative inside gen.oneof or gen.frequency.
 *
 * @example
 * forall(gen.oneof(gen.int(0, 99), gen.constant(null)), v => {
 *     assert.match(pred(x => x === null || type(x) === 'int'), v);
 * });
 *
 * @template T
 * @param {T} v - The value to constantly generate.
 * @returns {Generator<T>} The configured generator.
 */
export function constant(v) {
	return gen_from(function(_source) { return v; });
};

function size_from_opts(opts, name) {
	if (opts === null) die(name + ": opts required ({ max_len } or { len })");
	const len     = opts.len     ?? null;
	const min_len = opts.min_len ?? null;
	const max_len = opts.max_len ?? null;
	// Reject non-integer sizes before the comparisons below: a double like 2.5
	// otherwise slips through `< 0` / `< min_val` and yields an off-by-one length
	// (i < 2.5 admits i = 0,1,2) or feeds a fractional bound into the draw stream.
	for (let pair in [["len", len], ["min_len", min_len], ["max_len", max_len]])
		if (pair[1] !== null && type(pair[1]) !== 'int')
			die(sprintf("%s: %s must be an integer, got %s", name, pair[0], type(pair[1])));
	if (len !== null) {
		if (min_len !== null || max_len !== null)
			die(name + ": cannot combine 'len' with 'min_len' / 'max_len'");
		if (len < 0)
			die(sprintf("%s: len (%d) must be >= 0", name, len));
		return { min_len: len, max_len: len };
	}
	if (max_len === null)
		die(name + ": opts.max_len or opts.len required");
	const min_provided = (min_len !== null);
	const min_val = min_len ?? 0;
	if (min_val < 0)
		die(sprintf("%s: min_len (%d) must be >= 0", name, min_val));
	if (max_len < min_val) {
		if (min_provided)
			die(sprintf("%s: max_len (%d) must be >= min_len (%d)", name, max_len, min_val));
		else
			die(sprintf("%s: max_len (%d) must be >= 0", name, max_len));
	}
	return { min_len: min_val, max_len };
}

/**
 * Generates an array of elements drawn from a given generator.
 *
 * @example
 * forall(gen.array(gen.int(0, 9), { max_len: 5 }), arr => {
 *     assert.match(pred(a => length(a) <= 5), arr);
 * });
 * // Exact length:
 * forall(gen.array(gen.bool(), { len: 3 }), arr => {
 *     assert.match(has_length(3), arr);
 * });
 *
 * @template T
 * @param {Generator<T>} elem - The generator for individual elements.
 * @param {dict<any>} opts - Sizing options.
 * @param {int} [opts.len] - The exact length.
 * @param {int} [opts.min_len] - The minimum length (inclusive).
 * @param {int} [opts.max_len] - The maximum length (inclusive).
 * @returns {Generator<T[]>} The configured generator.
 */
export function array(elem, opts) {
	const sz = size_from_opts(opts, "gen.array");
	return gen_from(function(source) {
		const n = sz.min_len + source.draw(sz.max_len - sz.min_len + 1);
		const out = [];
		for (let i = 0; i < n; i++) push(out, elem.generate(source));
		return out;
	});
};

/**
 * Generates a tuple (array) with elements drawn from specific generators per position.
 *
 * @example
 * forall(gen.tuple(gen.int(0, 10), gen.bool()), pair => {
 *     assert.match(is_type('int'),     pair[0]);
 *     assert.match(is_type('boolean'), pair[1]);
 * });
 *
 * @param {...Generator} gens - The generators for each position.
 * @returns {Generator<any[]>} The configured generator.
 */
export function tuple(...gens) {
	return gen_from(function(source) {
		const out = [];
		for (let generator in gens) push(out, generator.generate(source));
		return out;
	});
};

/**
 * Generates an object matching a specific schema of keys and generators.
 *
 * @example
 * forall(gen.record({ id: gen.int(1, 100), active: gen.bool() }), obj => {
 *     assert.match(contains({ id: between(1, 100) }), obj);
 * });
 *
 * @param {dict<Generator<any>>} spec - A map of keys to generators.
 * @returns {Generator<dict<any>>} The configured generator.
 */
export function record(spec) {
	const ks = keys(spec);
	return gen_from(function(source) {
		const out = {};
		for (let k in ks) out[k] = spec[k].generate(source);
		return out;
	});
};

const STRING_CHARS       = "abcdefghijklmnopqrstuvwxyz0123456789 ";
const ALPHANUMERIC_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
let ASCII_CHARS = null; // built lazily to avoid a 95-char literal at module load
function _ascii_chars() {
	if (ASCII_CHARS === null) {
		let s = "";
		for (let c = 32; c <= 126; c++) s += chr(c);
		ASCII_CHARS = s;
	}
	return ASCII_CHARS;
}

/**
 * Generates a string.
 *
 * @example
 * forall(gen.string({ max_len: 20 }), s => {
 *     assert.match(is_type('string'), s);
 * });
 * // Custom charset (e.g. binary strings):
 * forall(gen.string({ len: 8, charset: "01" }), s => {
 *     assert.match(regex(/^[01]{8}$/), s);
 * });
 *
 * @param {dict<any>} opts - Sizing options.
 * @param {int} [opts.len] - The exact length.
 * @param {int} [opts.min_len] - The minimum length.
 * @param {int} [opts.max_len] - The maximum length.
 * @param {string} [opts.charset] - The character set to sample from.
 * @returns {Generator<string>} The configured generator.
 */
// The shared string builder. `name` is threaded through so a sizing error from
// gen.alphanumeric/gen.ascii reports its own name, not "gen.string".
function build_string(opts, name) {
	const sz = size_from_opts(opts, name);
	const charset = ((opts.charset ?? null) !== null) ? opts.charset : STRING_CHARS;
	if (length(charset) === 0) die(name + ": charset must be non-empty");
	const clen = length(charset);
	return gen_from(function(source) {
		const n = sz.min_len + source.draw(sz.max_len - sz.min_len + 1);
		const chars = [];
		for (let i = 0; i < n; i++)
			push(chars, substr(charset, source.draw(clen), 1));
		return join("", chars);
	});
}

/**
 * Generates a string. By default the charset is lowercase letters, digits, and
 * space; pass `opts.charset` to draw from a custom set of characters.
 *
 * @example
 * forall(gen.string({ min_len: 1, max_len: 8 }), s => assert.match(is_type('string'), s));
 * forall(gen.string({ len: 4, charset: 'ACGT' }), s => assert.match(regex(/^[ACGT]{4}$/), s));
 *
 * @param {dict<any>} opts - Sizing options, plus an optional charset.
 * @param {int} [opts.len] - The exact length.
 * @param {int} [opts.min_len] - The minimum length.
 * @param {int} [opts.max_len] - The maximum length.
 * @param {string} [opts.charset] - Characters to draw from (default: lowercase, digits, space).
 * @returns {Generator<string>} The configured generator.
 */
export function string(opts) {
	return build_string(opts, "gen.string");
};

function with_locked_charset(opts, charset, name) {
	opts ??= {};
	if ((opts.charset ?? null) !== null)
		die(name + ": 'charset' not allowed; use gen.string for custom charsets");
	const merged = { ...opts };
	merged.charset = charset;
	return merged;
}

/**
 * Generates a string consisting of alphanumeric characters.
 *
 * @example
 * forall(gen.alphanumeric({ max_len: 10 }), s => {
 *     assert.match(regex(/^[a-zA-Z0-9]*$/), s);
 * });
 *
 * @param {dict<any>} opts - Sizing options.
 * @param {int} [opts.len] - The exact length.
 * @param {int} [opts.min_len] - The minimum length.
 * @param {int} [opts.max_len] - The maximum length.
 * @returns {Generator<string>} The configured generator.
 */
export function alphanumeric(opts) { return build_string(with_locked_charset(opts, ALPHANUMERIC_CHARS, "gen.alphanumeric"), "gen.alphanumeric"); };

/**
 * Generates a string consisting of visible ASCII characters (codepoints 32–126).
 *
 * @example
 * forall(gen.ascii({ min_len: 1, max_len: 50 }), s => {
 *     assert.match(not(equals("")), s);
 * });
 *
 * @param {dict<any>} opts - Sizing options.
 * @param {int} [opts.len] - The exact length.
 * @param {int} [opts.min_len] - The minimum length.
 * @param {int} [opts.max_len] - The maximum length.
 * @returns {Generator<string>} The configured generator.
 */
export function ascii(opts)        { return build_string(with_locked_charset(opts, _ascii_chars(),    "gen.ascii"), "gen.ascii"); };

/**
 * Randomly picks one generator from the provided choices and generates a value from it.
 * Each alternative is equally likely. For weighted selection use gen.frequency.
 *
 * @example
 * forall(gen.oneof(gen.int(0, 99), gen.string({ len: 4 })), v => {
 *     assert.match(pred(x => type(x) === 'int' || type(x) === 'string'), v);
 * });
 *
 * @template T
 * @param {...Generator<T>} gens - The generators to choose from.
 * @returns {Generator<T>} The configured generator.
 */
export function oneof(...gens) {
	if (length(gens) === 0) die("gen.oneof: at least one generator required");
	return gen_from(function(source) { return gens[source.draw(length(gens))].generate(source); });
};

/**
 * Generates a value by randomly picking one of the provided constant elements.
 *
 * @example
 * forall(gen.elements("GET", "POST", "PUT", "DELETE"), method => {
 *     assert.match(regex(/^(GET|POST|PUT|DELETE)$/), method);
 * });
 *
 * @template T
 * @param {...T} arr - The constant elements to choose from.
 * @returns {Generator<T>} The configured generator.
 */
export function elements(...arr) {
	if (length(arr) === 0) die("gen.elements: at least one value required");
	return gen_from(function(source) { return arr[source.draw(length(arr))]; });
};

// List the simplest alternative first — smaller draws select earlier entries,
// so shrinking naturally converges toward simpler values.
/**
 * Selects a generator based on relative weights.
 * List simpler alternatives first so shrinking converges toward them.
 *
 * @example
 * // 80% small int, 20% large int
 * forall(gen.frequency([4, gen.int(0, 10)], [1, gen.int(100, 1000)]), n => {
 *     assert.match(between(0, 1000), n);
 * });
 *
 * @template T
 * @param {...any} pairs - Weight/generator pairs; each is `[weight, generator]` where weight is a positive int. List simplest alternatives first.
 * @returns {Generator<T>} The configured generator.
 */
export function frequency(...pairs) {
	let total = 0;
	for (let p in pairs) {
		// A negative weight is silently unreachable and corrupts the selection
		// walk (pick -= weight skews later alternatives), so reject it outright.
		if (type(p[0]) !== 'int' || p[0] < 0)
			die(sprintf("gen.frequency: each weight must be a non-negative integer, got %J", p[0]));
		total += p[0];
	}
	if (total <= 0) die("gen.frequency: weights must sum to a positive value");
	return gen_from(function(source) {
		let pick = source.draw(total);
		for (let p in pairs) {
			if (pick < p[0]) return p[1].generate(source);
			pick -= p[0];
		}
		die("gen.frequency: unreachable — weight bookkeeping broken");
	});
};

/**
 * Generates either null or a value from the provided generator.
 *
 * @example
 * forall(gen.optional(gen.int(1, 10)), v => {
 *     assert.match(pred(x => x === null || type(x) === 'int'), v);
 * });
 * // Bias toward non-null (3:1):
 * gen.optional(gen.string({ max_len: 8 }), { none_weight: 1, some_weight: 3 });
 *
 * @template T
 * @param {Generator<T>} generator - The generator to use.
 * @param {dict<any>} [opts] - Weighting options.
 * @param {int} [opts.none_weight=1] - The relative weight for generating null.
 * @param {int} [opts.some_weight=1] - The relative weight for generating a value.
 * @returns {Generator<T|null>} The configured generator.
 */
export function optional(generator, opts) {
	opts ??= {};
	const none_weight = opts.none_weight ?? 1;
	const some_weight = opts.some_weight ?? 1;
	if (none_weight < 0 || some_weight < 0)
		die("gen.optional: weights must be non-negative");
	if (none_weight === 0 && some_weight === 0)
		die("gen.optional: at least one weight must be > 0");
	return frequency([none_weight, constant(null)], [some_weight, generator]);
};

/**
 * Maps the output of a generator through a transformation function.
 * Prefer gen.map over gen.filter when a direct construction is possible.
 *
 * @example
 * // Generate only even numbers
 * forall(gen.map(gen.int(0, 50), n => n * 2), n => {
 *     assert.match(pred(x => x % 2 === 0), n);
 * });
 *
 * @template T, U
 * @param {Generator<T>} generator - The original generator.
 * @param {function(T): U} fn - The mapping function.
 * @returns {Generator<U>} The configured generator.
 */
export function map(generator, fn) {
	return gen_from(function(source) { return fn(generator.generate(source)); });
};

/**
 * Chains generators: the output of the first generator determines which generator runs next.
 * Use when a later generator's parameters depend on an earlier generated value.
 *
 * @example
 * // Generate an array whose length is itself random
 * forall(gen.bind(gen.int(1, 5), n => gen.array(gen.int(0, 9), { len: n })), arr => {
 *     assert.match(between(1, 5), length(arr));
 * });
 *
 * @template T, U
 * @param {Generator<T>} generator - The primary generator.
 * @param {function(T): Generator<U>} fn - A function that returns a new generator based on the primary value.
 * @returns {Generator<U>} The configured generator.
 */
export function bind(generator, fn) {
	return gen_from(function(source) {
		const a = generator.generate(source);
		return fn(a).generate(source);
	});
};

/**
 * Filters the output of a generator, rejecting values that don't satisfy the predicate.
 *
 * **Shrinking note:** during counterexample minimisation the shrinker replays candidate
 * choice sequences through the full generator, including this filter. A candidate that
 * exhausts `attempts` retries is treated as invalid (not fail, not pass) and skipped,
 * but still consumes a slot from the `shrink_max` evaluation budget. With a narrow
 * predicate this can drain the budget on structurally impossible candidates, causing the
 * reported counterexample to be larger than the true minimum. Prefer `gen.map` or
 * `gen.bind` over `gen.filter` when a direct construction is possible.
 *
 * @example
 * // Only odd numbers (wide predicate, filter is appropriate)
 * forall(gen.filter(gen.int(0, 100), n => n % 2 !== 0), n => {
 *     assert.match(pred(x => x % 2 !== 0), n);
 * });
 *
 * @template T
 * @param {Generator<T>} generator - The base generator.
 * @param {function(T): boolean} pred - The predicate function.
 * @param {dict<any>} [opts] - Filtering options.
 * @param {int} [opts.attempts=32] - Maximum consecutive rejections before aborting.
 * @returns {Generator<T>} The configured generator.
 */
export function filter(generator, pred, opts) {
	const attempts = (opts !== null && opts.attempts !== null) ? opts.attempts : 32;
	if (type(attempts) !== 'int')
		die(sprintf("gen.filter: attempts must be an integer, got %s", type(attempts)));
	if (attempts < 1) die(sprintf("gen.filter: attempts (%d) must be >= 1", attempts));
	return gen_from(function(source) {
		for (let i = 0; i < attempts; i++) {
			const v = generator.generate(source);
			if (pred(v)) return v;
		}
		die(DISCARD_MSG);
	});
};
