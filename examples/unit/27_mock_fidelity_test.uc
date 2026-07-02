import { describe, it, assert, mock, truthy, falsy } from 'utest';
import * as uci from 'uci';
import * as uclient from 'uclient';
import * as ubus from 'ubus';

// Regressions covering places where the mock proxies diverged from the real
// OpenWrt bindings.

const uci_data = {
	network: {
		lan:  { '.type': 'interface', proto: 'static' },
		wan:  { '.type': 'interface', proto: 'dhcp' },
		main: { '.type': 'route',     target: '0.0.0.0' }
	}
};

describe('uci mock fidelity', () => {
	it('foreach() with a null type visits every section (like real uci)', () => {
		mock.inject('uci', { data: uci_data }, (m) => {
			let seen = [];
			let ret = m.cursor().foreach('network', null, (s) => push(seen, s['.name']));
			assert.match(['lan', 'wan', 'main'], seen);
			assert.match(truthy(), ret);
		});
	});

	it('foreach() still filters by type when one is given', () => {
		mock.inject('uci', { data: uci_data }, (m) => {
			let seen = [];
			m.cursor().foreach('network', 'interface', (s) => push(seen, s['.name']));
			assert.match(['lan', 'wan'], seen);
		});
	});

	it('2-arg get(pkg, sec) returns the section type (like real uci)', () => {
		mock.inject('uci', { data: uci_data }, (m) => {
			assert.match('interface', m.cursor().get('network', 'lan'));
			assert.match('static',    m.cursor().get('network', 'lan', 'proto'));
		});
	});
});

describe('uclient mock fidelity', () => {
	it('a URL mocked to null returns false instead of tripping strict mode', () => {
		const url = 'http://unreachable.example/';
		mock.inject('uclient', { strict: true, data: { [url]: null } }, (m) => {
			let u = m.new(url, null, {});
			assert.match(falsy(), u.request('GET', {}));
		});
	});
});

describe('ubus mock fidelity', () => {
	// A ubus method can legitimately reply with null; the proxy uses has_data so an
	// explicit-null mock is a real reply, not "unmocked". These lock that in — the
	// exact divergence the proxy comment (ubus.uc:19-22) guards against — alongside
	// the object:method-over-object precedence the real key format implies.
	it('a method mocked to null returns null instead of tripping strict mode', () => {
		mock.inject('ubus', { strict: true, data: { 'service:list': null } }, (m) => {
			assert.match(null, m.connect().call('service', 'list', {}));
		});
	});

	it('an explicit-null method mock overrides a present object-level mock', () => {
		mock.inject('ubus', {
			data: { network: { up: true }, 'network:status': null }
		}, (m) => {
			let conn = m.connect();
			// The null method reply wins over the object fallback for that method...
			assert.match(null, conn.call('network', 'status', {}));
			// ...but other methods still fall back to the object-level mock.
			assert.match(truthy(), conn.call('network', 'get', {}).up);
		});
	});

	it('a method-level mock takes precedence over an object-level mock', () => {
		mock.inject('ubus', {
			data: { system: { src: 'object' }, 'system:board': { src: 'method' } }
		}, (m) => {
			let conn = m.connect();
			assert.match('method', conn.call('system', 'board', {}).src);
			assert.match('object', conn.call('system', 'info', {}).src);
		});
	});
});
