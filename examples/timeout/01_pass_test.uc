import { describe, it, assert } from 'utest';

// One bundle passes normally while another bundle's worker hangs and is killed
// by the timeout — exercising the uloop executor's per-worker timeout under a
// multi-bundle parallel run. See scripts/meta-test.sh for the combined check.
describe("Passing suite", () => {
	it("completes normally", () => assert.match(1, 1));
});
