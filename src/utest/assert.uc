import { parse_thrown } from 'utest.util';

// ─── Combinator prototype ────────────────────────────────────────────────────

const Combinator = { __utest__: { kind: 'combinator' } };

function is_combinator(v) {
	return type(v) == 'object' && v.__utest__ != null && v.__utest__.kind == 'combinator';
}

function fail(msg) {
	die(sprintf('%J', { __utest__: { kind: 'fail', message: msg } }));
}

function unwrap_error_msg(e) {
	return parse_thrown(e).message;
}

// ─── Combinator factories ────────────────────────────────────────────────────

// Forward declaration: equals_object/equals_array reference this before it is assigned.
let _normalize_equals;

function equals_scalar(expected, msg) {
	return proto({
		match: function(actual) {
			if (actual === expected)
				return { ok: true };
			return { ok: false, message: msg || sprintf("Expected %J\n  got %J", expected, actual) };
		}
	}, Combinator);
}

function equals_object(expected, msg) {
	const matchers = {};
	for (let k in keys(expected)) {
		const v = expected[k];
		matchers[k] = is_combinator(v) ? v : _normalize_equals(v);
	}

	return proto({
		match: function(actual) {
			if (type(actual) != 'object')
				return { ok: false, message: msg || sprintf("Expected an object, got %s", type(actual)) };
			const exp_keys = keys(matchers);
			const act_keys = keys(actual);
			if (length(exp_keys) != length(act_keys))
				return { ok: false, message: msg || sprintf("Expected keys %J\n  got keys %J", exp_keys, act_keys) };
			for (let k in exp_keys) {
				if (!exists(actual, k))
					return { ok: false, message: msg || sprintf("Missing key '%s'", k) };
				const r = matchers[k].match(actual[k]);
				if (!r.ok) return { ok: false, message: msg || r.message };
			}
			return { ok: true };
		}
	}, Combinator);
}

function equals_array(expected, msg) {
	const matchers = [];
	for (let el in expected)
		push(matchers, is_combinator(el) ? el : _normalize_equals(el));

	return proto({
		match: function(actual) {
			if (type(actual) != 'array')
				return { ok: false, message: msg || sprintf("Expected an array, got %s", type(actual)) };
			if (length(actual) != length(matchers))
				return { ok: false, message: msg || sprintf("Expected %d elements, got %d", length(matchers), length(actual)) };
			for (let i = 0; i < length(matchers); i++) {
				const r = matchers[i].match(actual[i]);
				if (!r.ok) return { ok: false, message: msg || r.message };
			}
			return { ok: true };
		}
	}, Combinator);
}

_normalize_equals = function(expected, msg) {
	if (type(expected) == 'array')  return equals_array(expected, msg);
	if (type(expected) == 'object') return equals_object(expected, msg);
	return equals_scalar(expected, msg);
};

export function equals(expected, msg) {
	return _normalize_equals(expected, msg);
};

function contains_object(expected, msg) {
	const matchers = {};
	for (let k in keys(expected)) {
		const v = expected[k];
		if (is_combinator(v))
			matchers[k] = v;
		else if (type(v) == 'object')
			matchers[k] = contains_object(v);
		else
			matchers[k] = equals(v);
	}

	return proto({
		match: function(actual) {
			if (type(actual) != 'object')
				return { ok: false, message: msg || sprintf("Expected an object, got %s", type(actual)) };
			for (let k in keys(matchers)) {
				const r = matchers[k].match(actual[k]);
				if (!r.ok) return { ok: false, message: msg || r.message };
			}
			return { ok: true };
		}
	}, Combinator);
}

function contains_string(expected, msg) {
	return proto({
		match: function(actual) {
			if (type(actual) != 'string')
				return { ok: false, message: msg || sprintf("Expected a string, got %s", type(actual)) };
			if (index(actual, expected) >= 0)
				return { ok: true };
			return { ok: false, message: msg || sprintf("Expected %J to contain %J", actual, expected) };
		}
	}, Combinator);
}

