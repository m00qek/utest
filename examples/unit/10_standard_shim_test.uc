import { describe, it, assert, mock } from 'utest';
import * as math from 'math';

// Auto-shim: mock.inject() scopes to proxy; mock.global.patch() also intercepts the imported module.

describe('Generic Proxy (math)', () => {
	it('real module is unaffected by default', () => {
		assert.match(7, math.abs(-7));
		assert.match(3, math.abs(3));
	});

	it('mock.inject() only intercepts via proxy, not imported module', () => {
		mock.inject('math', { behavior: { abs: () => 99 } }, (m_math) => {
			assert.match(99, m_math.abs(-4));
			assert.match(4, math.abs(-4));
		});
	});

	it('passes through non-overridden functions during mock.inject()', () => {
		mock.inject('math', { behavior: { rand: () => 0 } }, (m_math) => {
			assert.match(5, m_math.abs(-5));
		});
	});

	it('restores real function after mock.inject()', () => {
		mock.inject('math', { behavior: { abs: () => 0 } }, (m_math) => {});
		assert.match(9, math.abs(-9));
	});

	it('mock.global.patch() transparently intercepts the imported module via shim', () => {
		const m_math = mock.global.patch('math', { behavior: { abs: () => 42 } });
		assert.match(42, m_math.abs(-1));
		assert.match(42, math.abs(-1));
		mock.global.unpatch('math');

		assert.match(1, m_math.abs(-1));
		assert.match(1, math.abs(-1));
	});
});
