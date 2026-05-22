import { describe, it, equals, contains, truthy, falsy, not, regex } from 'utest';
import { assert } from 'utest.assert';

describe("Assertions", () => {
	it("assert.match() passes for deeply equal values", () => {
		assert.match({ a: 1, b: [2, 3] }, { a: 1, b: [2, 3] });
		assert.throws(() => assert.match(1, 2), /Expected/);
		assert.throws(() => assert.match(1, 2, 'custom'), /custom/);
		assert.throws(() => assert.match({ x: 1 }, { x: 1, y: 2 }), /keys/);
	});

	it("not(equals()) passes when values differ", () => {
		assert.match(1, not(equals(2)));
		assert.match('a', not(equals('b')));
		assert.throws(() => assert.match(1, not(equals(1))), /not to match/);
	});

	it("truthy() passes for truthy values and fails otherwise", () => {
		assert.match(true, truthy());
		assert.match(1, truthy());
		assert.throws(() => assert.match(false, truthy()), /truthy/);
		assert.throws(() => assert.match(null, truthy()), /truthy/);
	});

	it("falsy() passes for falsy values and fails otherwise", () => {
		assert.match(false, falsy());
		assert.match(null, falsy());
		assert.match(0, falsy());
		assert.throws(() => assert.match(true, falsy()), /falsy/);
	});

	it("regex() passes when string matches pattern and fails otherwise", () => {
		assert.match("OpenWrt 24.10", regex(/24\.10/));
		assert.match("utest@v1.0.0", regex(/^utest/));
		assert.throws(() => assert.match("hello", regex(/^\d+/)), /match/);
	});

	it("not(regex()) passes when string does not match pattern", () => {
		assert.match("hello", not(regex(/^\d+/)));
		assert.throws(() => assert.match("hello", not(regex(/^hello/))), /not to match/);
	});

	it("assert.throws() passes when exception is thrown, with optional pattern", () => {
		assert.throws(() => { let x = null; return x.property; }, /null/);
		assert.throws(() => assert.throws(() => {}), /Expected exception/);
		assert.throws(
			() => assert.throws(() => die('boom'), /xyz/),
			/did not match/
		);
	});

	it("assert.match() with contains() for substring and array containment", () => {
		assert.match("OpenWrt 24.10", contains("24.10"));
		assert.match([1, 2, 3], contains([2]));
		assert.match([{ a: 1 }, { b: 2 }], contains([{ b: 2 }]));
		assert.throws(() => assert.match("hello", contains("xyz")), /contain/);
		assert.throws(() => assert.match([1, 2], contains([3])), /contain/);
	});

	it("assert.match() with contains() accepts a combinator element", () => {
		assert.match([{ id: 1, extra: 'ignored' }, { id: 2 }], contains([contains({ id: 1 })]));
		assert.throws(
			() => assert.match([{ id: 2 }], contains([contains({ id: 1 })])),
			/contain/
		);
	});
});
