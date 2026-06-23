import { describe, it, assert } from 'utest';

// Demonstrates the --filter / config.filter feature.
// Run with the companion config (23_filter_config.uc) which sets
// filter: "matches the filter".  The second test is ignored (IGNORE),
// proving that excluded tests are counted but never executed.

describe("Filter demo", () => {
	it("matches the filter", () => {
		assert.match(true, true);
	});

	it("does not match and is ignored", () => {
		// Would fail if executed; filter keeps it from running.
		assert.match(true, false);
	});
});
