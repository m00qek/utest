// ─── Combinator prototype ────────────────────────────────────────────────────

const Combinator = { __utest__: { kind: 'combinator' } };

/**
 * @typedef {{match: function(any): {ok: boolean, message: string|null}}} Combinator
 */

export function is_combinator(v) {
	return type(v) === 'object' && v.__utest__ && v.__utest__.kind === 'combinator';
};

// ─── equals ──────────────────────────────────────────────────────────────────

// Forward declaration: equals_object/equals_array reference this before it is assigned.
let _normalize_equals;

function equals_scalar(expected) {
	return proto({
		match: function(actual) {
			if (actual === expected)
				return { ok: true };
			return { ok: false, message: sprintf("Expected %J\n  got %J", expected, actual) };
		}
	}, Combinator);
}

function equals_object(expected) {
	const matchers = {};
	for (let k in keys(expected)) {
		const v = expected[k];
		matchers[k] = is_combinator(v) ? v : _normalize_equals(v);
	}

	return proto({
		match: function(actual) {
			if (type(actual) !== 'object')
				return { ok: false, message: sprintf("Expected an object, got %s", type(actual)) };
			const exp_keys = keys(matchers);
			const act_keys = keys(actual);
			if (length(exp_keys) !== length(act_keys))
				return { ok: false, message: sprintf("Expected keys %J\n  got keys %J", exp_keys, act_keys) };
			for (let k in exp_keys) {
				if (!exists(actual, k))
					return { ok: false, message: sprintf("Missing key '%s'", k) };
				const r = matchers[k].match(actual[k]);
				if (!r.ok) return { ok: false, message: r.message };
			}
			return { ok: true };
		}
	}, Combinator);
}

function equals_array(expected) {
	const matchers = [];
	for (let el in expected)
		push(matchers, is_combinator(el) ? el : _normalize_equals(el));

	return proto({
		match: function(actual) {
			if (type(actual) !== 'array')
				return { ok: false, message: sprintf("Expected an array, got %s", type(actual)) };
			if (length(actual) !== length(matchers))
				return { ok: false, message: sprintf("Expected %d elements, got %d", length(matchers), length(actual)) };
			for (let i = 0; i < length(matchers); i++) {
				const r = matchers[i].match(actual[i]);
				if (!r.ok) return { ok: false, message: r.message };
			}
			return { ok: true };
		}
	}, Combinator);
}

_normalize_equals = function(expected) {
	if (type(expected) === 'array')  return equals_array(expected);
	if (type(expected) === 'object') return equals_object(expected);
	return equals_scalar(expected);
};

/**
 * Asserts that a value equals the expected value. Arrays and objects are compared structurally.
 * 
 * @template T
 * @param {T} expected - The expected value or nested combinators.
 * @returns {Combinator} The configured combinator.
 */
export function equals(expected) {
	return _normalize_equals(expected);
};

// ─── contains ────────────────────────────────────────────────────────────────

function contains_object(expected) {
	const matchers = {};
	for (let k in keys(expected)) {
		const v = expected[k];
		if (is_combinator(v))
			matchers[k] = v;
		else if (type(v) === 'object')
			matchers[k] = contains_object(v);
		else
			matchers[k] = equals(v);
	}

	return proto({
		match: function(actual) {
			if (type(actual) !== 'object')
				return { ok: false, message: sprintf("Expected an object, got %s", type(actual)) };
			for (let k in keys(matchers)) {
				const r = matchers[k].match(actual[k]);
				if (!r.ok) return { ok: false, message: r.message };
			}
			return { ok: true };
		}
	}, Combinator);
}

function contains_string(expected) {
	return proto({
		match: function(actual) {
			if (type(actual) !== 'string')
				return { ok: false, message: sprintf("Expected a string, got %s", type(actual)) };
			if (index(actual, expected) >= 0)
				return { ok: true };
			return { ok: false, message: sprintf("Expected %J to contain %J", actual, expected) };
		}
	}, Combinator);
}

function contains_array(expected) {
	const matchers = [];
	for (let el in expected) {
		if (is_combinator(el))        push(matchers, el);
		else if (type(el) === 'array')  push(matchers, contains_array(el));
		else if (type(el) === 'object') push(matchers, contains_object(el));
		else                           push(matchers, equals(el));
	}

	return proto({
		match: function(actual) {
			if (type(actual) !== 'array')
				return { ok: false, message: sprintf("Expected an array, got %s", type(actual)) };

			// Ordered-subsequence search with backtracking.
			// Finds strictly-increasing positions i_0 < i_1 < … where
			// matchers[k].match(actual[i_k]).ok for every k.
			// Backtracking prevents a wildcard (any(), pred(), regex()) from
			// greedily consuming a slot that a later specific matcher needs.
			let bt;
			bt = function(mi, ai) {
				if (mi === length(matchers)) return true;
				for (let j = ai; j < length(actual); j++)
					if (matchers[mi].match(actual[j]).ok && bt(mi + 1, j + 1)) return true;
				return false;
			};

			if (!bt(0, 0))
				return { ok: false, message: sprintf("Expected %J to contain %J as a subsequence", actual, expected) };
			return { ok: true };
		}
	}, Combinator);
}

