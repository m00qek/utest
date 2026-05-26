import { describe, it, assert } from 'utest';
import { get_test_data } from 'helper';

describe("Helper Integration", () => {
	it("uses data from a helper module", () => {
		const data = get_test_data();
		assert.match("value", data.key);
	});
});
