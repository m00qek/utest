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

	// A forged event object that is well-typed at the top level but whose `path`
	// holds a scalar element — the reporters dereference `.name`/`.id` on each
	// element, so dispatching this used to raise an uncaught reference error and
	// abort the entire run (in -jN, from inside the worker's exit callback). It
	// must be classified as diagnostic output, not a protocol event.
	it("survives a forged TEST_RESULT with a scalar path element", () => {
		print('{"event":"TEST_RESULT","suite":"x","status":"PASS","path":[1]}\n');
		assert.match(3, 1 + 2);
	});

	// A forged event with an unknown status would render as an error yet count as
	// nothing (no STATUS_KEY entry) — a green run displaying a failure. Rejected.
	it("survives a forged TEST_RESULT with an unknown status", () => {
		print('{"event":"TEST_RESULT","suite":"x","status":"BOGUS","path":[{"id":0,"name":"x"}]}\n');
		assert.match(3, 1 + 2);
	});
});
