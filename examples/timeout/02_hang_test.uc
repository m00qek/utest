import { describe, it, assert } from 'utest';

// A worker that hangs partway through a suite. The tests before the hang must
// still appear in the report: the worker reporter flushes stdout after every
// event, so their results reach the parent before the timeout kill (SIGKILL
// under -jN, SIGTERM under -j1) discards whatever is left. Without that flush,
// musl's fully-buffered stdout would swallow every result after SUITE_START and
// "partial results above" would show nothing. The companion config pins a seed
// so the shuffled order — and therefore which tests land before the hang — is
// deterministic for the golden baseline.
describe("Hanging suite", () => {
	it("first quick check", () => assert.match(1, 1));
	it("second quick check", () => assert.match(2, 2));
	it("third quick check", () => assert.match(3, 3));
	it("never returns", () => { while (true) {} });
});
