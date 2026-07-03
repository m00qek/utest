import { describe, it, assert, is_type } from 'utest';

// Env-passthrough probe for the parallel executor (see scripts/meta-test.sh).
// uloop.process is exec-style: it builds the child's environment from exactly
// the dict it is given, so an empty dict would leave a -jN worker with no
// environment at all. This fixture is run identically under -j1 (in-process)
// and -j2 (through a spawned worker) against one baseline; the harness sets
// UTEST_ENV_PROBE on the parent, so the -j2 run only matches if the worker
// actually inherited it. A custom variable is used rather than PATH because the
// container ships a shell fallback PATH that would mask a truly empty envp.
describe("Environment passthrough", () => {
	it("a worker sees the parent's custom environment variable", () => {
		assert.match("present", getenv("UTEST_ENV_PROBE"));
	});

	it("a worker sees the parent's PATH", () => {
		assert.match(is_type('string'), getenv("PATH"));
	});
});
