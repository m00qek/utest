import { describe, it, assert } from 'utest';

// Regression: a test that writes a bare scalar to stdout produces a line that
// parses as valid JSON but is not an event object.  The executor must treat it
// as diagnostic output, not a protocol message — dereferencing .event on it
// used to crash the whole runner (both -j1 and -jN paths).
describe("hostile worker stdout", () => {
	it("survives a test printing bare scalar JSON lines", () => {
		print("42\n");
		print("true\n");
		print("null\n");
		print("\"a bare string\"\n");
		print("[1, 2, 3]\n");
		assert.match(3, 1 + 2);
	});

	it("still runs later tests in the same suite", () => {
		assert.match(true, true);
	});
});
