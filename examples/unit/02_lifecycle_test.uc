import { describe, it, assert, beforeEach, afterEach, setup, teardown } from 'utest';

// Demonstrates setup(), teardown(), beforeEach(), and afterEach() hooks.

let state = [];

// Global setup: runs once before any tests in this module
setup(() => {
	push(state, "GLOBAL_SETUP");
});

// Global teardown: runs once after all tests in this module
teardown(() => {
	// In a real scenario, you might close database connections here
	push(state, "GLOBAL_TEARDOWN");
});

describe("Lifecycle Hooks", () => {
	let suite_val = 0;

	// Runs before every test in THIS describe block
	beforeEach(() => {
		suite_val = 100;
	});

	// Runs after every test in THIS describe block
	afterEach(() => {
		suite_val = 0;
	});

	it("sees the value from beforeEach", () => {
		assert.match(100, suite_val);
		suite_val += 50;
	});

	it("sees a reset value in the next test", () => {
		// Even though the previous test modified suite_val, 
		// beforeEach has run again.
		assert.match(100, suite_val);
	});

	it("has access to global setup state", () => {
		assert.match("GLOBAL_SETUP", state[0]);
	});
});

describe("declaration-time validation", () => {
	// it()/describe() validate their body at declaration (before it can register),
	// so a missing/non-function body fails clearly instead of exploding at run time
	// as an opaque "left-hand side is not a function". The dying calls abort before
	// touching the suite tree, so exercising them here is safe. (beforeEach/afterEach
	// validate the same way, but guard() blocks calling them during a run.)
	it("it() with no body dies pointing at skip()", () => {
		assert.throws(() => it("pending"), /needs a function body/);
	});

	it("it() with a non-function body dies", () => {
		assert.throws(() => it("bad", 42), /needs a function body/);
	});

	it("describe() with a non-function body dies", () => {
		assert.throws(() => describe("bad", 42), /requires a function argument/);
	});
});