function contains_array(expected, msg) {
	const matchers = [];
	for (let el in expected) {
		if (is_combinator(el))        push(matchers, el);
		else if (type(el) == 'array')  push(matchers, contains_array(el));
		else if (type(el) == 'object') push(matchers, contains_object(el));
		else                           push(matchers, equals(el));
	}

	return proto({
		match: function(actual) {
			if (type(actual) != 'array')
				return { ok: false, message: msg || sprintf("Expected an array, got %s", type(actual)) };
			for (let m in matchers) {
				let found = false;
				for (let el in actual)
					if (m.match(el).ok) { found = true; break; }
				if (!found)
					return { ok: false, message: msg || sprintf("Expected %J to contain %J", actual, expected) };
			}
			return { ok: true };
		}
	}, Combinator);
}

export function contains(expected, msg) {
	if (type(expected) == 'string')
		return contains_string(expected, msg);
	if (type(expected) == 'array')
		return contains_array(expected, msg);
	if (type(expected) == 'object' && !is_combinator(expected))
		return contains_object(expected, msg);
	die(sprintf("contains(): expected a string, array, or plain object; got %s",
		is_combinator(expected) ? "combinator" : type(expected)));
};

export function truthy(msg) {
	return proto({
		match: function(actual) {
			if (actual)
				return { ok: true };
			return { ok: false, message: msg || sprintf("Expected truthy value, got %J", actual) };
		}
	}, Combinator);
};

export function falsy(msg) {
	return proto({
		match: function(actual) {
			if (!actual)
				return { ok: true };
			return { ok: false, message: msg || sprintf("Expected falsy value, got %J", actual) };
		}
	}, Combinator);
};

export function not(combinator, msg) {
	if (!is_combinator(combinator))
		die(sprintf("not(): expected a combinator; got %s", type(combinator)));
	return proto({
		match: function(actual) {
			if (!combinator.match(actual).ok)
				return { ok: true };
			return { ok: false, message: msg || sprintf("Expected value not to match, but got %J", actual) };
		}
	}, Combinator);
};

export function pred(fn, msg) {
	return proto({
		match: function(actual) {
			if (fn(actual))
				return { ok: true };
			return { ok: false, message: msg || sprintf("Predicate failed for %J", actual) };
		}
	}, Combinator);
};

export function regex(expected, msg) {
	return proto({
		match: function(actual) {
			if (type(actual) == 'string' && match(actual, expected))
				return { ok: true };
			return { ok: false, message: msg || sprintf("Expected '%s' to match %s", actual, expected) };
		}
	}, Combinator);
};

export function any() {
	return proto({
		match: function(_actual) { return { ok: true }; }
	}, Combinator);
};

export function any_order(expected, msg) {
	const matchers = [];
	for (let m in expected)
		push(matchers, is_combinator(m) ? m : equals(m));

	return proto({
		match: function(actual) {
			if (type(actual) != 'array')
				return { ok: false, message: msg || sprintf("Expected an array, got %s", type(actual)) };
			if (length(actual) != length(matchers))
				return { ok: false, message: msg || sprintf("Expected %d elements, got %d", length(matchers), length(actual)) };

			// Backtracking search avoids the greedy false-negative when a wildcard
			// (e.g. any()) claims an element that a later specific matcher needs.
			const used = [];
			for (let i = 0; i < length(actual); i++)
				push(used, false);

			let bt;
			bt = function(i) {
				if (i == length(matchers)) return true;
				for (let j = 0; j < length(actual); j++) {
					if (!used[j] && matchers[i].match(actual[j]).ok) {
						used[j] = true;
						if (bt(i + 1)) return true;
						used[j] = false;
					}
				}
				return false;
			};

			if (!bt(0))
				return { ok: false, message: msg || "No valid permutation found" };
			return { ok: true };
		}
	}, Combinator);
};


// ─── Assert object ───────────────────────────────────────────────────────────

export const assert = {
	throws: function(fn, pattern, msg) {
		try {
			fn();
		} catch (e) {
			if (pattern) {
				const emsg = unwrap_error_msg(e);
				if (!match(emsg, pattern))
					fail(msg || sprintf("Exception '%s' did not match pattern %s", emsg, pattern));
			}
			return;
		}
		fail(msg || "Expected exception but none was thrown");
	},

	match: function(actual, expected, msg) {
		const r = (is_combinator(expected) ? expected : equals(expected)).match(actual);
		if (!r.ok) fail(msg ? (msg + "\n" + r.message) : r.message);
	}
};
