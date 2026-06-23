import { describe, it, assert } from 'utest';

// Part of the multi-bundle regression test.  Run together with 02_bundle_b_test.uc
// via meta-test.sh to exercise cross-bundle stat aggregation.

describe("Bundle A", () => {
	it("passes in bundle A", () => {
		assert.match(true, true);
	});
});
