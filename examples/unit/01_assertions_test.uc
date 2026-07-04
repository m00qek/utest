import { describe, it, assert, contains, is_combinator, equals } from 'utest';

describe("Assertions", () => {
	it("assert.fail() raises a catchable FAIL", () => {
		// Reports as FAIL (not ERROR like a bare die); assert.throws with a matching
		// pattern is the explicit opt-in to catch a utest failure.
		assert.throws(() => assert.fail("unreachable branch"), /unreachable branch/);
		assert.throws(() => assert.fail(), /assert.fail/);
	});

	it("is_combinator is exported from the umbrella", () => {
		assert.match(true, is_combinator(equals(1)));
		assert.match(false, is_combinator(42));
	});

	it("assert.match() passes for deeply equal values", () => {
		assert.match({ a: 1, b: [2, 3] }, { a: 1, b: [2, 3] });
		assert.throws(() => assert.match(2, 1), /Expected/);
		assert.throws(() => assert.match(2, 1, 'custom'), /custom/);
		assert.throws(() => assert.match({ x: 1, y: 2 }, { x: 1 }), /keys/);
	});

	it("assert.throws() passes when exception is thrown, with optional pattern", () => {
		assert.throws(() => { let x = null; return x.property; }, /null/);
		assert.throws(() => assert.throws(() => {}), /Expected exception/);
		assert.throws(
			() => assert.throws(() => die('boom'), /xyz/),
			/did not match/
		);
	});

	it("assert.throws() without a pattern rejects a swallowed assertion failure", () => {
		// The bug: assert.throws(() => assert.match(1, 2)) used to pass, silently
		// swallowing a real assertion failure inside fn. It must now itself fail.
		assert.throws(
			() => assert.throws(() => assert.match(1, 2)),
			/caught a utest assertion failure/
		);
	});

	it("assert.throws() with a matching pattern may catch an assertion failure deliberately", () => {
		// Explicit opt-in: a pattern that matches the assertion message is allowed.
		assert.throws(() => assert.match(1, 2), /Expected 1/);
	});

	it("assert.throws() without a pattern still accepts a genuine exception", () => {
		assert.throws(() => die("boom"));
		assert.throws(() => { let x = null; return x.property; });
	});

	it("assert.throws() accepts a string pattern (regex string)", () => {
		assert.throws(() => die("fatal error"), "fatal error");
		assert.throws(() => die("fatal error"), "fatal");
		assert.throws(
			() => assert.throws(() => die("boom"), "xyz"),
			/did not match/
		);
	});

	it("assert.throws() accepts a combinator as pattern", () => {
		assert.throws(() => die("fatal error"), contains("fatal"));
		assert.throws(
			() => assert.throws(() => die("boom"), contains("xyz")),
			/did not match/
		);
	});

	it("assert.throws() reports a non-matching combinator pattern as a label", () => {
		// The failure message must not dump the combinator's serialized { match }
		// object; it should read "pattern the given combinator".
		assert.throws(
			() => assert.throws(() => die("boom"), contains("xyz")),
			/did not match pattern the given combinator/
		);
	});
});
