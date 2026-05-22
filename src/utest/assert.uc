// ─── Combinator prototype ────────────────────────────────────────────────────

const Combinator = { __combinator__: true };

function is_combinator(v) {
	return type(v) == 'object' && v.__combinator__;
}

function fail(msg) {
	die(sprintf('%J', { __utest_fail__: true, message: msg }));
}

function unwrap_error_msg(e) {
	if (type(e) == 'object' && e.type == "Error") {
		let parsed = null;
		try { parsed = json(e.message); } catch(_) {}
		if (type(parsed) == 'object' && parsed.__utest_fail__)
			return parsed.message;
		return e.message;
	}
	return sprintf('%s', e);
}

// ─── Combinator factories ────────────────────────────────────────────────────

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
		if (is_combinator(el))       push(matchers, el);
		else if (type(el) == 'array') push(matchers, contains_array(el));
		else                          push(matchers, equals(el));
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
	return contains_array(type(expected) == 'array' ? expected : [expected], msg);
};

export function matches(expected, msg) {
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

export function has(expected, msg) {
	const matchers = {};
	for (let k in keys(expected)) {
		const v = expected[k];
		if (is_combinator(v))
			matchers[k] = v;
		else if (type(v) == 'object')
			matchers[k] = has(v);
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
	eq: function(actual, expected, msg) {
		const r = equals(expected).match(actual);
		if (!r.ok)
			fail(msg
				? sprintf("%s\n  Actual:   %s\n  Expected: %s", msg, sprintf('%J', actual), sprintf('%J', expected))
				: r.message);
	},

	ok: function(val, msg) {
		if (!val) {
			fail(msg || sprintf("Expected truthy value, got %s", sprintf('%J', val)));
		}
	},

	matches: function(str, regex, msg) {
		if (type(str) != 'string')
			fail(sprintf("assert.matches: expected a string, got %s", type(str)));
		if (!match(str, regex))
			fail(msg || sprintf("Expected '%s' to match %s", str, regex));
	},

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

	ne: function(actual, expected, msg) {
		if (equals(expected).match(actual).ok) {
			fail(sprintf("%s\n  Value: %s",
				msg || "Expected values to differ",
				sprintf('%J', actual)
			));
		}
	},

	notOk: function(val, msg) {
		if (val) {
			fail(msg || sprintf("Expected falsy value, got %s", sprintf('%J', val)));
		}
	},

	notMatches: function(str, regex, msg) {
		if (type(str) != 'string')
			fail(sprintf("assert.notMatches: expected a string, got %s", type(str)));
		if (match(str, regex))
			fail(msg || sprintf("Expected '%s' not to match %s", str, regex));
	},

	notThrows: function(fn, msg) {
		try {
			fn();
		} catch (e) {
			fail(msg || sprintf("Expected no exception but got: %s", unwrap_error_msg(e)));
		}
	},

	contains: function(haystack, needle, msg) {
		if (type(haystack) == 'string') {
			if (index(haystack, needle) < 0)
				fail(msg || sprintf("Expected string to contain '%s'", needle));
		} else if (type(haystack) == 'array') {
			const matcher = is_combinator(needle) ? needle : equals(needle);
			for (let item in haystack) {
				if (matcher.match(item).ok) return;
			}
			fail(msg || sprintf("Expected array to contain %s", sprintf('%J', needle)));
		} else {
			fail(sprintf("assert.contains: expected a string or array, got %s", type(haystack)));
		}
	},

	match: function(actual, expected, msg) {
		const r = (is_combinator(expected) ? expected : equals(expected)).match(actual);
		if (!r.ok) fail(msg || r.message);
	}
};
