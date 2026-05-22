import { describe, it, mock, truthy, falsy } from 'utest';
import { assert } from 'utest.assert';
import * as uloop from 'uloop';

/**
 * uloop Mocking Example
 *
 * The key behaviour: run() fires all registered timer callbacks synchronously,
 * so code that drives an event loop (io.sleep, uclient requests) becomes
 * testable without blocking. Declare the module in config.mocks
 * (see 13_uloop_config.uc) so the framework generates the shim.
 */

describe('uloop Mocking', () => {
	it('run() fires registered timer callbacks synchronously', () => {
		mock.inject('uloop', {}, (m_uloop) => {
			let fired = false;
			m_uloop.timer(1000, () => { fired = true; });
			assert.match(fired, falsy());
			m_uloop.run();
			assert.match(fired, truthy());
		});
	});

	it('run() fires multiple timers in registration order', () => {
		mock.inject('uloop', {}, (m_uloop) => {
			let order = [];
			m_uloop.timer(3000, () => push(order, 'a'));
			m_uloop.timer(1000, () => push(order, 'b'));
			m_uloop.run();
			assert.match(order, ['a', 'b']);
		});
	});

	it('run() clears the queue so a second run() does nothing', () => {
		mock.inject('uloop', {}, (m_uloop) => {
			let count = 0;
			m_uloop.timer(100, () => count++);
			m_uloop.run();
			m_uloop.run();
			assert.match(count, 1);
		});
	});

	it('end() is a no-op and can be called freely from inside callbacks', () => {
		mock.inject('uloop', {}, (m_uloop) => {
			let done = false;
			m_uloop.timer(0, () => { m_uloop.end(); done = true; });
			m_uloop.run();
			assert.match(done, truthy());
		});
	});

	it('models the io.sleep() pattern without blocking', () => {
		mock.inject('uloop', {}, (m_uloop) => {
			let ended = false;
			m_uloop.init();
			m_uloop.timer(5000, () => { m_uloop.end(); ended = true; });
			m_uloop.run();
			assert.match(ended, truthy(), 'sleep returned without blocking');
		});
	});

	it('supports behavior override for run()', () => {
		let run_called = false;
		mock.inject('uloop', {
			behavior: { run: () => { run_called = true; } }
		}, (m_uloop) => {
			m_uloop.timer(100, () => {});
			m_uloop.run();
		});
		assert.match(run_called, truthy());
	});

	it('patches global state via mock.global.patch()', () => {
		const m_uloop = mock.global.patch('uloop', {});
		let fired = false;
		uloop.timer(500, () => { fired = true; });
		uloop.run();
		assert.match(fired, truthy(), 'shim transparently intercepts');
		mock.global.unpatch('uloop');
	});
});
