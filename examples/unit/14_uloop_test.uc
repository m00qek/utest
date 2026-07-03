import { describe, it, assert, mock, truthy, falsy } from 'utest';
import * as uloop from 'uloop';

// run() fires all registered timer callbacks synchronously — event-loop-driven code becomes testable without blocking.

describe('uloop Mocking', () => {
	it('run() fires registered timer callbacks synchronously', () => {
		mock.inject('uloop', {}, (m_uloop) => {
			let fired = false;
			m_uloop.timer(1000, () => { fired = true; });
			assert.match(falsy(), fired);
			m_uloop.run();
			assert.match(truthy(), fired);
		});
	});

	it('run() fires timers in deadline order, not registration order', () => {
		mock.inject('uloop', {}, (m_uloop) => {
			let order = [];
			m_uloop.timer(3000, () => push(order, 'a'));
			m_uloop.timer(1000, () => push(order, 'b'));
			m_uloop.run();
			// Real uloop fires the shorter deadline first, regardless of the order
			// the timers were armed; the mock must match to stay target-faithful.
			assert.match(['b', 'a'], order);
		});
	});

	it('run() fires equal-deadline timers in registration order', () => {
		mock.inject('uloop', {}, (m_uloop) => {
			let order = [];
			m_uloop.timer(100, () => push(order, 'first'));
			m_uloop.timer(100, () => push(order, 'second'));
			m_uloop.timer(100, () => push(order, 'third'));
			m_uloop.run();
			assert.match(['first', 'second', 'third'], order);
		});
	});

	it('run() clears the queue so a second run() does nothing', () => {
		mock.inject('uloop', {}, (m_uloop) => {
			let count = 0;
			m_uloop.timer(100, () => count++);
			m_uloop.run();
			m_uloop.run();
			assert.match(1, count);
		});
	});

	it('end() is a no-op and can be called freely from inside callbacks', () => {
		mock.inject('uloop', {}, (m_uloop) => {
			let done = false;
			m_uloop.timer(0, () => { m_uloop.end(); done = true; });
			m_uloop.run();
			assert.match(truthy(), done);
		});
	});

	it('models the io.sleep() pattern without blocking', () => {
		mock.inject('uloop', {}, (m_uloop) => {
			let ended = false;
			m_uloop.init();
			m_uloop.timer(5000, () => { m_uloop.end(); ended = true; });
			m_uloop.run();
			assert.match(truthy(), ended, 'sleep returned without blocking');
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
		assert.match(truthy(), run_called);
	});

	it('patches global state via mock.global.patch()', () => {
		const m_uloop = mock.global.patch('uloop', {});
		let fired = false;
		uloop.timer(500, () => { fired = true; });
		uloop.run();
		assert.match(truthy(), fired, 'shim transparently intercepts');
		mock.global.unpatch('uloop');
	});

	it('timers registered inside an inner inject() do not leak into the outer scope', () => {
		const fired = [];
		mock.inject('uloop', {}, (outer) => {
			outer.timer(100, () => push(fired, 'outer'));
			mock.inject('uloop', {}, (inner) => {
				inner.timer(50, () => push(fired, 'inner'));
			});
			outer.run();
		});
		assert.match(['outer'], fired, 'inner timer must not appear in outer pending queue');
	});

	it('running timers inside an inject does not re-fire an outer-scope timer', () => {
		// A timer registered at the global scope, then run() inside an inject,
		// used to fire and then be "cleared" only in the inject layer — leaving
		// the global queue intact so a later run() fired it a second time.
		let count = 0;
		mock.global.patch('uloop', {});
		uloop.timer(100, () => count++);
		mock.inject('uloop', {}, (inner) => {
			inner.run();
		});
		uloop.run();
		mock.global.unpatch('uloop');
		assert.match(1, count, 'global timer must fire exactly once');
	});
});
