// ─── Combinator prototype ────────────────────────────────────────────────────

const Combinator = { __utest__: { kind: 'combinator' } };

/**
 * @template T
 * @typedef {{ match: function(T): {ok: boolean, message: string|null} }} Combinator
 */

export function is_combinator(v) {
	return type(v) === 'object' && v.__utest__ && v.__utest__.kind === 'combinator';
};

// Wraps a match function `(actual) -> { ok, message? }` as a combinator by
// attaching the shared Combinator prototype.  Every combinator below is built
// through this factory so the prototype wiring lives in exactly one place.
function comb(match) {
	return proto({ match }, Combinator);
}

// ─── equals ──────────────────────────────────────────────────────────────────

// Forward declaration: equals_object/equals_array reference this before it is assigned.
let _normalize_equals;

// Render an accumulated structural path (object keys and array indices) so a
// nested equals() failure can say *where* it mismatched, e.g. ['user','age'] ->
// "user.age" and ['items',2,'name'] -> "items[2].name". The path is built
// bottom-up by equals_object/equals_array (each prepends its own segment as the
// failure bubbles up) and formatted once by assert.match().
export function path_str(path) {
	let s = "";
	for (let seg in path)
		s += (type(seg) === 'int') ? ("[" + seg + "]") : ((s === "" ? "" : ".") + seg);
	return s;
};

function equals_scalar(expected) {
	return comb(function(actual) {
		if (actual === expected)
			return { ok: true };
		return { ok: false, message: sprintf("Expected %J\n  got %J", expected, actual) };
	});
}

function equals_object(expected) {
	const matchers = {};
	for (let k in keys(expected)) {
		const v = expected[k];
		matchers[k] = is_combinator(v) ? v : _normalize_equals(v);
	}

	return comb(function(actual) {
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
			// Prepend this key to the child's path (empty for a leaf/non-structural
			// combinator) so the failure carries the full location to assert.match().
			if (!r.ok) return { ok: false, message: r.message, path: [k, ...(r.path ?? [])] };
		}
		return { ok: true };
	});
}

function equals_array(expected) {
	const matchers = [];
	for (let el in expected)
		push(matchers, is_combinator(el) ? el : _normalize_equals(el));

	return comb(function(actual) {
		if (type(actual) !== 'array')
			return { ok: false, message: sprintf("Expected an array, got %s", type(actual)) };
		if (length(actual) !== length(matchers))
			return { ok: false, message: sprintf("Expected %d elements, got %d", length(matchers), length(actual)) };
		for (let i = 0; i < length(matchers); i++) {
			const r = matchers[i].match(actual[i]);
			// Prepend this index (rendered [i]) to the child's path.
			if (!r.ok) return { ok: false, message: r.message, path: [i, ...(r.path ?? [])] };
		}
		return { ok: true };
	});
}

_normalize_equals = function(expected) {
	if (type(expected) === 'array')  return equals_array(expected);
	if (type(expected) === 'object') return equals_object(expected);
	return equals_scalar(expected);
};

/**
 * Asserts that a value equals the expected value. Arrays and objects are compared structurally.
 * Nested combinators inside arrays or objects are matched against the corresponding element.
 *
 * @example
 * assert.match(equals({ status: 200, body: contains("ok") }), response);
 * assert.match(equals([1, any(), 3]), [1, 99, 3]);
 *
 * @template T
 * @param {T} expected - The expected value or nested combinators.
 * @returns {Combinator<T>} The configured combinator.
 */
export function equals(expected) {
	// A combinator passed directly (e.g. equals(any())) is the one entry point the
	// nested is_combinator checks above don't cover: equals_object would compare
	// against the combinator's own { match } shape and fail confusingly. Unwrap it,
	// mirroring assert.match, so equals(any()) behaves like any().
	if (is_combinator(expected)) return expected;
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

	return comb(function(actual) {
		if (type(actual) !== 'object')
			return { ok: false, message: sprintf("Expected an object, got %s", type(actual)) };
		for (let k in keys(matchers)) {
			if (!exists(actual, k))
				return { ok: false, message: sprintf("Missing key '%s'", k) };
			const r = matchers[k].match(actual[k]);
			// Note: unlike equals_object, the partial matchers (contains/starts_with/
			// ends_with) do not prepend `k` to a child's `path`, so a nested
			// contains({user:{age:…}}) failure reports the leaf message without the
			// "at user.age:" prefix that equals() failures get. Left as-is: a known
			// asymmetry in the feature surface, not wired through here.
			if (!r.ok) return { ok: false, message: r.message };
		}
		return { ok: true };
	});
}

