import { describe, it, assert, teardown } from 'utest';

// Demonstrates a module-level teardown() that throws.
// Tests run normally first; teardown() failure is then recorded as FATAL
// alongside the passing results — stats.fatals=1, stats.passed=1.

teardown(() => {
	die("intentional");
});

describe("Fatal teardown demo", () => {
	it("runs before teardown() throws", () => {
		assert.match(true, true);
	});
});
