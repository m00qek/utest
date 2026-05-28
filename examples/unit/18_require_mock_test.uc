import { describe, it, assert, mock } from 'utest';
import { compute_abs } from '18_require_mock_helper';

// Verifies that mock.global.patch() intercepts require() calls in program-mode
// code under test, not just ES-module import statements.

describe("require() interception via mock.global.patch()", () => {
	it('returns real module when no patch is active', () => {
		assert.match(7, compute_abs(-7));
	});

	it('intercepts require() in program-mode code when patch is active', () => {
		mock.global.patch('math', { behavior: { abs: () => 42 } });
		assert.match(42, compute_abs(-1));
		mock.global.unpatch('math');
	});

	it('restores real module after unpatch', () => {
		mock.global.patch('math', { behavior: { abs: () => 0 } });
		mock.global.unpatch('math');
		assert.match(5, compute_abs(-5));
	});
});
