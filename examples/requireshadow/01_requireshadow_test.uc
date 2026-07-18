import { describe, it, assert } from 'utest';

// This directory ships its own greeting.uc (a decoy); the companion config
// also adds greeting_lib/ as a lib_paths entry, which provides the real one.
// The test's own directory must rank below every fixed tier (lib_paths
// included) — see bootstrap.uc's REQUIRE_SEARCH_PATH template for the test's
// own directory (push, not unshift) — so a coincidentally same-named sibling
// file cannot silently outrank a properly configured module.
describe("Test-directory require priority", () => {
	it("a same-named sibling file does not outrank lib_paths", () => {
		let greeting = require('greeting');
		assert.match("REAL (lib_paths)", greeting.greet());
	});
});
