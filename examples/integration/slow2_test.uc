import { describe, it } from 'utest';
import { assert } from 'utest.assert';

describe("Slow Suite 2", () => {
	it("takes 2 seconds", () => {
		sleep(2000);
		assert.ok(true);
	});
});
