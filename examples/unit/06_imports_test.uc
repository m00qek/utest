import { describe, it } from 'utest';
import { assert } from 'utest.assert';
import { get_test_data } from 'helper';

/**
 * Module Imports
 * 
 * utest supports standard ucode imports. You can share helpers 
 * between test files.
 */

describe("Helper Integration", () => {
	it("uses data from a helper module", () => {
		const data = get_test_data();
		assert.match(data.key, "value");
	});
});
