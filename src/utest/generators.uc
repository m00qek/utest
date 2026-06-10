// Generators for property-based testing.  Each generator is an object with a
// `generate(source)` method that draws random values via `source.draw(bound)`.
//
// Source contract: every generator MUST read randomness only through
// `source.draw(bound)`, never via math.rand() directly.  Bypassing the source
// breaks recording and replay of the choice sequence, which silently corrupts
// shrinking.
//
// This module only DEFINES generators.  The recordable source, replay, the
// shrinker, persistence, and the prop DSL all live in utest.property.

// Filter rejection sentinel.  Thrown by gen.filter when the predicate fails
// `attempts` times in a row; caught and counted as a discarded case by forall.
// We wrap it in the standard __utest__ envelope so user-side try/catch that
// inspects exceptions can detect framework-internal throws.
const DISCARD_MSG = sprintf('%J', { __utest__: { kind: 'property_discard' } });

// ─── Generator prototype ─────────────────────────────────────────────────────

const Generator = { __utest__: { kind: 'generator' } };

function gen_from(fn) { return proto({ generate: fn }, Generator); }

export function is_generator(v) {
	return type(v) == 'object' && v.__utest__ && v.__utest__.kind == 'generator';
};

// ─── Primitives ──────────────────────────────────────────────────────────────

// Draws are encoded so small draws map to values close to the "zero point" —
// the endpoint of [lo, hi] closest to 0 (or 0 itself if it lies in range).
// Draws 0..pos_room cover zp, zp+1, ..., hi (non-negative side).
// Draws pos_room+1..span-1 cover zp-1, zp-2, ..., lo (negative side).
// So gen.int(-100, 100) shrinks toward 0, not toward -100.
function int_gen(lo, hi) {
	if (lo > hi) die(sprintf("gen.int: lo (%d) must be <= hi (%d)", lo, hi));
	const span = hi - lo + 1;
	const zp = (lo > 0) ? lo : ((hi < 0) ? hi : 0);
	const pos_room = hi - zp;
	return gen_from(function(s) {
		const d = s.draw(span);
		if (d <= pos_room) return zp + d;
		return zp - (d - pos_room);
	});
}

function bool_gen() {
	return gen_from(function(s) { return s.draw(2) == 1; });
}

// Same zero-point idea as int_gen: small draws map to values near 0 (or
// the endpoint closest to 0 if 0 isn't in range).  Precision is split between
// the positive and negative sides proportionally to their room.
// opts: { precision? }
function float_gen(lo, hi, opts) {
	if (lo > hi) die(sprintf("gen.float: lo (%g) must be <= hi (%g)", lo, hi));
	const precision = (opts != null && opts.precision != null) ? opts.precision : 10000;
	if (precision < 1) die(sprintf("gen.float: precision (%d) must be >= 1", precision));
	const zp = (lo > 0) ? lo : ((hi < 0) ? hi : 0.0);
	const pos_room = hi - zp;
	const neg_room = zp - lo;
	const total = pos_room + neg_room;
	const pos_quota = (total <= 0) ? 0 :
	                  (neg_room == 0) ? precision :
	                  int(precision * pos_room / (total * 1.0));
	const neg_quota = precision - pos_quota;
	return gen_from(function(s) {
		const d = s.draw(precision + 1);
		if (total <= 0) return zp;
		if (d <= pos_quota) {
			if (pos_quota == 0) return zp;
			return zp + (d / (pos_quota * 1.0)) * pos_room;
		}
		return zp - ((d - pos_quota) / (neg_quota * 1.0)) * neg_room;
	});
}

function constant_gen(v) {
	return gen_from(function(_s) { return v; });
}

// ─── Sizing helper (shared by array + string family) ─────────────────────────

// Parses size opts for gen.array / gen.string.  Returns { min_len, max_len }.
// Accepts either { len } (fixed length) or { max_len, min_len? } (range).
function size_from_opts(opts, name) {
	if (opts == null) die(name + ": opts required ({ max_len } or { len })");
	if (opts.len != null) {
		if (opts.min_len != null || opts.max_len != null)
			die(name + ": cannot combine 'len' with 'min_len' / 'max_len'");
		if (opts.len < 0)
			die(sprintf("%s: len (%d) must be >= 0", name, opts.len));
		return { min_len: opts.len, max_len: opts.len };
	}
	if (opts.max_len == null)
		die(name + ": opts.max_len or opts.len required");
	const min_provided = (opts.min_len != null);
	const min_len = opts.min_len ?? 0;
	if (min_len < 0)
		die(sprintf("%s: min_len (%d) must be >= 0", name, min_len));
	if (opts.max_len < min_len) {
		if (min_provided)
			die(sprintf("%s: max_len (%d) must be >= min_len (%d)", name, opts.max_len, min_len));
		else
			die(sprintf("%s: max_len (%d) must be >= 0", name, opts.max_len));
	}
	return { min_len, max_len: opts.max_len };
}

// ─── Containers ──────────────────────────────────────────────────────────────

function array_gen(elem, opts) {
	const sz = size_from_opts(opts, "gen.array");
	return gen_from(function(s) {
		const n = sz.min_len + s.draw(sz.max_len - sz.min_len + 1);
		const out = [];
		for (let i = 0; i < n; i++) push(out, elem.generate(s));
		return out;
	});
}

