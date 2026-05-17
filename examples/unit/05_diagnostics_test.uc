import { describe, it } from 'utest';
import { assert } from 'utest.assert';

/**
 * Failures vs Errors
 * 
 * utest distinguishes between two types of non-passing tests:
 * 1. FAIL: An assertion failed (intentional logic check).
 * 2. ERROR: A runtime exception occurred (unexpected crash).
 */

describe("Diagnostic Reporting", () => {
	it("is a failure (Assertion Error)", () => {
		assert.eq(1 + 1, 3, "Arithmetic is failing");
	});

	it("is an error (Runtime Exception)", () => {
		let user = null;
		print(user.name); // This will crash because user is null
	});
});
