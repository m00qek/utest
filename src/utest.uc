import * as dsl from 'utest.dsl';
import { mock as _mock } from 'utest.mock.engine';
import { assert as _assert } from 'utest.assert';

export const describe = dsl.describe;
export const xdescribe = dsl.xdescribe;
export const it = dsl.it;
export const skip = dsl.skip;
export const beforeEach = dsl.beforeEach;
export const afterEach = dsl.afterEach;
export const setup = dsl.setup;
export const teardown = dsl.teardown;
export const mock = _mock;
export const assert = _assert;
