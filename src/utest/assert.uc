/**
 * Assertion utilities for the utest framework.
 *
 * @module utest.assert
 */

import { parse_thrown } from 'utest.util';
import { is_combinator, equals, regex as _regex, contains } from 'utest.combinators';

function fail(msg) {
	die(sprintf('%J', { __utest__: { kind: 'fail', message: msg } }));
}

function unwrap_error_msg(e) {
	return parse_thrown(e).message;
}

/**
 * Asserts that a function throws an exception, optionally matching a pattern.
 *
 * @example
 * assert.throws(() => { die("fatal error"); }, "fatal error");
 *
 * @param {function} fn - The function expected to throw.
 * @param {string|RegExp|Combinator<string>} [pattern] - Substring (string), regex, or combinator the error message must satisfy.
 * @param {string} [msg] - Custom failure message.
 */
export function throws(fn, pattern, msg) {
	try {
		fn();
	} catch (e) {
		if (pattern !== null) {
			const emsg = unwrap_error_msg(e);
			const combinator = is_combinator(pattern) ? pattern :
				(type(pattern) === 'regexp' ? _regex(pattern) : contains(pattern));
			if (!combinator.match(emsg).ok)
				fail(msg || sprintf("Exception '%s' did not match pattern %s", emsg, pattern));
		}
		return;
	}
	fail(msg || "Expected exception but none was thrown");
};

/**
 * Asserts that a value matches an expected value or combinator.
 *
 * @example
 * assert.match(2, 1 + 1);
 * assert.match(contains("foo"), "foo bar");
 *
 * @template T
 * @param {T | Combinator<T>} expected - The expected value or combinator.
 * @param {T} actual - The actual value to test.
 * @param {string} [msg] - Custom failure message.
 */
export function match(expected, actual, msg) {
	const r = (is_combinator(expected) ? expected : equals(expected)).match(actual);
	if (!r.ok) fail(msg ? (msg + "\n" + r.message) : r.message);
};
