import { describe, it, mock } from 'utest';
import { assert } from 'utest.assert';
import * as uclient from 'uclient';

/**
 * uclient Mocking Example
 *
 * Data keys are request URLs; values are response descriptors:
 *   { status, headers, body }  — successful response
 *   { error: code }            — network/transport error
 *
 * Callbacks (header_done, data_read, data_eof, error) are fired
 * synchronously inside request(), making async HTTP testable without
 * a real event loop. Declare the module in config.mocks
 * (see 14_uclient_config.uc) so the framework generates the shim.
 */

describe('uclient Mocking', () => {
	it('ssl_init() and connect() return true by default', () => {
		mock.inject('uclient', {}, (m_uclient) => {
			let u = m_uclient.new('http://example.com/', null, {});
			assert.ok(u.ssl_init({ verify: true }));
			assert.ok(u.connect());
		});
	});

	it('request() fires header_done, data_read, data_eof in order', () => {
		const url = 'http://api.example.com/items';
		mock.inject('uclient', {
			data: { [url]: { status: 200, headers: { 'content-type': 'application/json' }, body: '[]' } }
		}, (m_uclient) => {
			let events = [];
			let u = m_uclient.new(url, null, {
				header_done: () => push(events, 'header_done'),
				data_read:   () => push(events, 'data_read'),
				data_eof:    () => push(events, 'data_eof')
			});
			u.request('GET', {});
			assert.eq(events, ['header_done', 'data_read', 'data_eof']);
		});
	});

	it('status() and get_headers() are readable inside callbacks', () => {
		const url = 'http://api.example.com/status';
		mock.inject('uclient', {
			data: { [url]: { status: 201, headers: { 'x-custom': 'yes' }, body: '' } }
		}, (m_uclient) => {
			let got_status = null;
			let got_headers = null;
			let u = m_uclient.new(url, null, {
				header_done: (conn) => {
					got_status = conn.status().status;
					got_headers = conn.get_headers();
				},
				data_read: () => {},
				data_eof:  () => {}
			});
			u.request('GET', {});
			assert.eq(got_status, 201);
			assert.eq(got_headers['x-custom'], 'yes');
		});
	});

	it('read() returns body on first call, null on subsequent calls', () => {
		const url = 'http://api.example.com/body';
		mock.inject('uclient', {
			data: { [url]: { status: 200, headers: {}, body: 'hello world' } }
		}, (m_uclient) => {
			let chunks = [];
			let u = m_uclient.new(url, null, {
				data_read: (conn) => {
					let chunk;
					while ((chunk = conn.read()) != null) push(chunks, chunk);
				},
				header_done: () => {},
				data_eof:    () => {}
			});
			u.request('GET', {});
			assert.eq(chunks, ['hello world']);
		});
	});

	it('request() fires error callback for error responses', () => {
		const url = 'http://api.example.com/broken';
		mock.inject('uclient', {
			data: { [url]: { error: 'connection_refused' } }
		}, (m_uclient) => {
			let got_error = null;
			let u = m_uclient.new(url, null, {
				error: (conn, code) => { got_error = code; }
			});
			u.request('GET', {});
			assert.eq(got_error, 'connection_refused');
		});
	});

	it('request() returns false and skips callbacks for unmocked URLs', () => {
		mock.inject('uclient', { data: {} }, (m_uclient) => {
			let called = false;
			let u = m_uclient.new('http://example.com/missing', null, {
				header_done: () => { called = true; }
			});
			let ok = u.request('GET', {});
			assert.eq(ok, false);
			assert.notOk(called);
		});
	});

	it('strict mode dies on unmocked URL', () => {
		assert.throws(() => {
			mock.inject('uclient', { strict: true, data: {} }, (m_uclient) => {
				let u = m_uclient.new('http://example.com/x', null, {});
				u.request('GET', {});
			});
		}, /strict mock/);
	});

	it('supports behavior override for connect() to simulate failure', () => {
		mock.inject('uclient', {
			behavior: { connect: () => false }
		}, (m_uclient) => {
			let u = m_uclient.new('http://example.com/', null, {});
			assert.eq(u.connect(), false);
		});
	});

	it('supports behavior override for new()', () => {
		let constructed_url = null;
		mock.inject('uclient', {
			behavior: { new: (url) => { constructed_url = url; return {}; } }
		}, (m_uclient) => {
			m_uclient.new('http://custom.example.com/', null, {});
			assert.eq(constructed_url, 'http://custom.example.com/');
		});
	});

	it('does not fire data_read for responses with no body', () => {
		const url = 'http://api.example.com/no-content';
		mock.inject('uclient', {
			data: { [url]: { status: 204, headers: {}, body: null } }
		}, (m_uclient) => {
			let data_read_fired = false;
			let u = m_uclient.new(url, null, {
				header_done: () => {},
				data_read:   () => { data_read_fired = true; },
				data_eof:    () => {}
			});
			u.request('GET', {});
			assert.notOk(data_read_fired);
		});
	});

	it('patches global state via mock.global.patch()', () => {
		const url = 'http://api.example.com/global';
		const m_uclient = mock.global.patch('uclient', {
			data: { [url]: { status: 200, headers: {}, body: 'patched' } }
		});
		let body = null;
		let u = uclient.new(url, null, {
			data_read: (conn) => { body = conn.read(); },
			header_done: () => {},
			data_eof: () => {}
		});
		u.request('GET', {});
		assert.eq(body, 'patched', 'shim transparently intercepts global state');
		mock.global.unpatch('uclient');
	});
});
