import { describe, it, afterEach, assert, mock, spy } from 'utest';
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

	it('spy(proxy) sees the fresh calls dict after restore()', () => {
		const m_fs = mock.global.patch('fs', { data: { '/pre': 'x', '/post': 'y' } });
		m_fs.readfile('/pre');
		const snap = mock.snapshot();
		m_fs.readfile('/between');
		mock.restore(snap);
		// spy() does a live lookup into the registry, so after restore() swaps in a
		// fresh reg.global.calls, pre- and between-calls are gone automatically.
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

	describe('pre_body_snap is always restored before afterEach runs', () => {
		afterEach(() => {
			// If pre_body_snap was not restored, the patch from the test body would
			// still be active here and readfile would return 'leaked' instead of null.
			assert.match(null, fs.readfile('/tmp/leaked.txt'),
				'test body patch must not be visible in afterEach');
		});

		it('patch without unpatch does not leak into afterEach', () => {
			// Intentionally patch without unpatching — pre_body_snap should restore.
			mock.global.patch('fs', { data: { '/tmp/leaked.txt': 'leaked' } });
		});
	});
});

describe('mock.global.patch input validation', () => {
	it('rejects a null state with a clear message (like mock.inject)', () => {
		assert.throws(() => mock.global.patch('fs', null), /must be a non-null object/);
	});
});

describe('mock state rejects unknown keys (typo protection)', () => {
	it('inject() rejects a misspelled key, naming the valid keys for the module', () => {
		assert.throws(() => mock.inject('fs', { behaviour: {} }, () => {}),
		              /unknown key 'behaviour'.*allowed keys: behavior, strict, data, commands/);
	});

	it("inject() accepts a proxy's declared channel (fs 'commands')", () => {
		mock.inject('fs', { commands: { 'echo hi': 'hi\n' } }, (m_fs) => {
			assert.match('hi\n', m_fs.popen('echo hi').read('all'));
		});
	});

	it("rejects a channel that belongs to a different proxy (uci has no 'commands')", () => {
		assert.throws(() => mock.inject('uci', { commands: {} }, () => {}),
		              /unknown key 'commands'/);
	});

	it('global.patch() rejects a misspelled key too', () => {
		assert.throws(() => mock.global.patch('fs', { files: {} }), /unknown key 'files'/);
	});
});

describe('deep_clone handles cyclic and shared mock data', () => {
	it('cyclic data dies cleanly instead of stack-overflowing', () => {
		let cyclic = { a: 1 };
		cyclic.self = cyclic;
		assert.throws(() => mock.inject('fs', { data: { '/x': cyclic } }, () => {}),
		              /cyclic data structure/);
	});

	it('a shared (non-cyclic) subtree is cloned, not rejected as a cycle', () => {
		let shared = { v: 1 };
		// The same object in two sibling positions is a DAG, not a cycle.
		mock.inject('uci', { data: { pkg: { a: shared, b: shared } } }, (m) => {
			assert.match(1, m.cursor().get('pkg', 'a', 'v'));
			assert.match(1, m.cursor().get('pkg', 'b', 'v'));
		});
	});
});
