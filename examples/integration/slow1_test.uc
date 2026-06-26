import { describe, it, assert } from 'utest';

describe("Slow Suite 1", () => {
	it("takes 2 seconds", () => {
		sleep(2000);
		assert.match(true, true);
	});
});
