import { describe, it } from 'utest';
// Intentionally imports a module that does not exist, so the worker fails to
// compile this file. Named without the _test.uc suffix so the meta-test's main
// discovery loop skips it; it is exercised by the dedicated load-fatal check,
// which asserts the runner emits a FATAL (not a silent vanish) and exits non-zero.
import * as missing from 'utest_no_such_module';

describe('unreachable', () => {
	it('never compiles', () => {});
});
