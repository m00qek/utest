import { describe, it, assert, mock, truthy, falsy } from 'utest';
import * as uci from 'uci';
import * as uclient from 'uclient';

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