/**
 * Asserts that a string, array, or object contains the expected value(s).
 * 
 * @param {any} expected - The substring, subsequence, or subset of object keys to find.
 * @returns {Combinator} The configured combinator.
 */
export function contains(expected) {
	if (type(expected) === 'string')
		return contains_string(expected);
	if (type(expected) === 'array')
		return contains_array(expected);
	if (type(expected) === 'object' && !is_combinator(expected))
		return contains_object(expected);
	die(sprintf("contains(): expected a string, array, or plain object; got %s",
		is_combinator(expected) ? "combinator" : type(expected)));
};

// ─── starts_with / ends_with ─────────────────────────────────────────────────

function starts_with_string(expected) {
	return proto({
		match: function(actual) {
			if (type(actual) !== 'string')
				return { ok: false, message: sprintf("Expected a string, got %s", type(actual)) };
			if (substr(actual, 0, length(expected)) === expected)
				return { ok: true };
			return { ok: false, message: sprintf("Expected %J to start with %J", actual, expected) };
		}
	}, Combinator);
}

function starts_with_array(expected) {
	const matchers = [];
	for (let el in expected)
		push(matchers, is_combinator(el) ? el : equals(el));
	return proto({
		match: function(actual) {
			if (type(actual) !== 'array')
				return { ok: false, message: sprintf("Expected an array, got %s", type(actual)) };
			if (length(actual) < length(matchers))
				return { ok: false, message: sprintf("Expected at least %d elements, got %d", length(matchers), length(actual)) };
			for (let i = 0; i < length(matchers); i++) {
				const r = matchers[i].match(actual[i]);
				if (!r.ok) return { ok: false, message: r.message };
			}
			return { ok: true };
		}
	}, Combinator);
}

/**
 * Asserts that a string or array starts with the expected sequence.
 * 
 * @param {string|any[]} expected - The expected starting sequence.
 * @returns {Combinator} The configured combinator.
 */
export function starts_with(expected) {
	if (type(expected) === 'string') return starts_with_string(expected);
	if (type(expected) === 'array')  return starts_with_array(expected);
	die(sprintf("starts_with(): expected a string or array; got %s",
		is_combinator(expected) ? "combinator" : type(expected)));
};

function ends_with_string(expected) {
	return proto({
		match: function(actual) {
			if (type(actual) !== 'string')
				return { ok: false, message: sprintf("Expected a string, got %s", type(actual)) };
			if (length(expected) > length(actual))
				return { ok: false, message: sprintf("Expected %J to end with %J", actual, expected) };
			if (substr(actual, length(actual) - length(expected)) === expected)
				return { ok: true };
			return { ok: false, message: sprintf("Expected %J to end with %J", actual, expected) };
		}
	}, Combinator);
}

function ends_with_array(expected) {
	const matchers = [];
	for (let el in expected)
		push(matchers, is_combinator(el) ? el : equals(el));
	return proto({
		match: function(actual) {
			if (type(actual) !== 'array')
				return { ok: false, message: sprintf("Expected an array, got %s", type(actual)) };
			if (length(actual) < length(matchers))
				return { ok: false, message: sprintf("Expected at least %d elements, got %d", length(matchers), length(actual)) };
			const offset = length(actual) - length(matchers);
			for (let i = 0; i < length(matchers); i++) {
				const r = matchers[i].match(actual[offset + i]);
				if (!r.ok) return { ok: false, message: r.message };
			}
			return { ok: true };
		}
	}, Combinator);
}

/**
 * Asserts that a string or array ends with the expected sequence.
 * 
 * @param {string|any[]} expected - The expected ending sequence.
 * @returns {Combinator} The configured combinator.
 */
export function ends_with(expected) {
	if (type(expected) === 'string') return ends_with_string(expected);
	if (type(expected) === 'array')  return ends_with_array(expected);
	die(sprintf("ends_with(): expected a string or array; got %s",
		is_combinator(expected) ? "combinator" : type(expected)));
};

// ─── Scalar combinators ───────────────────────────────────────────────────────

/**
 * Asserts that a value is truthy.
 * 
 * @returns {Combinator} The configured combinator.
 */
export function truthy() {
	return proto({
		match: function(actual) {
			if (actual)
				return { ok: true };
			return { ok: false, message: sprintf("Expected truthy value, got %J", actual) };
		}
	}, Combinator);
};

