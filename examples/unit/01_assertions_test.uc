import { describe, it } from 'utest';
import { assert, has } from 'utest.assert';

describe("Assertions", () => {
	it("assert.eq() passes for deeply equal values and fails otherwise", () => {
		assert.eq({ a: 1, b: [2, 3] }, { a: 1, b: [2, 3] });
		assert.throws(() => assert.eq(1, 2), /Expected/);
		assert.throws(() => assert.eq(1, 2, 'custom'), /custom/);
		assert.throws(() => assert.eq({ x: 1 }, { x: 1, y: 2 }), /keys/);
	});

	it("assert.ne() passes when values differ and fails otherwise", () => {
		assert.ne(1, 2);
		assert.ne('a', 'b');
		assert.ne({ a: 1 }, { a: 2 });
		assert.throws(() => assert.ne(1, 1), /differ/);
	});

	it("assert.ok() passes for truthy values and fails otherwise", () => {
		assert.ok(true);
		assert.ok(length("hello") > 0);
		assert.throws(() => assert.ok(false), /truthy/);
		assert.throws(() => assert.ok(null), /truthy/);
	});

	it("assert.notOk() passes for falsy values and fails otherwise", () => {
		assert.notOk(false);
		assert.notOk(null);
		assert.notOk(0);
		assert.throws(() => assert.notOk(true), /falsy/);
	});

	it("assert.matches() passes when string matches regex and fails otherwise", () => {
		assert.matches("OpenWrt 24.10", /24\.10/);
		assert.matches("utest@v1.0.0", /^utest/);
		assert.throws(() => assert.matches("hello", /^\d+/), /to match/);
	});

	it("assert.notMatches() passes when string does not match regex and fails otherwise", () => {
		assert.notMatches("hello", /^\d+/);
		assert.throws(() => assert.notMatches("hello", /^hello/), /not to match/);
	});

	it("assert.throws() passes when exception is thrown, with optional pattern", () => {
		assert.throws(() => { let x = null; return x.property; }, /null/);
		assert.throws(() => assert.throws(() => {}), /Expected exception/);
		assert.throws(
			() => assert.throws(() => die('boom'), /xyz/),
			/did not match/
		);
	});

	it("assert.notThrows() passes when no exception is thrown and fails otherwise", () => {
		assert.notThrows(() => { let x = 1 + 1; });
		assert.throws(
			() => assert.notThrows(() => die('boom')),
			/Expected no exception/
		);
	});

	it("assert.contains() passes when haystack contains needle and fails otherwise", () => {
		assert.contains("OpenWrt 24.10", "24.10");
		assert.contains([1, 2, 3], 2);
		assert.contains([{ a: 1 }, { b: 2 }], { b: 2 });
		assert.throws(() => assert.contains("hello", "xyz"), /contain/);
		assert.throws(() => assert.contains([1, 2], 3), /contain/);
	});

	it("assert.contains() accepts a combinator as needle", () => {
		assert.contains([{ id: 1, extra: 'ignored' }, { id: 2 }], has({ id: 1 }));
		assert.throws(
			() => assert.contains([{ id: 2 }], has({ id: 1 })),
			/contain/
		);
	});
});
