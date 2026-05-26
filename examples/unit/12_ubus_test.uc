import { describe, it, assert, mock, truthy, falsy } from 'utest';
import * as ubus from 'ubus';

// Data keys use the 'object:method' format; a bare 'object' key is a fallback for any method.

describe('ubus Mocking', () => {
	it('returns mocked data for object:method key', () => {
		mock.inject('ubus', {
			data: { 'system:board': { model: 'Test Router', hostname: 'OpenWrt' } }
		}, (m_ubus) => {
			let conn = m_ubus.connect();
			assert.match({ model: 'Test Router', hostname: 'OpenWrt' }, conn.call('system', 'board', {}));
		});
	});

	it('falls back to object key for any method', () => {
		mock.inject('ubus', {
			data: { 'network': { up: true } }
		}, (m_ubus) => {
			let conn = m_ubus.connect();
			assert.match(truthy(), conn.call('network', 'status', {}).up);
			assert.match(truthy(), conn.call('network', 'get_status', {}).up);
		});
	});

	it('returns null for unmocked calls in non-strict mode', () => {
		mock.inject('ubus', { data: {} }, (m_ubus) => {
			assert.match(null, m_ubus.connect().call('unmocked', 'method', {}));
		});
	});

	it('supports function values for dynamic responses', () => {
		mock.inject('ubus', {
			data: { 'network:status': (args) => ({ up: args.interface == 'wan' }) }
		}, (m_ubus) => {
			let conn = m_ubus.connect();
			assert.match(truthy(), conn.call('network', 'status', { interface: 'wan' }).up);
			assert.match(falsy(), conn.call('network', 'status', { interface: 'lan' }).up);
		});
	});

	it('supports behavior override for call', () => {
		mock.inject('ubus', {
			behavior: { call: (obj, method, args) => ({ routed: obj + '.' + method }) }
		}, (m_ubus) => {
			assert.match('system.board', m_ubus.connect().call('system', 'board', {}).routed);
		});
	});

	it('supports nesting mock.inject()', () => {
		mock.inject('ubus', { data: { 'a:b': { val: 1 } } }, (outer) => {
			let conn = outer.connect();
			assert.match(1, conn.call('a', 'b', {}).val);

			mock.inject('ubus', { data: { 'c:d': { val: 2 } } }, (inner) => {
				let conn2 = inner.connect();
				assert.match(1, conn2.call('a', 'b', {}).val);
				assert.match(2, conn2.call('c', 'd', {}).val);
			});

			assert.match(null, conn.call('c', 'd', {}));
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

		assert.match('patched', m_ubus.connect().call('system', 'board', {}).hostname);
		assert.match('patched', ubus.connect().call('system', 'board', {}).hostname, 'shim transparently intercepts');
		mock.global.unpatch('ubus');

		assert.match(null, m_ubus.connect().call('system', 'board', {}));
	});
});
