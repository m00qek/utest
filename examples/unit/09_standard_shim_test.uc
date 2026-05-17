import { describe, it, mock } from 'utest';
import { assert } from 'utest.assert';
import * as math from 'math';

/**
 * Generic Proxy + Auto-Shim Example
 *
 * Declaring a module in config.mocks (see 09_standard_shim_config.uc) tells
 * utest to auto-generate a generic shim for it — no custom proxy file required.
 * The shim intercepts all function calls through the mock engine so that:
 *   - mock.global.patch() sets global state → the imported `math` is intercepted
 *   - mock.inject() sets scoped state → only the proxy `m_math` sees it;
 *     the imported `math` (shim) passes through to the real module
 *
 * Custom proxies work the same way: write src/utest/mock/proxy/<name>.uc and
 * the framework uses it automatically when the module is listed in config.mocks.
 */

describe('Generic Proxy (math)', () => {
	it('real module is unaffected by default', () => {
		assert.eq(math.abs(-7), 7);
		assert.eq(math.abs(3), 3);
	});

	it('mock.inject() only intercepts via proxy, not imported module', () => {
		mock.inject('math', { behavior: { abs: () => 99 } }, (m_math) => {
			assert.eq(m_math.abs(-4), 99);
			assert.eq(math.abs(-4), 4);
		});
	});

	it('passes through non-overridden functions during mock.inject()', () => {
		mock.inject('math', { behavior: { rand: () => 0 } }, (m_math) => {
			assert.eq(m_math.abs(-5), 5);
		});
	});

	it('restores real function after mock.inject()', () => {
		mock.inject('math', { behavior: { abs: () => 0 } }, (m_math) => {});
		assert.eq(math.abs(-9), 9);
	});

	it('mock.global.patch() transparently intercepts the imported module via shim', () => {
		const m_math = mock.global.patch('math', { behavior: { abs: () => 42 } });
		assert.eq(m_math.abs(-1), 42);
		assert.eq(math.abs(-1), 42);
		mock.global.unpatch('math');

		assert.eq(m_math.abs(-1), 1);
		assert.eq(math.abs(-1), 1);
	});
});
