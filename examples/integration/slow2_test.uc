import { describe, it, assert } from 'utest';

describe("Slow Suite 2", () => {
	it("takes 2 seconds", () => {
		sleep(2000);
		assert.match(true, true);
	});
});