/**
 * Asserts that a value is falsy.
 * 
 * @returns {Combinator} The configured combinator.
 */
export function falsy() {
	return proto({
		match: function(actual) {
			if (!actual)
				return { ok: true };
			return { ok: false, message: sprintf("Expected falsy value, got %J", actual) };
		}
	}, Combinator);
};

/**
 * Inverts another combinator, matching when it fails.
 * 
 * @param {Combinator} combinator - The combinator to invert.
 * @returns {Combinator} The configured combinator.
 */
export function not(combinator) {
	if (!is_combinator(combinator))
		die(sprintf("not(): expected a combinator; got %s", type(combinator)));
	return proto({
		match: function(actual) {
			if (!combinator.match(actual).ok)
				return { ok: true };
			return { ok: false, message: sprintf("Expected value not to match, but got %J", actual) };
		}
	}, Combinator);
};

/**
 * Asserts that a value satisfies a custom predicate function.
 * 
 * @param {function(any): boolean} fn - The predicate function.
 * @returns {Combinator} The configured combinator.
 */
export function pred(fn) {
	return proto({
		match: function(actual) {
			if (fn(actual))
				return { ok: true };
			return { ok: false, message: sprintf("Predicate failed for %J", actual) };
		}
	}, Combinator);
};

/**
 * Asserts that a string matches a regular expression.
 * 
 * @param {RegExp} expected - The regular expression to match against.
 * @returns {Combinator} The configured combinator.
 */
export function regex(expected) {
	return proto({
		match: function(actual) {
			if (type(actual) === 'string' && match(actual, expected))
				return { ok: true };
			return { ok: false, message: sprintf("Expected '%s' to match %s", actual, expected) };
		}
	}, Combinator);
};

/**
 * A wildcard combinator that matches any value unconditionally.
 * 
 * @returns {Combinator} The configured combinator.
 */
export function any() {
	return proto({
		match: function(_actual) { return { ok: true }; }
	}, Combinator);
};

/**
 * Asserts that an array contains the exact expected elements, in any order.
 * 
 * @param {any[]} expected - The expected elements or combinators.
 * @returns {Combinator} The configured combinator.
 */
export function any_order(expected) {
	const matchers = [];
	for (let m in expected)
		push(matchers, is_combinator(m) ? m : equals(m));

	return proto({
		match: function(actual) {
			if (type(actual) !== 'array')
				return { ok: false, message: sprintf("Expected an array, got %s", type(actual)) };
			if (length(actual) !== length(matchers))
				return { ok: false, message: sprintf("Expected %d elements, got %d", length(matchers), length(actual)) };

			// Backtracking search avoids the greedy false-negative when a wildcard
			// (e.g. any()) claims an element that a later specific matcher needs.
			const used = [];
			for (let i = 0; i < length(actual); i++)
				push(used, false);

			let bt;
			bt = function(i) {
				if (i === length(matchers)) return true;
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
				return { ok: false, message: "No valid permutation found" };
			return { ok: true };
		}
	}, Combinator);
};

/**
 * Asserts that a string, array, or object has the specified length.
 * 
 * @param {int} n - The expected length.
 * @returns {Combinator} The configured combinator.
 */
export function has_length(n) {
	return proto({
		match: function(actual) {
			const t = type(actual);
			if (t !== 'string' && t !== 'array' && t !== 'object')
				return { ok: false, message: sprintf("Expected a string, array, or object, got %s", t) };
			const l = length(actual);
			if (l === n)
				return { ok: true };
			return { ok: false, message: sprintf("Expected length %d, got %d", n, l) };
		}
	}, Combinator);
};

/**
 * Asserts that a number is within an inclusive range.
 * 
 * @param {int|float} min - The minimum allowed value.
 * @param {int|float} max - The maximum allowed value.
 * @returns {Combinator} The configured combinator.
 */
export function between(min, max) {
	return proto({
		match: function(actual) {
			if (type(actual) !== 'int' && type(actual) !== 'double')
				return { ok: false, message: sprintf("Expected a number, got %s", type(actual)) };
			if (actual >= min && actual <= max)
				return { ok: true };
			return { ok: false, message: sprintf("Expected value between %s and %s, got %s", min, max, actual) };
		}
	}, Combinator);
};

/**
 * Asserts that a value is of a specific ucode type.
 * 
 * @param {string} expected - The expected type name (e.g. 'string', 'int', 'double', 'object', 'array').
 * @returns {Combinator} The configured combinator.
 */
export function is_type(expected) {
	return proto({
		match: function(actual) {
			const t = type(actual);
			if (t === expected)
				return { ok: true };
			return { ok: false, message: sprintf("Expected type '%s', got '%s'", expected, t) };
		}
	}, Combinator);
};

