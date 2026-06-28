import { describe, it, assert, mock, spy } from 'utest';
import * as fs from 'fs';

// Covers the mock state API: inject(), global.patch/unpatch, snapshot/restore, reset().

describe('Mock State', () => {
	it('mock.inject() scopes data to the callback; the imported module is unaffected', () => {
		mock.inject('fs', { data: { '/tmp/a.txt': 'scoped' } }, (m_fs) => {
			assert.match('scoped', m_fs.readfile('/tmp/a.txt'));
			assert.match(null, fs.readfile('/tmp/a.txt'), 'shim passes through when no global patch');
		});
		assert.match(null, fs.readfile('/tmp/a.txt'), 'layer cleaned up after callback');
	});

	it('mock.global.patch() intercepts the imported module via the shim', () => {
		const m_fs = mock.global.patch('fs', { data: { '/tmp/b.txt': 'patched' } });
		assert.match('patched', m_fs.readfile('/tmp/b.txt'));
		assert.match('patched', fs.readfile('/tmp/b.txt'), 'shim transparently intercepts');
		mock.global.unpatch('fs');
		assert.match(null, fs.readfile('/tmp/b.txt'));
	});

	it('inject() layer is visible on top of a global patch', () => {
		mock.global.patch('fs', { data: { '/tmp/base.txt': 'base' } });
		mock.inject('fs', { data: { '/tmp/local.txt': 'local' } }, (m_fs) => {
			assert.match('base', m_fs.readfile('/tmp/base.txt'), 'global data visible inside inject');
			assert.match('local', m_fs.readfile('/tmp/local.txt'), 'inject layer on top');
		});
		assert.match(null, fs.readfile('/tmp/local.txt'), 'inject layer gone');
		mock.global.unpatch('fs');
	});

	it('mock.snapshot() and mock.restore() save and recover global state', () => {
		const snap = mock.snapshot();
		mock.global.patch('fs', { data: { '/tmp/snap.txt': 'hello' } });
		assert.match('hello', fs.readfile('/tmp/snap.txt'));
		mock.restore(snap);
		assert.match(null, fs.readfile('/tmp/snap.txt'), 'state restored to pre-patch');
	});

	it('restore() repoints spy(proxy).calls to the fresh dict so call tracking stays consistent', () => {
		const m_fs = mock.global.patch('fs', { data: { '/pre': 'x', '/post': 'y' } });
		m_fs.readfile('/pre');
		const snap = mock.snapshot();
		m_fs.readfile('/between');
		mock.restore(snap);
		// After restore(), the calls dict is fresh: pre- and between-calls are gone.
		assert.match(null, spy(m_fs).calls.readfile, 'calls dict reset after restore');
		m_fs.readfile('/post');
		assert.match([ ['/post'] ], spy(m_fs).calls.readfile, 'only post-restore calls visible');
		mock.global.unpatch('fs');
	});

	it('mock.reset() discards all active inject() layers', () => {
		mock.inject('fs', { data: { '/tmp/r.txt': 'layer' } }, (m_fs) => {
			assert.match('layer', m_fs.readfile('/tmp/r.txt'));
			mock.reset();
			assert.match(null, m_fs.readfile('/tmp/r.txt'), 'layer cleared by reset');
		});
	});
});
