import { describe, it, assert, mock, truthy, falsy } from 'utest';
import * as uci from 'uci';

// Data keys are package names; values are UCI section maps: { section: { '.type': '...', option: value } }.

const uci_data = {
	'luci-sso': {
		'default': {
			'.type': 'oidc',
			'enabled': '1',
			'issuer_url': 'https://idp.example.com',
			'client_id': 'my-client'
		},
		'admin_role': {
			'.type': 'role',
			'email': ['admin@example.com'],
			'read': ['*'],
			'write': ['*']
		},
		'viewer_role': {
			'.type': 'role',
			'email': ['viewer@example.com'],
			'read': ['luci-mod-status'],
			'write': []
		}
	}
};

describe('uci Mocking', () => {
	it('get() reads a single option', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			let c = m_uci.cursor();
			assert.match('1', c.get('luci-sso', 'default', 'enabled'));
			assert.match('https://idp.example.com', c.get('luci-sso', 'default', 'issuer_url'));
			assert.match(null, c.get('luci-sso', 'default', 'missing_opt'));
		});
	});

	it('get() returns null for missing package or section', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			let c = m_uci.cursor();
			assert.match(null, c.get('no-pkg', 'sec', 'opt'));
			assert.match(null, c.get('luci-sso', 'no-sec', 'opt'));
		});
	});

	it('get_all() returns the full section object including .name', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			let c = m_uci.cursor();
			let sec = c.get_all('luci-sso', 'default');
			assert.match('default', sec['.name']);
			assert.match('oidc', sec['.type']);
			assert.match('my-client', sec.client_id);
			assert.match(null, c.get_all('luci-sso', 'no-sec'));
		});
	});

	it('foreach() iterates sections matching a type in insertion order', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			let names = [];
			m_uci.cursor().foreach('luci-sso', 'role', (s) => push(names, s['.name']));
			assert.match(['admin_role', 'viewer_role'], names);
		});
	});

	it('foreach() injects .name and exposes all options', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			let first = null;
			m_uci.cursor().foreach('luci-sso', 'role', (s) => { if (!first) first = s; });
			assert.match('admin_role', first['.name']);
			assert.match('admin@example.com', first.email[0]);
			assert.match('*', first.read[0]);
		});
	});

	it('load() is a no-op returning true', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			assert.match(truthy(), m_uci.cursor().load('luci-sso'));
		});
	});

	it('load() is recorded in cursor call history', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			let c = m_uci.cursor();
			c.load('luci-sso');
			assert.match([['luci-sso']], c.__utest__.calls.load);
		});
	});

	it('set() writes and is immediately readable via get()', () => {
		mock.inject('uci', { data: {
			'luci-sso': { 'default': { '.type': 'oidc', 'enabled': '0' } }
		}}, (m_uci) => {
			let c = m_uci.cursor();
			assert.match('0', c.get('luci-sso', 'default', 'enabled'));
			c.set('luci-sso', 'default', 'enabled', '1');
			assert.match('1', c.get('luci-sso', 'default', 'enabled'));
		});
	});

	it('commit() is a no-op returning true', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			assert.match(truthy(), m_uci.cursor().commit('luci-sso'));
		});
	});

	it('delete() removes a single option', () => {
		mock.inject('uci', { data: {
			'luci-sso': { 'default': { '.type': 'oidc', 'enabled': '1', 'scope': 'openid' } }
		}}, (m_uci) => {
			let c = m_uci.cursor();
			assert.match(truthy(), c.delete('luci-sso', 'default', 'scope'));
			assert.match(null, c.get('luci-sso', 'default', 'scope'));
			assert.match('1', c.get('luci-sso', 'default', 'enabled'));
		});
	});

	it('delete() removes an entire section', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			let c = m_uci.cursor();
			assert.match(truthy(), c.delete('luci-sso', 'viewer_role'));
			let names = [];
			c.foreach('luci-sso', 'role', (s) => push(names, s['.name']));
			assert.match(['admin_role'], names);
		});
	});

	it('strict mode dies on unmocked package access', () => {
		assert.throws(() => {
			mock.inject('uci', { strict: true, data: {} }, (m_uci) => {
				m_uci.cursor().get('no-pkg', 'sec', 'opt');
			});
		}, /strict mock/);
	});

	it('patches global state via mock.global.patch()', () => {
		const m_uci = mock.global.patch('uci', {
			data: { 'luci-sso': { 'default': { '.type': 'oidc', 'enabled': '1' } } }
		});
		assert.match('1', uci.cursor().get('luci-sso', 'default', 'enabled'));
		mock.global.unpatch('uci');
		assert.match(null, m_uci.cursor().get('luci-sso', 'default', 'enabled'));
	});
});

describe('uci strict mode blocks every accessor on an unmocked package', () => {
	// Strict mode's contract: any access to an unmocked package dies, so a
	// typo'd package name is caught. get()/foreach() already enforced it;
	// get_all(), delete(), and load() must too (regression for those holes).
	const cfg = { strict: true, data: uci_data };

	it('get_all() dies for an unmocked package but still serves the mocked one', () => {
		mock.inject('uci', cfg, (m) => {
			assert.throws(() => m.cursor().get_all('typo-pkg', 'default'),
			              /strict mock: uci package 'typo-pkg'/);
			assert.match('oidc', m.cursor().get_all('luci-sso', 'default')['.type']);
		});
	});

	it('delete() dies for an unmocked package', () => {
		mock.inject('uci', cfg, (m) => {
			assert.throws(() => m.cursor().delete('typo-pkg', 'default'),
			              /strict mock: uci package 'typo-pkg'/);
		});
	});

	it('load() returns false for an unmocked package (like real uci), true for the mocked one', () => {
		mock.inject('uci', cfg, (m) => {
			assert.match(falsy(),  m.cursor().load('typo-pkg'));
			assert.match(truthy(), m.cursor().load('luci-sso'));
		});
	});
});

describe('uci reads return fresh copies (no live references into the store)', () => {
	// A list-typed option returned by reference would let SUT push()/mutation
	// corrupt the layer's store; real uci returns a fresh value each read.
	it('mutating a list returned by get() does not corrupt the store', () => {
		mock.inject('uci', { data: uci_data }, (m) => {
			push(m.cursor().get('luci-sso', 'admin_role', 'read'), 'injected');
			assert.match(['*'], m.cursor().get('luci-sso', 'admin_role', 'read'));
		});
	});

	it('mutating a list inside a get_all() result does not corrupt the store', () => {
		mock.inject('uci', { data: uci_data }, (m) => {
			push(m.cursor().get_all('luci-sso', 'admin_role').read, 'injected');
			assert.match(['*'], m.cursor().get_all('luci-sso', 'admin_role').read);
		});
	});

	it('mutating a section handed to foreach() does not corrupt the store', () => {
		mock.inject('uci', { data: uci_data }, (m) => {
			m.cursor().foreach('luci-sso', 'role', (s) => push(s.read, 'injected'));
			let seen = null;
			m.cursor().foreach('luci-sso', 'role', (s) => { if (s['.name'] === 'admin_role') seen = s.read; });
			assert.match(['*'], seen);
		});
	});
});
