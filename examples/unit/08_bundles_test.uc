import { describe, it, assert } from 'utest';

// Run with a name: utest 'MyBundle:examples/unit/08_bundles_test.uc'

describe("Bundles", () => {
	it("demonstrates how tests are grouped into bundles", () => {
		assert.match(true, true);
	});
});
