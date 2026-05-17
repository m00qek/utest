import { describe, it, mock } from 'utest';
import { assert } from 'utest.assert';
import * as ubus from 'ubus';

/**
 * ubus Mocking Example
 *
 * Data keys use the 'object:method' format. A bare 'object' key serves as a
 * fallback for any method on that object. Declare the module in config.mocks
 * (see 11_ubus_config.uc) so the framework generates the shim.
 */

describe('ubus Mocking', () => {
	it('returns mocked data for object:method key', () => {
		mock.inject('ubus', {
			data: { 'system:board': { model: 'Test Router', hostname: 'OpenWrt' } }
		}, (m_ubus) => {
			let conn = m_ubus.connect();
			assert.eq(conn.call('system', 'board', {}), { model: 'Test Router', hostname: 'OpenWrt' });
		});
	});

	it('falls back to object key for any method', () => {
		mock.inject('ubus', {
			data: { 'network': { up: true } }
		}, (m_ubus) => {
			let conn = m_ubus.connect();
			assert.ok(conn.call('network', 'status', {}).up);
			assert.ok(conn.call('network', 'get_status', {}).up);
		});
	});

	it('returns null for unmocked calls in non-strict mode', () => {
		mock.inject('ubus', { data: {} }, (m_ubus) => {
			assert.eq(m_ubus.connect().call('unmocked', 'method', {}), null);
		});
	});

	it('supports function values for dynamic responses', () => {
		mock.inject('ubus', {
			data: { 'network:status': (args) => ({ up: args.interface == 'wan' }) }
		}, (m_ubus) => {
			let conn = m_ubus.connect();
			assert.ok(conn.call('network', 'status', { interface: 'wan' }).up);
			assert.notOk(conn.call('network', 'status', { interface: 'lan' }).up);
		});
	});

	it('supports behavior override for call', () => {
		mock.inject('ubus', {
			behavior: { call: (obj, method, args) => ({ routed: obj + '.' + method }) }
		}, (m_ubus) => {
			assert.eq(m_ubus.connect().call('system', 'board', {}).routed, 'system.board');
		});
	});

	it('supports nesting mock.inject()', () => {
		mock.inject('ubus', { data: { 'a:b': { val: 1 } } }, (outer) => {
			let conn = outer.connect();
			assert.eq(conn.call('a', 'b', {}).val, 1);

			mock.inject('ubus', { data: { 'c:d': { val: 2 } } }, (inner) => {
				let conn2 = inner.connect();
				assert.eq(conn2.call('a', 'b', {}).val, 1);
				assert.eq(conn2.call('c', 'd', {}).val, 2);
			});

			assert.eq(conn.call('c', 'd', {}), null);
		});
	});

	it('strict mode dies on unmocked calls', () => {
		assert.throws(() => {
			mock.inject('ubus', { strict: true, data: {} }, (m_ubus) => {
				m_ubus.connect().call('unmocked', 'method', {});
			});
		}, /strict mock/);
	});

	it('patches global state via mock.global.patch()', () => {
		const m_ubus = mock.global.patch('ubus', {
			data: { 'system:board': { hostname: 'patched' } }
		});

		assert.eq(m_ubus.connect().call('system', 'board', {}).hostname, 'patched');
		assert.eq(ubus.connect().call('system', 'board', {}).hostname, 'patched', 'shim transparently intercepts');
		mock.global.unpatch('ubus');

		assert.eq(m_ubus.connect().call('system', 'board', {}), null);
	});
});
