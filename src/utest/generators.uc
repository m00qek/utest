// Source contract: generators MUST read randomness only through source.draw(bound),
// never via math.rand() directly — bypassing the source silently corrupts shrinking.

// Thrown by gen.filter when the predicate fails `attempts` times in a row;
// caught and counted as a discarded case by forall.
const DISCARD_MSG = sprintf('%J', { __utest__: { kind: 'property_discard' } });

const Generator = { __utest__: { kind: 'generator' } };

function gen_from(fn) { return proto({ generate: fn }, Generator); }

export function is_generator(v) {
	return type(v) == 'object' && v.__utest__ && v.__utest__.kind == 'generator';
};

// Small draws map to values near the "zero point" — the endpoint of [lo, hi]
// closest to 0 — so gen.int(-100, 100) shrinks toward 0, not toward -100.
function int_gen(lo, hi) {
	if (lo > hi) die(sprintf("gen.int: lo (%d) must be <= hi (%d)", lo, hi));
	const span = hi - lo + 1;
	const zp = (lo > 0) ? lo : ((hi < 0) ? hi : 0);
	const pos_room = hi - zp;
	return gen_from(function(source) {
		const d = source.draw(span);
		if (d <= pos_room) return zp + d;
		return zp - (d - pos_room);
	});
}

function bool_gen() {
	return gen_from(function(source) { return source.draw(2) == 1; });
}

// Same zero-point shrinking as int_gen; precision controls the number of
// discrete steps across [lo, hi], split proportionally between each side.
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
	return gen_from(function(source) {
		const d = source.draw(precision + 1);
		if (total <= 0) return zp;
		if (d <= pos_quota) {
			if (pos_quota == 0) return zp;
			return zp + (d / (pos_quota * 1.0)) * pos_room;
		}
		return zp - ((d - pos_quota) / (neg_quota * 1.0)) * neg_room;
	});
}

function constant_gen(v) {
	return gen_from(function(_source) { return v; });
}

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

function array_gen(elem, opts) {
	const sz = size_from_opts(opts, "gen.array");
	return gen_from(function(source) {
		const n = sz.min_len + source.draw(sz.max_len - sz.min_len + 1);
		const out = [];
		for (let i = 0; i < n; i++) push(out, elem.generate(source));
		return out;
	});
}

function tuple_gen(...gens) {
	return gen_from(function(source) {
		const out = [];
		for (let generator in gens) push(out, generator.generate(source));
		return out;
	});
}

function record_gen(spec) {
	const ks = keys(spec);
	return gen_from(function(source) {
		const out = {};
		for (let k in ks) out[k] = spec[k].generate(source);
		return out;
	});
}

const STRING_CHARS       = "abcdefghijklmnopqrstuvwxyz0123456789 ";
const ALPHANUMERIC_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
let ASCII_CHARS = null; // built lazily to avoid a 95-char literal at module load
function _ascii_chars() {
	if (ASCII_CHARS == null) {
		let s = "";
		for (let c = 32; c <= 126; c++) s += chr(c);
		ASCII_CHARS = s;
	}
	return ASCII_CHARS;
}

function string_gen(opts) {
	const sz = size_from_opts(opts, "gen.string");
	const charset = (opts.charset != null) ? opts.charset : STRING_CHARS;
	if (length(charset) == 0) die("gen.string: charset must be non-empty");
	return gen_from(function(source) {
		const n = sz.min_len + source.draw(sz.max_len - sz.min_len + 1);
		let out = "";
		for (let i = 0; i < n; i++)
			out += substr(charset, source.draw(length(charset)), 1);
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

function oneof_gen(...gens) {
	if (length(gens) == 0) die("gen.oneof: at least one generator required");
	return gen_from(function(source) { return gens[source.draw(length(gens))].generate(source); });
}

function elements_gen(...arr) {
	if (length(arr) == 0) die("gen.elements: at least one value required");
	return gen_from(function(source) { return arr[source.draw(length(arr))]; });
}

// List the simplest alternative first — smaller draws select earlier entries,
// so shrinking naturally converges toward simpler values.
function frequency_gen(...pairs) {
	let total = 0;
	for (let p in pairs) total += p[0];
	if (total <= 0) die("gen.frequency: weights must sum to a positive value");
	return gen_from(function(source) {
		let pick = source.draw(total);
		for (let p in pairs) {
			if (pick < p[0]) return p[1].generate(source);
			pick -= p[0];
		}
		die("gen.frequency: unreachable — weight bookkeeping broken");
	});
}

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

function map_gen(generator, fn) {
	return gen_from(function(source) { return fn(generator.generate(source)); });
}

function bind_gen(generator, fn) {
	return gen_from(function(source) {
		const a = generator.generate(source);
		return fn(a).generate(source);
	});
}

function filter_gen(generator, pred, opts) {
	const attempts = (opts != null && opts.attempts != null) ? opts.attempts : 32;
	if (attempts < 1) die(sprintf("gen.filter: attempts (%d) must be >= 1", attempts));
	return gen_from(function(source) {
		for (let i = 0; i < attempts; i++) {
			const v = generator.generate(source);
			if (pred(v)) return v;
		}
		die(DISCARD_MSG);
	});
}

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
