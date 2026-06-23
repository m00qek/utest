import { describe, it, assert, setup } from 'utest';

// Demonstrates a module-level setup() that throws.
// All tests in the module are skipped and a FATAL is reported.

setup(() => {
	die("intentional");
});

describe("Fatal setup demo", () => {
	it("is never reached because setup() threw", () => {
		assert.match(true, true);
	});
});
