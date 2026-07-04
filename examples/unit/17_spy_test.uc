import { describe, it, assert, mock, spy, contains, any, equals } from 'utest';
import * as fs from 'fs';

describe('spy()', () => {

	describe('on a specific proxy (fs)', () => {
		it('starts with empty arrays for all proxy methods', () => {
			mock.inject('fs', { data: { '/a': 'x' } }, (m_fs) => {
				assert.match(contains({
					readfile: [],
					writefile: [],
					access: [],
					stat: []
				}), spy(m_fs).calls);
			});
		});

		it('records args in order for each call', () => {
			mock.inject('fs', { data: { '/a': 'x', '/b': 'y' } }, (m_fs) => {
				m_fs.readfile('/a');
				m_fs.readfile('/b');
				assert.match([ ['/a'], ['/b'] ], spy(m_fs).calls.readfile);
			});
		});

		it('records multiple different methods independently', () => {
			mock.inject('fs', { data: {} }, (m_fs) => {
				m_fs.writefile('/out', 'hello');
				m_fs.access('/out', 'r');
				m_fs.stat('/out');
				assert.match(contains({
					writefile: [ ['/out', 'hello'] ],
					access:    [ ['/out', 'r'] ],
					stat:      [ ['/out'] ]
				}), spy(m_fs).calls);
			});
		});

		it('records call even when behavior is overridden', () => {
			mock.inject('fs', { behavior: { readfile: (p) => 'override' } }, (m_fs) => {
				m_fs.readfile('/any');
				assert.match([ ['/any'] ], spy(m_fs).calls.readfile);
			});
		});

		it('resets call records between inject() scopes', () => {
			mock.inject('fs', { data: { '/a': 'x' } }, (m_fs) => {
				m_fs.readfile('/a');
				assert.match([ ['/a'] ], spy(m_fs).calls.readfile);
			});
			mock.inject('fs', { data: { '/a': 'x' } }, (m_fs) => {
				assert.match([], spy(m_fs).calls.readfile);
			});
		});

		it('records calls via mock.global.patch()', () => {
			const m_fs = mock.global.patch('fs', { data: { '/g': 'global' } });
			fs.readfile('/g');
			assert.match([ ['/g'] ], spy(m_fs).calls.readfile);
			mock.global.unpatch('fs');
		});

		it('spy() on a proxy leaked out of its scope dies rather than misreport', () => {
			// spy() does a live registry lookup, so a proxy captured out of inject()
			// would otherwise report the current (empty global) scope's calls. Both an
			// inject proxy after its callback and a patch proxy after unpatch must die.
			let leaked;
			mock.inject('fs', { data: {} }, (m_fs) => { leaked = m_fs; m_fs.readfile('/x'); });
			assert.throws(() => spy(leaked), /used outside its scope/);

			const m_fs = mock.global.patch('fs', {});
			mock.global.unpatch('fs');
			assert.throws(() => spy(m_fs), /used outside its scope/);
		});

		it('resets call records on successive global patches', () => {
			mock.global.patch('fs', { data: { '/a': 'x' } });
			fs.readfile('/a');
			const m_fs2 = mock.global.patch('fs', { data: { '/b': 'y' } });
			assert.match([], spy(m_fs2).calls.readfile);
			mock.global.unpatch('fs');
		});

		it('spy() on a global-patch proxy reflects the active layer during inject()', () => {
			// m_fs is the global-patch proxy; its calls are tracked in reg.global.calls.
			// When mock.inject() pushes a layer, record_call() writes to that layer's
			// calls dict instead.  spy(m_fs) must do a live lookup so it returns the
			// inject layer's dict while inside the callback — not the stale global dict.
			const m_fs = mock.global.patch('fs', { data: { '/pre': 'a', '/in': 'b', '/post': 'c' } });
			m_fs.readfile('/pre');

			mock.inject('fs', {}, () => {
				m_fs.readfile('/in');
				assert.match([ ['/in'] ], spy(m_fs).calls.readfile,
					'spy must see inject-layer calls during inject');
			});

			m_fs.readfile('/post');
			assert.match([ ['/pre'], ['/post'] ], spy(m_fs).calls.readfile,
				'spy must see global-layer calls after inject');
			mock.global.unpatch('fs');
		});
	});

	describe('on an auto-generated proxy (math)', () => {
		it('records calls via the generic ctx.base() path', () => {
			mock.inject('math', {}, (m_math) => {
				m_math.abs(-5);
				m_math.abs(-3);
				assert.match([ [-5], [-3] ], spy(m_math).calls.abs);
			});
		});

		it('records call even when behavior is overridden', () => {
			mock.inject('math', { behavior: { abs: (n) => 99 } }, (m_math) => {
				m_math.abs(-1);
				assert.match([ [-1] ], spy(m_math).calls.abs);
			});
		});
	});

	describe('on ubus — proxy and inner connection object', () => {
		it('records connect() on the proxy', () => {
			mock.inject('ubus', { data: {} }, (m_ubus) => {
				m_ubus.connect();
				m_ubus.connect();
				assert.match([ [], [] ], spy(m_ubus).calls.connect);
			});
		});

		it('records call() on the connection object', () => {
			mock.inject('ubus', { data: { 'sys:info': { ok: true } } }, (m_ubus) => {
				let conn = m_ubus.connect();
				conn.call('sys', 'info', {});
				conn.call('sys', 'info', { extra: 1 });
				assert.match([
					['sys', 'info', {}],
					['sys', 'info', { extra: 1 }]
				], spy(conn).calls.call);
			});
		});

		it('records call() even when behavior is overridden', () => {
			mock.inject('ubus', { behavior: { call: () => null } }, (m_ubus) => {
				let conn = m_ubus.connect();
				conn.call('any', 'method', { x: 1 });
				assert.match([ ['any', 'method', { x: 1 }] ], spy(conn).calls.call);
			});
		});

		it('each connect() call returns an independent call log', () => {
			mock.inject('ubus', { data: { 'a:b': 1 } }, (m_ubus) => {
				let conn1 = m_ubus.connect();
				let conn2 = m_ubus.connect();
				conn1.call('a', 'b', {});
				assert.match([ ['a', 'b', {}] ], spy(conn1).calls.call);
				assert.match([], spy(conn2).calls.call);
			});
		});
	});

	describe('on uci — proxy and inner cursor object', () => {
		it('records cursor() on the proxy', () => {
			mock.inject('uci', { data: {} }, (m_uci) => {
				m_uci.cursor();
				assert.match([ [] ], spy(m_uci).calls.cursor);
			});
		});

		it('starts with empty arrays for all cursor methods', () => {
			mock.inject('uci', { data: {} }, (m_uci) => {
				let cursor = m_uci.cursor();
				assert.match(contains({
					get: [], get_all: [], foreach: [],
					set: [], commit: [], save: [], "delete": []
				}), spy(cursor).calls);
			});
		});

		it('records get(), set(), commit() on the cursor', () => {
			mock.inject('uci', { data: { network: { wan: { '.type': 'interface', proto: 'dhcp' } } } }, (m_uci) => {
				let cursor = m_uci.cursor();
				cursor.get('network', 'wan', 'proto');
				cursor.set('network', 'wan', 'proto', 'static');
				cursor.commit('network');
				assert.match(contains({
					get:    [ ['network', 'wan', 'proto'] ],
					set:    [ ['network', 'wan', 'proto', 'static'] ],
					commit: [ ['network'] ]
				}), spy(cursor).calls);
			});
		});

		it('each cursor() call returns an independent call log', () => {
			mock.inject('uci', { data: { net: { s: { proto: 'dhcp' } } } }, (m_uci) => {
				let c1 = m_uci.cursor();
				let c2 = m_uci.cursor();
				c1.get('net', 's', 'proto');
				assert.match([ ['net', 's', 'proto'] ], spy(c1).calls.get);
				assert.match([], spy(c2).calls.get);
			});
		});
	});

	describe('on uloop proxy', () => {
		it('records init(), timer(), run(), end()', () => {
			mock.inject('uloop', {}, (m_uloop) => {
				m_uloop.init();
				m_uloop.timer(100, () => {});
				m_uloop.timer(200, () => {});
				m_uloop.run();
				m_uloop.end();
				assert.match(contains({
					init: [ [] ],
					run:  [ [] ],
					end:  [ [] ]
				}), spy(m_uloop).calls);
				assert.match([
					[ 100, any() ],
					[ 200, any() ]
				], spy(m_uloop).calls.timer);
			});
		});
	});

	describe('on uclient — proxy and inner client object', () => {
		it('records new() on the proxy', () => {
			mock.inject('uclient', { data: { 'http://x': { status: 200, body: 'ok' } } }, (m_uclient) => {
				m_uclient.new('http://x', null, {});
				assert.match([ ['http://x', null, any()] ], spy(m_uclient).calls.new);
			});
		});

		it('starts with empty arrays for all client methods', () => {
			mock.inject('uclient', { data: { 'http://x': { status: 200, body: '' } } }, (m_uclient) => {
				let u = m_uclient.new('http://x', null, {});
				assert.match(contains({
					ssl_init: [], set_timeout: [], connect: [],
					request: [], get_headers: [], status: [],
					read: [], disconnect: []
				}), spy(u).calls);
			});
		});

		it('records request(), read(), disconnect() on the client', () => {
			mock.inject('uclient', { data: { 'http://x': { status: 200, body: 'hello' } } }, (m_uclient) => {
				let u = m_uclient.new('http://x', null, {
					header_done: (u) => {},
					data_read:   (u) => {},
					data_eof:    (u) => {}
				});
				u.request('GET', {});
				u.read();
				u.disconnect();
				assert.match(contains({
					request:    [ ['GET', {}] ],
					read:       [ [] ],
					disconnect: [ [] ]
				}), spy(u).calls);
			});
		});
	});

	describe('edge cases', () => {
		it('dies when passed a plain object', () => {
			assert.throws(() => spy({}), /not a spyable object/);
		});

		it('dies when passed null', () => {
			assert.throws(() => spy(null), /not a spyable object/);
		});

		it('dies when passed a combinator', () => {
			assert.throws(() => spy(equals('x')), /not a spyable object/);
		});
	});

});
