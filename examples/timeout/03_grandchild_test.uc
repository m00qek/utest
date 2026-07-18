import { describe, it, assert } from 'utest';

// A worker that forks a background grandchild, then hangs. Confirms the
// timeout kill reaches the worker's whole process group, not just the worker
// PID. The grandchild deliberately inherits the worker's stdout (no
// redirection) — under the sequential executor that is the executor's own
// read pipe, so a surviving grandchild holds its write end open forever and
// the blocking read never sees EOF; under the parallel executor it would
// simply linger as an orphan after the worker's own SIGKILL. `sleep 30`
// outlives the fixture's 2s timeout and is unique enough within the
// container's PID namespace for the harness to check for its absence.
describe("Grandchild-spawning suite", () => {
	it("forks a background child", () => {
		system("sleep 30 &");
		assert.match(1, 1);
	});
	it("never returns", () => { while (true) {} });
});