function tuple_gen(...gens) {
	return gen_from(function(s) {
		const out = [];
		for (let g in gens) push(out, g.generate(s));
		return out;
	});
}

function record_gen(spec) {
	const ks = keys(spec);
	return gen_from(function(s) {
		const out = {};
		for (let k in ks) out[k] = spec[k].generate(s);
		return out;
	});
}

// ─── Strings ─────────────────────────────────────────────────────────────────

const STRING_CHARS       = "abcdefghijklmnopqrstuvwxyz0123456789 ";
const ALPHANUMERIC_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
// Printable ASCII (chr 32..126).  Built lazily on first use to avoid a 95-char
// module-load literal; we keep it as a module-level const after the first call.
let ASCII_CHARS = null;
function _ascii_chars() {
	if (ASCII_CHARS == null) {
		let s = "";
		for (let c = 32; c <= 126; c++) s += chr(c);
		ASCII_CHARS = s;
	}
	return ASCII_CHARS;
}

// gen.string(opts) — opts: { max_len | len | min_len+max_len, charset? }.
// Default charset is lowercase + digits + space.
function string_gen(opts) {
	const sz = size_from_opts(opts, "gen.string");
	const charset = (opts.charset != null) ? opts.charset : STRING_CHARS;
	if (length(charset) == 0) die("gen.string: charset must be non-empty");
	return gen_from(function(s) {
		const n = sz.min_len + s.draw(sz.max_len - sz.min_len + 1);
		let out = "";
		for (let i = 0; i < n; i++)
			out += substr(charset, s.draw(length(charset)), 1);
		return out;
	});
}

function with_locked_charset(opts, charset, name) {
	opts ??= {};
	if (opts.charset != null)
		die(name + ": 'charset' not allowed; use gen.string for custom charsets");
	const merged = { ...opts };
	merged.charset = charset;
	return merged;
}

function alphanumeric_gen(opts) { return string_gen(with_locked_charset(opts, ALPHANUMERIC_CHARS, "gen.alphanumeric")); }
function ascii_gen(opts)        { return string_gen(with_locked_charset(opts, _ascii_chars(),    "gen.ascii"));        }

// ─── Choice ──────────────────────────────────────────────────────────────────

function oneof_gen(...gens) {
	if (length(gens) == 0) die("gen.oneof: at least one generator required");
	return gen_from(function(s) { return gens[s.draw(length(gens))].generate(s); });
}

function elements_gen(...arr) {
	if (length(arr) == 0) die("gen.elements: at least one value required");
	return gen_from(function(s) { return arr[s.draw(length(arr))]; });
}

// Each pair is [weight, gen].  Smaller draws select earlier entries, so list
// the simplest alternative first to make shrinking helpful.
function frequency_gen(...pairs) {
	let total = 0;
	for (let p in pairs) total += p[0];
	if (total <= 0) die("gen.frequency: weights must sum to a positive value");
	return gen_from(function(s) {
		let pick = s.draw(total);
		for (let p in pairs) {
			if (pick < p[0]) return p[1].generate(s);
			pick -= p[0];
		}
		die("gen.frequency: unreachable — weight bookkeeping broken");
	});
}

// opts: { none_weight?, some_weight? } — relative weights; both default to 1 (50/50).
function optional_gen(g, opts) {
	opts ??= {};
	const none_weight = opts.none_weight ?? 1;
	const some_weight = opts.some_weight ?? 1;
	if (none_weight < 0 || some_weight < 0)
		die("gen.optional: weights must be non-negative");
	if (none_weight == 0 && some_weight == 0)
		die("gen.optional: at least one weight must be > 0");
	return frequency_gen([none_weight, constant_gen(null)], [some_weight, g]);
}

// ─── Combinators ─────────────────────────────────────────────────────────────

function map_gen(g, f) {
	return gen_from(function(s) { return f(g.generate(s)); });
}

function bind_gen(g, f) {
	return gen_from(function(s) {
		const a = g.generate(s);
		return f(a).generate(s);
	});
}

// opts: { attempts? } — re-roll budget per case, default 32.
function filter_gen(g, pred, opts) {
	const attempts = (opts != null && opts.attempts != null) ? opts.attempts : 32;
	if (attempts < 1) die(sprintf("gen.filter: attempts (%d) must be >= 1", attempts));
	return gen_from(function(s) {
		for (let i = 0; i < attempts; i++) {
			const v = g.generate(s);
			if (pred(v)) return v;
		}
		die(DISCARD_MSG);
	});
}

// ─── Export ──────────────────────────────────────────────────────────────────

export const gen = {
	int:          int_gen,
	bool:         bool_gen,
	float:        float_gen,
	array:        array_gen,
	string:       string_gen,
	ascii:        ascii_gen,
	alphanumeric: alphanumeric_gen,
	tuple:        tuple_gen,
	record:       record_gen,
	oneof:        oneof_gen,
	frequency:    frequency_gen,
	elements:     elements_gen,
	constant:     constant_gen,
	optional:     optional_gen,
	map:          map_gen,
	bind:         bind_gen,
	filter:       filter_gen
};
