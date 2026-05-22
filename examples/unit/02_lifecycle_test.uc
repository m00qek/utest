import { describe, it, beforeEach, afterEach, setup, teardown } from 'utest';
import { assert } from 'utest.assert';

/**
 * Test Lifecycle Hooks
 * 
 * utest provides hooks at two levels:
 * 1. Global (Module) level: setup(), teardown()
 * 2. Suite level: beforeEach(), afterEach()
 */

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
		assert.match(suite_val, 100);
		suite_val += 50;
	});

	it("sees a reset value in the next test", () => {
		// Even though the previous test modified suite_val, 
		// beforeEach has run again.
		assert.match(suite_val, 100);
	});

	it("has access to global setup state", () => {
		assert.match(state[0], "GLOBAL_SETUP");
	});
});
