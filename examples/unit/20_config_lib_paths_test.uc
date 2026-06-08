import { describe, it, assert } from 'utest';
import { greet } from 'greeting';

describe("Config-relative lib paths", () => {
	it("resolves a relative lib_paths entry against the config file's directory", () => {
		assert.match("hello from config lib path", greet());
	});
});
