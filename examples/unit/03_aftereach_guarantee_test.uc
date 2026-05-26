import { describe, it, assert, afterEach, setup, teardown, truthy } from 'utest';

let afterEach_count = 0;

setup(() => { afterEach_count = 0; });

teardown(() => {
	assert.match(2, afterEach_count, 'afterEach must run for every test, including failing ones');
});

describe('afterEach guarantee', () => {
	afterEach(() => { afterEach_count++; });

	it('a passing test', () => {
		assert.match(true, true);
	});

	it('a failing test (afterEach must still run)', () => {
		assert.match(truthy(), false, 'intentional failure');
	});
});