function contains_string(expected) {
	return comb(function(actual) {
		if (type(actual) !== 'string')
			return { ok: false, message: sprintf("Expected a string, got %s", type(actual)) };
		if (index(actual, expected) >= 0)
			return { ok: true };
		return { ok: false, message: sprintf("Expected %J to contain %J", actual, expected) };
	});
}

function contains_array(expected) {
	const matchers = [];
	for (let el in expected) {
		if (is_combinator(el))        push(matchers, el);
		else if (type(el) === 'array')  push(matchers, contains_array(el));
		else if (type(el) === 'object') push(matchers, contains_object(el));
		else                           push(matchers, equals(el));
	}

	return comb(function(actual) {
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
	});
}

/**
 * Asserts that a string, array, or object contains the expected value(s).
 * For strings: substring match. For arrays: ordered subsequence (with backtracking).
 * For objects: subset of keys (deep, combinators allowed as values).
 *
 * @example
 * assert.match(contains("error"), "fatal error: permission denied");
 * assert.match(contains([2, 4]), [1, 2, 3, 4, 5]);
 * assert.match(contains({ status: 200 }), { status: 200, body: "ok", latency: 12 });
 *
 * @param {any} expected - The substring, subsequence, or subset of object keys to find.
 * @returns {Combinator<string|any[]|dict<any>>} The configured combinator.
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
	return comb(function(actual) {
		if (type(actual) !== 'string')
			return { ok: false, message: sprintf("Expected a string, got %s", type(actual)) };
		if (substr(actual, 0, length(expected)) === expected)
			return { ok: true };
		return { ok: false, message: sprintf("Expected %J to start with %J", actual, expected) };
	});
}

function starts_with_array(expected) {
	const matchers = [];
	for (let el in expected)
		push(matchers, is_combinator(el) ? el : equals(el));
	return comb(function(actual) {
		if (type(actual) !== 'array')
			return { ok: false, message: sprintf("Expected an array, got %s", type(actual)) };
		if (length(actual) < length(matchers))
			return { ok: false, message: sprintf("Expected at least %d elements, got %d", length(matchers), length(actual)) };
		for (let i = 0; i < length(matchers); i++) {
			const r = matchers[i].match(actual[i]);
			if (!r.ok) return { ok: false, message: r.message };
		}
		return { ok: true };
	});
}

/**
 * Asserts that a string or array starts with the expected sequence.
 *
 * @example
 * assert.match(starts_with("hello"), "hello world");
 * assert.match(starts_with([1, 2]), [1, 2, 3, 4]);
 *
 * @param {string|any[]} expected - The expected starting sequence.
 * @returns {Combinator<string|any[]>} The configured combinator.
 */
export function starts_with(expected) {
	if (type(expected) === 'string') return starts_with_string(expected);
	if (type(expected) === 'array')  return starts_with_array(expected);
	die(sprintf("starts_with(): expected a string or array; got %s",
		is_combinator(expected) ? "combinator" : type(expected)));
};

function ends_with_string(expected) {
	return comb(function(actual) {
		if (type(actual) !== 'string')
			return { ok: false, message: sprintf("Expected a string, got %s", type(actual)) };
		if (length(expected) > length(actual))
			return { ok: false, message: sprintf("Expected %J to end with %J", actual, expected) };
		if (substr(actual, length(actual) - length(expected)) === expected)
			return { ok: true };
		return { ok: false, message: sprintf("Expected %J to end with %J", actual, expected) };
	});
}

function ends_with_array(expected) {
	const matchers = [];
	for (let el in expected)
		push(matchers, is_combinator(el) ? el : equals(el));
	return comb(function(actual) {
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
	});
}

/**
 * Asserts that a string or array ends with the expected sequence.
 *
 * @example
 * assert.match(ends_with(".uc"), "utest.uc");
 * assert.match(ends_with([3, 4]), [1, 2, 3, 4]);
 *
 * @param {string|any[]} expected - The expected ending sequence.
 * @returns {Combinator<string|any[]>} The configured combinator.
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
 * @returns {Combinator<any>} The configured combinator.
 */
export function truthy() {
	return comb(function(actual) {
		if (actual)
			return { ok: true };
		return { ok: false, message: sprintf("Expected truthy value, got %J", actual) };
	});
};

/**
 * Asserts that a value is falsy.
 *
 * @returns {Combinator<any>} The configured combinator.
 */
export function falsy() {
	return comb(function(actual) {
		if (!actual)
			return { ok: true };
		return { ok: false, message: sprintf("Expected falsy value, got %J", actual) };
	});
};

