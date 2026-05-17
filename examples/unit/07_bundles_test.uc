import { describe, it } from 'utest';
import { assert } from 'utest.assert';

/**
 * Bundles Feature
 * 
 * Bundles allow you to group test files and give them a descriptive name.
 * You can define bundles via the CLI using the "Name:Path" syntax.
 * 
 * Example:
 *   utest "Core:examples/unit/01_*.uc" "Logic:examples/unit/02_*.uc"
 */

describe("Bundles", () => {
	it("demonstrates how tests are grouped into bundles", () => {
		assert.ok(true, "This test will be reported under its assigned bundle name");
	});
});
