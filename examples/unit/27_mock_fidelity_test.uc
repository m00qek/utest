import { describe, it, assert, mock, truthy, falsy } from 'utest';
import * as uci from 'uci';
import * as uclient from 'uclient';
import * as ubus from 'ubus';
import * as fs from 'fs';

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

describe('fs mock read-side fidelity', () => {
	// The read-only family (lstat/readlink/realpath/opendir) used to fall through
	// to the REAL filesystem during an active mock, so a mocked path stat()'d as a
	// regular file but lstat()'d as null. These lock the family to the same view
	// the rest of the fs proxy presents.
	const tree = { data: { '/tmp/d/a.txt': 'hello', '/tmp/d/sub/b.txt': 'x' } };

	it('stat().type uses the real fs vocabulary (file/directory, not regular)', () => {
		mock.inject('fs', tree, (m) => {
			assert.match('file', m.stat('/tmp/d/a.txt').type);
			assert.match('directory', m.stat('/tmp/d').type);
		});
	});

	it('lstat mirrors stat for a mocked file and directory', () => {
		mock.inject('fs', tree, (m) => {
			let l = m.lstat('/tmp/d/a.txt');
			assert.match('file', l.type);
			assert.match(5, l.size);
			assert.match('directory', m.lstat('/tmp/d').type);
			assert.match(null, m.lstat('/tmp/d/missing.txt'));
		});
	});

	it('readlink reports a known path as a non-symlink (null)', () => {
		mock.inject('fs', tree, (m) => {
			assert.match(null, m.readlink('/tmp/d/a.txt'));
			assert.match(null, m.readlink('/tmp/d'));
		});
	});

	it('realpath canonicalizes . and .. and confirms existence', () => {
		mock.inject('fs', tree, (m) => {
			assert.match('/tmp/d/a.txt', m.realpath('/tmp/d/./a.txt'));
			assert.match('/tmp/d/a.txt', m.realpath('/tmp/d/sub/../a.txt'));
			assert.match('/tmp/d', m.realpath('/tmp/d'));
		});
	});

	it('opendir cursors the merged listing and rewinds with seek', () => {
		mock.inject('fs', tree, (m) => {
			let dh = m.opendir('/tmp/d');
			let first = [];
			let e;
			while ((e = dh.read()) !== null) push(first, e);
			assert.match(truthy(), length(first) >= 2);   // a.txt + sub
			dh.seek(0);
			assert.match(first[0], dh.read());
			dh.close();
			// A file is not a directory: opendir returns null, like the real fs.
			assert.match(null, m.opendir('/tmp/d/a.txt'));
		});
	});

	it('strict mode dies on an unmocked read-side op, like stat/readfile', () => {
		mock.inject('fs', { strict: true, data: { '/tmp/d/a.txt': 'x' } }, (m) => {
			assert.throws(() => m.lstat('/tmp/nope'), /unmocked path/);
			assert.throws(() => m.readlink('/tmp/nope'), /unmocked path/);
			assert.throws(() => m.realpath('/tmp/nope'), /unmocked path/);
			assert.match('file', m.lstat('/tmp/d/a.txt').type);
		});
	});
});
