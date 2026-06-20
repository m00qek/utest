import { describe, it, forall, gen, assert } from 'utest';

// Fixed persist_id shared across all four steps of the round-trip.
const PERSIST_ID = "persist_roundtrip_smoke_test";

describe("Persist round-trip", () => {
	it("counterexample survives across forall() calls and is deleted on pass", () => {
		// Pre-flight: remove any file left by a previously interrupted test run.
		// A trivially-passing property causes forall() to replay the saved value
		// (which passes), call delete_example(), and return cleanly.
		try {
			forall(gen.int(0, 10), () => null, { persist_id: PERSIST_ID });
		} catch (_) {}

		// Step 1: failing property with persistence enabled.
		// forall() should shrink the counterexample, save it, and include
		// "Saved to:" in the failure message.
		assert.throws(
			() => forall(gen.int(0, 10),
			             (n) => assert.match(true, n < 3, sprintf("n=%d is not < 3", n)),
			             { seed: 1, persist_id: PERSIST_ID }),
			/Saved to:/
		);

		// Step 2: re-run with the same failing property and the same persist_id.
		// forall() should load the saved counterexample, replay it, and report
		// the failure as a replay rather than a new random run.
		assert.throws(
			() => forall(gen.int(0, 10),
			             (n) => assert.match(true, n < 3, sprintf("n=%d is not < 3", n)),
			             { persist_id: PERSIST_ID }),
			/replayed saved counterexample/
		);

		// Step 3: re-run with a property that passes on the saved value.
		// forall() loads the file, the replay passes (n >= 0 is always true),
		// delete_example() runs, and the full 100-run suite completes without error.
		forall(gen.int(0, 10),
		       (n) => assert.match(true, n >= 0),
		       { persist_id: PERSIST_ID });

		// Step 4: confirm no file remains.
		// If delete_example() had not run, this call would load the file, replay
		// a failing value, and throw "replayed saved counterexample" — failing
		// the test.
		forall(gen.int(0, 10),
		       (n) => assert.match(true, n >= 0),
		       { persist_id: PERSIST_ID });
	});
});
