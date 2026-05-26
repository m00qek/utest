import { describe, it, assert } from 'utest';

// FAIL = assertion error; ERROR = runtime crash.

describe("Diagnostic Reporting", () => {
	it("is a failure (Assertion Error)", () => {
		assert.match(3, 1 + 1, "Arithmetic is failing");
	});

	it("is an error (Runtime Exception)", () => {
		let user = null;
		return user.name;
	});
});
