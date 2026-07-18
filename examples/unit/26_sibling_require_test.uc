import { describe, it, assert } from 'utest';

// Regression: a test must be able to require() a helper module sitting next to
// it.  The worker appends the test's directory to REQUIRE_SEARCH_PATH; that
// entry used to be a bare directory (never matched), so require() of a sibling
// failed with "No module named ...".  It must now be a proper glob template.
// See 01_requireshadow_test.uc (examples/requireshadow/) for why it is
// appended, not prepended: a same-named sibling file must not outrank a
// properly configured module (shim, lib_paths, etc.).
describe("sibling require()", () => {
	it("resolves a program-mode helper next to the test file", () => {
		let helper = require("26_sibling_require_helper");
		assert.match(10, helper.double(5));
	});
});
