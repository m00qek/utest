import { describe, it, assert, setup } from 'utest';

// Demonstrates a module-level setup() that throws.
// setup() failure is fatal: no test results are emitted and stats.fatals is 1.

setup(() => {
	die("intentional");
});

describe("Fatal setup demo", () => {
	it("is never reached because setup() threw", () => {
		assert.match(true, true);
	});
});