/**
 * Inverts another combinator, matching when it fails.
 *
 * @example
 * assert.match(not(contains("error")), "all systems go");
 * assert.match(not(equals(null)), someValue);
 *
 * @template T
 * @param {Combinator<T>} combinator - The combinator to invert.
 * @returns {Combinator<T>} The configured combinator.
 */
export function not(combinator) {
	if (!is_combinator(combinator))
		die(sprintf("not(): expected a combinator; got %s", type(combinator)));
	return comb(function(actual) {
		if (!combinator.match(actual).ok)
			return { ok: true };
		return { ok: false, message: sprintf("Expected value not to match, but got %J", actual) };
	});
};

/**
 * Asserts that a value satisfies a custom predicate function.
 * Use when no built-in combinator fits; prefer composing combinators when possible.
 *
 * @example
 * assert.match(pred(n => n % 2 === 0), 42);
 * assert.match(pred(s => length(s) > 0 && s[0] === "/"), "/etc/config");
 *
 * @template T
 * @param {function(T): boolean} fn - The predicate function.
 * @returns {Combinator<T>} The configured combinator.
 */
export function pred(fn) {
	return comb(function(actual) {
		if (fn(actual))
			return { ok: true };
		return { ok: false, message: sprintf("Predicate failed for %J", actual) };
	});
};

/**
 * Asserts that a string matches a regular expression.
 *
 * @example
 * assert.match(regex(/^\d{3}-\d{4}$/), "555-1234");
 * assert.match(regex(/^(ok|error)$/), status);
 *
 * @param {RegExp} expected - The regular expression to match against.
 * @returns {Combinator<string>} The configured combinator.
 */
export function regex(expected) {
	// ucode's match(str, "literal") treats a string as a literal, not a pattern,
	// so a non-regexp argument would silently never match — and, worse, invert
	// into an always-pass under not(regex(...)). Validate like the siblings.
	if (type(expected) !== 'regexp')
		die(sprintf("regex(): expected a regular expression; got %s",
			is_combinator(expected) ? "combinator" : type(expected)));
	return comb(function(actual) {
		if (type(actual) === 'string' && match(actual, expected))
			return { ok: true };
		return { ok: false, message: sprintf("Expected '%s' to match %s", actual, expected) };
	});
};

/**
 * A wildcard combinator that matches any value unconditionally.
 *
 * @returns {Combinator<any>} The configured combinator.
 */
export function any() {
	return comb(function(_actual) { return { ok: true }; });
};

/**
 * Asserts that an array contains the exact expected elements, in any order.
 * Combinators are accepted as elements; backtracking prevents greedy wildcards
 * from stealing slots that later specific matchers need.
 *
 * @example
 * assert.match(any_order([1, 2, 3]), [3, 1, 2]);
 * assert.match(any_order([equals(42), any()]), [99, 42]);
 *
 * @param {any[]} expected - The expected elements or combinators.
 * @returns {Combinator<any[]>} The configured combinator.
 */
export function any_order(expected) {
	const matchers = [];
	for (let m in expected)
		push(matchers, is_combinator(m) ? m : equals(m));

	return comb(function(actual) {
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
	});
};

/**
 * Asserts that a string, array, or object has the specified length.
 * 
 * @param {int} n - The expected length.
 * @returns {Combinator<string|any[]|dict<any>>} The configured combinator.
 */
export function has_length(n) {
	return comb(function(actual) {
		const t = type(actual);
		if (t !== 'string' && t !== 'array' && t !== 'object')
			return { ok: false, message: sprintf("Expected a string, array, or object, got %s", t) };
		const l = length(actual);
		if (l === n)
			return { ok: true };
		return { ok: false, message: sprintf("Expected length %d, got %d", n, l) };
	});
};

/**
 * Asserts that a number is within an inclusive range.
 * 
 * @param {int|float} min - The minimum allowed value.
 * @param {int|float} max - The maximum allowed value.
 * @returns {Combinator<int|float>} The configured combinator.
 */
export function between(min, max) {
	return comb(function(actual) {
		if (type(actual) !== 'int' && type(actual) !== 'double')
			return { ok: false, message: sprintf("Expected a number, got %s", type(actual)) };
		if (actual >= min && actual <= max)
			return { ok: true };
		return { ok: false, message: sprintf("Expected value between %s and %s, got %s", min, max, actual) };
	});
};

/**
 * Asserts that a value is of a specific ucode type.
 * 
 * @param {string} expected - The expected type name (e.g. 'string', 'int', 'double', 'object', 'array').
 * @returns {Combinator<any>} The configured combinator.
 */
export function is_type(expected) {
	return comb(function(actual) {
		const t = type(actual);
		if (t === expected)
			return { ok: true };
		return { ok: false, message: sprintf("Expected type '%s', got '%s'", expected, t) };
	});
};

