import { describe, it, assert } from 'utest';

// Part of the multi-bundle regression test.  Run together with 01_bundle_a_test.uc
// via meta-test.sh to exercise cross-bundle stat aggregation.

describe("Bundle B", () => {
	it("passes in bundle B", () => {
		assert.match(true, true);
	});
});
