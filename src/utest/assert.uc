function is_object(v) {
	return type(v) == 'object' || type(v) == 'array';
}

function deep_equal(actual, expected, seen) {
	if (actual === expected) {
		return true;
	}

	if (type(actual) != type(expected)) {
		return false;
	}

	if (!is_object(actual)) {
		return actual == expected;
	}

	// Circular reference protection
	for (let s in seen) {
		if (s.actual === actual && s.expected === expected) {
			return true;
		}
	}

	push(seen, { actual, expected });

	if (type(actual) == 'array') {
		if (length(actual) != length(expected)) {
			return false;
		}
		for (let i = 0; i < length(actual); i++) {
			if (!deep_equal(actual[i], expected[i], seen)) {
				return false;
			}
		}
		return true;
	}

	// Object comparison
	let keys_actual = keys(actual);
	let keys_expected = keys(expected);

	if (length(keys_actual) != length(keys_expected)) {
		return false;
	}

	for (let k in keys_actual) {
		if (!exists(expected, k) || !deep_equal(actual[k], expected[k], seen)) {
			return false;
		}
	}

	return true;
}

export const assert = {
	eq: function(actual, expected, msg) {
		if (!deep_equal(actual, expected, [])) {
			die(sprintf("%s\n  Actual:   %s\n  Expected: %s",
				msg || "Assertion failed",
				sprintf('%J', actual),
				sprintf('%J', expected)
			));
		}
	},

	ok: function(val, msg) {
		if (!val) {
			die(msg || sprintf("Expected truthy value, got %s", sprintf('%J', val)));
		}
	},

	match: function(str, regex, msg) {
		if (type(str) != 'string')
			die(sprintf("assert.match: expected a string, got %s", type(str)));
		if (!match(str, regex))
			die(msg || sprintf("Expected '%s' to match %s", str, regex));
	},

	throws: function(fn, pattern, msg) {
		try {
			fn();
		} catch (e) {
			if (pattern && !match(sprintf('%s', e), pattern)) {
				die(msg || sprintf("Exception '%s' did not match pattern %s", e, pattern));
			}
			return;
		}
		die(msg || "Expected exception but none was thrown");
	},

	ne: function(actual, expected, msg) {
		if (deep_equal(actual, expected, [])) {
			die(sprintf("%s\n  Value: %s",
				msg || "Expected values to differ",
				sprintf('%J', actual)
			));
		}
	},

	notOk: function(val, msg) {
		if (val) {
			die(msg || sprintf("Expected falsy value, got %s", sprintf('%J', val)));
		}
	},

	notMatch: function(str, regex, msg) {
		if (type(str) != 'string')
			die(sprintf("assert.notMatch: expected a string, got %s", type(str)));
		if (match(str, regex))
			die(msg || sprintf("Expected '%s' not to match %s", str, regex));
	}
};
