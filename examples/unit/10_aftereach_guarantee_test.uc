import { describe, it, afterEach, setup, teardown } from 'utest';
import { assert } from 'utest.assert';

let afterEach_count = 0;

setup(() => { afterEach_count = 0; });

teardown(() => {
	assert.eq(afterEach_count, 2, 'afterEach must run for every test, including failing ones');
});

describe('afterEach guarantee', () => {
	afterEach(() => { afterEach_count++; });

	it('a passing test', () => {
		assert.ok(true);
	});

	it('a failing test (afterEach must still run)', () => {
		die('intentional failure');
	});
});
