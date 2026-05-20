import { describe, it } from 'utest';
import { assert } from 'utest.assert';

/**
 * Basic Assertions
 * 
 * This example demonstrates the fundamental assertion types provided by utest.
 */

describe("Assertions", () => {
	it("checks for deep equality with assert.eq()", () => {
		const actual = { a: 1, b: [2, 3] };
		const expected = { a: 1, b: [2, 3] };
		
		assert.eq(actual, expected, "Objects should be deeply equal");
	});

	it("checks for truthiness with assert.ok()", () => {
		assert.ok(true);
		assert.ok(length("hello") > 0);
		assert.ok({ some: "data" });
	});

	it("matches strings against regex with assert.match()", () => {
		assert.match("OpenWrt 24.10", /24\.10/);
		assert.match("utest@v1.0.0", /^utest/);
	});

	it("verifies exceptions with assert.throws()", () => {
		const block = () => {
			let x = null;
			return x.property; // This will throw
		};

		assert.throws(block, /left-hand side is not a function|null/);
	});

	it("verifies no exception with assert.notThrows()", () => {
		assert.notThrows(() => { let x = 1 + 1; });
		assert.notThrows(() => { return "safe"; }, "safe call must not throw");
	});

	it("checks string and array containment with assert.contains()", () => {
		assert.contains("OpenWrt 24.10", "24.10");
		assert.contains([1, 2, 3], 2);
		assert.contains([{ a: 1 }, { b: 2 }], { b: 2 });
	});
});
