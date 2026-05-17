import { describe, it, mock } from 'utest';
import { assert } from 'utest.assert';
import * as uci from 'uci';

/**
 * uci Mocking Example
 *
 * Data keys are package names; values are section maps using the standard
 * UCI structure: { section_name: { '.type': '...', option: value } }.
 * Declare the module in config.mocks (see 12_uci_config.uc) so the
 * framework generates the shim.
 */

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
			assert.eq(c.get('luci-sso', 'default', 'enabled'), '1');
			assert.eq(c.get('luci-sso', 'default', 'issuer_url'), 'https://idp.example.com');
			assert.eq(c.get('luci-sso', 'default', 'missing_opt'), null);
		});
	});

	it('get() returns null for missing package or section', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			let c = m_uci.cursor();
			assert.eq(c.get('no-pkg', 'sec', 'opt'), null);
			assert.eq(c.get('luci-sso', 'no-sec', 'opt'), null);
		});
	});

	it('get_all() returns the full section object', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			let c = m_uci.cursor();
			let sec = c.get_all('luci-sso', 'default');
			assert.eq(sec['.type'], 'oidc');
			assert.eq(sec.client_id, 'my-client');
			assert.eq(c.get_all('luci-sso', 'no-sec'), null);
		});
	});

	it('foreach() iterates sections matching a type in insertion order', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			let names = [];
			m_uci.cursor().foreach('luci-sso', 'role', (s) => push(names, s['.name']));
			assert.eq(names, ['admin_role', 'viewer_role']);
		});
	});

	it('foreach() injects .name and exposes all options', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			let first = null;
			m_uci.cursor().foreach('luci-sso', 'role', (s) => { if (!first) first = s; });
			assert.eq(first['.name'], 'admin_role');
			assert.eq(first.email[0], 'admin@example.com');
			assert.eq(first.read[0], '*');
		});
	});

	it('set() writes and is immediately readable via get()', () => {
		mock.inject('uci', { data: {
			'luci-sso': { 'default': { '.type': 'oidc', 'enabled': '0' } }
		}}, (m_uci) => {
			let c = m_uci.cursor();
			assert.eq(c.get('luci-sso', 'default', 'enabled'), '0');
			c.set('luci-sso', 'default', 'enabled', '1');
			assert.eq(c.get('luci-sso', 'default', 'enabled'), '1');
		});
	});

	it('commit() is a no-op returning true', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			assert.ok(m_uci.cursor().commit('luci-sso'));
		});
	});

	it('delete() removes a single option', () => {
		mock.inject('uci', { data: {
			'luci-sso': { 'default': { '.type': 'oidc', 'enabled': '1', 'scope': 'openid' } }
		}}, (m_uci) => {
			let c = m_uci.cursor();
			assert.ok(c.delete('luci-sso', 'default', 'scope'));
			assert.eq(c.get('luci-sso', 'default', 'scope'), null);
			assert.eq(c.get('luci-sso', 'default', 'enabled'), '1');
		});
	});

	it('delete() removes an entire section', () => {
		mock.inject('uci', { data: uci_data }, (m_uci) => {
			let c = m_uci.cursor();
			assert.ok(c.delete('luci-sso', 'viewer_role'));
			let names = [];
			c.foreach('luci-sso', 'role', (s) => push(names, s['.name']));
			assert.eq(names, ['admin_role']);
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
		assert.eq(uci.cursor().get('luci-sso', 'default', 'enabled'), '1');
		mock.global.unpatch('uci');
		assert.eq(m_uci.cursor().get('luci-sso', 'default', 'enabled'), null);
	});
});
