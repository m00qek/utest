import { describe, it, skip } from 'utest';
import { assert } from 'utest.assert';

/**
 * Skipping Tests
 * 
 * Use skip() instead of it() to temporarily disable a test.
 * Skipped tests are reported but their contents are never executed.
 */

describe("Feature: Authentication", () => {
	it("works with valid credentials", () => {
		assert.ok(true);
	});

	skip("works with OAuth2 (Not implemented yet)", () => {
		// This block is never executed.
		// You can put failing code or TODOs here.
		assert.ok(false); 
	});

	describe("Legacy API", () => {
		// Nested skip
		skip("handles XML responses", () => {
			assert.ok(false);
		});
	});
});
