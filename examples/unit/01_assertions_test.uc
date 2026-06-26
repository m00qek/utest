import { describe, it, assert, contains } from 'utest';

describe("Assertions", () => {
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
});
