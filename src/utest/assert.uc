/**
 * Assertion utilities for the utest framework.
 *
 * @module utest.assert
 */

import { parse_thrown, fail_envelope } from 'utest.util';
import { is_combinator, equals, regex as _regex, contains, path_str } from 'utest.combinators';

/**
 * Unconditionally raises an assertion failure. Reports as FAIL (like any other
 * assert.*), not as an ERROR the way a bare `die()` would — use it for an
 * unreachable branch or a bespoke check the built-in assertions don't cover.
 *
 * @param {string} [msg] - The failure message.
 * @example
 * if (state !== 'ready') assert.fail("expected ready, got " + state);
 */
export function fail(msg) {
	die(fail_envelope(msg ?? "assert.fail() called"));
};

/**
 * Asserts that a function throws an exception, optionally matching a pattern.
 *
 * A utest control-flow throw — an assertion failure (a nested assert.*) or a
 * property-engine sentinel — is not counted as a caught exception unless the
 * caller supplies a pattern that matches it: otherwise `assert.throws(() =>
 * assert.match(1, 2))` would swallow a real failure inside `fn` and pass green.
 * A genuine exception (a die() or runtime error from the code under test) is
 * accepted as before.
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
		const parsed = parse_thrown(e);
		const emsg = parsed.message;
		// A non-null kind means this is utest's own control flow (assertion failure
		// or property sentinel), not an exception the code deliberately raised.
		const sentinel = (parsed.kind !== null);

		if (pattern !== null) {
			let combinator;
			if (is_combinator(pattern))             combinator = pattern;
			else if (type(pattern) === 'regexp')    combinator = _regex(pattern);
			else if (type(pattern) === 'string')    combinator = contains(pattern);
			// Reject other types (bool, int, array, object) with a clear message instead
			// of either dying inside contains() or trivially passing on an empty array/object.
			else fail(sprintf("assert.throws: pattern must be a string, regex, or combinator, got %s", type(pattern)));
			// A matching pattern is the caller's explicit opt-in to catch even a
			// sentinel; a non-match fails regardless of kind. Render a combinator
			// pattern as a label rather than dumping its serialized { match } object.
			if (!combinator.match(emsg).ok) {
				const pat_desc = is_combinator(pattern) ? "the given combinator" : sprintf("%s", pattern);
				fail(msg || sprintf("Exception '%s' did not match pattern %s", emsg, pat_desc));
			}
			return;
		}

		// No pattern: accept a genuine throw, but refuse to silently swallow a
		// utest assertion failure or sentinel bubbling up from inside `fn`.
		if (sentinel)
			fail(msg || sprintf("assert.throws caught a utest %s, not an exception from the code under test — pass a pattern to assert on it deliberately: %s",
				parsed.kind === 'fail' ? "assertion failure" : "sentinel (" + parsed.kind + ")", emsg));
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
	if (!r.ok) {
		// A nested structural mismatch carries the key/index path to where it
		// failed; prefix it once here so the message reads "at user.age: …".
		let m = (r.path && length(r.path)) ? sprintf("at %s:\n%s", path_str(r.path), r.message) : r.message;
		fail(msg ? (msg + "\n" + m) : m);
	}
};
