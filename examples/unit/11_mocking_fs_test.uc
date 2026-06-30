import { describe, it, assert, mock, truthy, regex } from 'utest';
import * as fs from 'fs';

// Filesystem mock: demonstrates data/behavior injection, strict mode, global.patch, and virtual file operations.

describe('FS Mocking', () => {
	it('real fs is unaffected by default', () => {
		const content = fs.readfile('/etc/banner');
		assert.match(regex(/OpenWrt/), content);
	});

	it('patches global state via mock.global.patch()', () => {
		const m_fs = mock.global.patch('fs', { data: { '/tmp/setup.txt': 'setup' } });
		assert.match('setup', m_fs.readfile('/tmp/setup.txt'));
		assert.match('setup', fs.readfile('/tmp/setup.txt'), 'shim transparently intercepts global state');
		mock.global.unpatch('fs');

		assert.match(null, m_fs.readfile('/tmp/setup.txt'));
	});

	it('injects scoped mock via mock.inject()', () => {
		mock.inject('fs', { data: { '/tmp/scoped': 'data' } }, (m_fs) => {
			assert.match('data', m_fs.readfile('/tmp/scoped'));
			assert.match(null, fs.readfile('/tmp/scoped'), 'real fs is unaffected inside callback');
		});
	});

	it('supports nesting mock.inject()', () => {
		mock.inject('fs', { data: { '/a': '1' } }, (m_fs) => {
			assert.match('1', m_fs.readfile('/a'));

			mock.inject('fs', { data: { '/b': '2' } }, (m_fs2) => {
				assert.match('1', m_fs2.readfile('/a'));
				assert.match('2', m_fs2.readfile('/b'));
			});

			assert.match('1', m_fs.readfile('/a'));
			assert.match(null, m_fs.readfile('/b'), "Mock state should be restored");
		});
	});

	it('allows custom function implementation via mock.inject()', () => {
		let created = [];

		mock.inject('fs', { behavior: { mkdir: (path) => {
			push(created, path);
			return true;
		}}}, (m_fs) => {
			m_fs.mkdir('/tmp/custom_path');
		});
		assert.match(['/tmp/custom_path'], created);
	});

	it('intercepts readfile calls when enabled', () => {
		const m_fs = mock.global.patch('fs', { data: { '/tmp/virtual.txt': 'hello virtual world' } });
		assert.match('hello virtual world', m_fs.readfile('/tmp/virtual.txt'));
		mock.global.unpatch('fs');
	});

	it('lists virtual files in lsdir()', () => {
		const m_fs = mock.global.patch('fs', { data: {
			'/tmp/mockdir/file1.txt': '1',
			'/tmp/mockdir/file2.txt': '2',
			'/tmp/mockdir/subdir/file3.txt': '3'
		}});

		const list = m_fs.lsdir('/tmp/mockdir');
		sort(list);
		assert.match(['file1.txt', 'file2.txt', 'subdir'], list);
		mock.global.unpatch('fs');
	});

	it('merges real and virtual files in lsdir()', () => {
		const m_fs = mock.global.patch('fs', { data: { '/etc/virtual_config': 'v' } });
		const list = m_fs.lsdir('/etc');

		let has_virtual = false;
		let has_real = false;
		for (let name in list) {
			if (name === 'virtual_config') has_virtual = true;
			if (name === 'banner' || name === 'hosts') has_real = true;
		}

		assert.match(truthy(), has_virtual, 'Should find virtual file');
		assert.match(truthy(), has_real, 'Should find real file');
		mock.global.unpatch('fs');
	});

	it('supports globbing virtual files', () => {
		const m_fs = mock.global.patch('fs', { data: {
			'/tmp/glob/a.txt': 'a',
			'/tmp/glob/b.txt': 'b',
			'/tmp/glob/c.log': 'c'
		}});
		const files = m_fs.glob('/tmp/glob/*.txt');
		sort(files);
		assert.match(['/tmp/glob/a.txt', '/tmp/glob/b.txt'], files);
		mock.global.unpatch('fs');
	});

	it('supports writing to pre-registered virtual files', () => {
		const m_fs = mock.global.patch('fs', { data: { '/tmp/writable.txt': 'initial' } });
		m_fs.writefile('/tmp/writable.txt', 'updated');
		assert.match('updated', m_fs.readfile('/tmp/writable.txt'));
		mock.global.unpatch('fs');
	});

	it('supports writing to new virtual paths when mock is active', () => {
		const m_fs = mock.global.patch('fs', { data: { '/tmp/seed.txt': 'seed' } });
		m_fs.writefile('/tmp/new.txt', 'created');
		assert.match('created', m_fs.readfile('/tmp/new.txt'));
		mock.global.unpatch('fs');
	});

	it('access() returns true for virtual files', () => {
		mock.inject('fs', { data: { '/tmp/present.txt': 'yes' } }, (m_fs) => {
			assert.match(truthy(), m_fs.access('/tmp/present.txt'));
			assert.match(null, m_fs.access('/tmp/absent.txt'));
		});
	});

	it('stat() returns size and type for virtual files', () => {
		mock.inject('fs', { data: { '/tmp/data.txt': 'hello' } }, (m_fs) => {
			let s = m_fs.stat('/tmp/data.txt');
			assert.match(5, s.size);
			assert.match('regular', s.type);
			assert.match(null, m_fs.stat('/tmp/missing.txt'));
		});
	});

	it('rename() moves a virtual file', () => {
		mock.inject('fs', { data: { '/tmp/old.txt': 'content' } }, (m_fs) => {
			assert.match(truthy(), m_fs.rename('/tmp/old.txt', '/tmp/new.txt'));
			assert.match('content', m_fs.readfile('/tmp/new.txt'));
			assert.match(null, m_fs.readfile('/tmp/old.txt'));
		});
	});

	it('unlink() removes a virtual file and it disappears from lsdir()', () => {
		mock.inject('fs', { data: {
			'/tmp/dir/keep.txt': 'keep',
			'/tmp/dir/gone.txt': 'gone'
		}}, (m_fs) => {
			assert.match(truthy(), m_fs.unlink('/tmp/dir/gone.txt'));
			assert.match(null, m_fs.readfile('/tmp/dir/gone.txt'));
			const list = m_fs.lsdir('/tmp/dir');
			assert.match(['keep.txt'], list);
		});
	});

	it('mkdir() and chmod() are no-ops returning true', () => {
		mock.inject('fs', {}, (m_fs) => {
			assert.match(truthy(), m_fs.mkdir('/tmp/newdir', 493));
			assert.match(truthy(), m_fs.chmod('/tmp/file.txt', 420));
		});
	});

	it('error() returns null by default', () => {
		mock.inject('fs', {}, (m_fs) => {
			assert.match(null, m_fs.error());
		});
	});

	it('access() returns true for virtual directories', () => {
		mock.inject('fs', { data: { '/tmp/dir/file.txt': 'content' } }, (m_fs) => {
			assert.match(truthy(), m_fs.access('/tmp/dir'), 'parent dir of a virtual file must be accessible');
			assert.match(truthy(), m_fs.access('/tmp'), 'ancestor dir must be accessible');
			assert.match(null, m_fs.access('/tmp/other'), 'unrelated path must return null');
		});
	});

	it('stat() returns directory type for virtual directories', () => {
		mock.inject('fs', { data: { '/tmp/dir/file.txt': 'content' } }, (m_fs) => {
			let s = m_fs.stat('/tmp/dir');
			assert.match('directory', s.type);
			assert.match(0, s.size);
			assert.match(null, m_fs.stat('/tmp/missing'));
		});
	});

	it('glob() supports ? wildcard for single character', () => {
		mock.inject('fs', { data: {
			'/tmp/test_1.uc': 'a',
			'/tmp/test_2.uc': 'b',
			'/tmp/test_10.uc': 'c'
		}}, (m_fs) => {
			const files = m_fs.glob('/tmp/test_?.uc');
			sort(files);
			assert.match(['/tmp/test_1.uc', '/tmp/test_2.uc'], files);
		});
	});

	it('glob() supports ** globstar for recursive paths', () => {
		mock.inject('fs', { data: {
			'/tmp/globstar/a/b/c.txt': 'deep',
			'/tmp/globstar/a/d.txt': 'shallow',
			'/tmp/globstar/e.log': 'wrong-ext'
		}}, (m_fs) => {
			const files = m_fs.glob('/tmp/globstar/**/*.txt');
			sort(files);
			assert.match(['/tmp/globstar/a/b/c.txt', '/tmp/globstar/a/d.txt'], files);
		});
	});

	it('glob() **/ matches zero intermediate path components', () => {
		mock.inject('fs', { strict: true, data: {
			'/cfg/foo.conf': 'top-level',
			'/cfg/sub/bar.conf': 'nested',
			'/cfg/sub/baz.log': 'wrong-ext'
		}}, (m_fs) => {
			const files = m_fs.glob('/cfg/**/*.conf');
			sort(files);
			assert.match(['/cfg/foo.conf', '/cfg/sub/bar.conf'], files,
				'**/ must match zero or more path components');
		});
	});

	it('open() in read mode returns a handle that reads the virtual file', () => {
		mock.inject('fs', { data: { '/tmp/hello.txt': 'line1\nline2\n' } }, (m_fs) => {
			const f = m_fs.open('/tmp/hello.txt', 'r');
			assert.match('line1\n', f.read('line'));
			assert.match('line2\n', f.read('line'));
			assert.match(null,     f.read('line'));
			f.close();
		});
	});

	it('open() in read mode supports read("all")', () => {
		mock.inject('fs', { data: { '/tmp/all.txt': 'hello world' } }, (m_fs) => {
			const f = m_fs.open('/tmp/all.txt', 'r');
			assert.match('hello world', f.read('all'));
			assert.match('',            f.read('all'));
			f.close();
		});
	});

	it('open() in read mode supports read(n) for byte count', () => {
		mock.inject('fs', { data: { '/tmp/bytes.txt': 'abcdef' } }, (m_fs) => {
			const f = m_fs.open('/tmp/bytes.txt', 'r');
			assert.match('ab', f.read(2));
			assert.match('cd', f.read(2));
			assert.match('ef', f.read(2));
			f.close();
		});
	});

	it('open() in read mode returns null for unmocked path', () => {
		mock.inject('fs', { data: {} }, (m_fs) => {
			assert.match(null, m_fs.open('/tmp/missing.txt', 'r'));
		});
	});

	it('open() in write mode stores content to the data store on close', () => {
		mock.inject('fs', { data: {} }, (m_fs) => {
			const f = m_fs.open('/tmp/out.txt', 'w');
			f.write('hello ');
			f.write('world');
			f.close();
			assert.match('hello world', m_fs.readfile('/tmp/out.txt'));
		});
	});

	it('open() in write mode overwrites existing content', () => {
		mock.inject('fs', { data: { '/tmp/existing.txt': 'old' } }, (m_fs) => {
			const f = m_fs.open('/tmp/existing.txt', 'w');
			f.write('new');
			f.close();
			assert.match('new', m_fs.readfile('/tmp/existing.txt'));
		});
	});

	it('open() in append mode preserves existing content', () => {
		mock.inject('fs', { data: { '/tmp/log.txt': 'first\n' } }, (m_fs) => {
			const f = m_fs.open('/tmp/log.txt', 'a');
			f.write('second\n');
			f.close();
			assert.match('first\nsecond\n', m_fs.readfile('/tmp/log.txt'));
		});
	});

	it('open() error() always returns null', () => {
		mock.inject('fs', { data: { '/tmp/f.txt': 'x' } }, (m_fs) => {
			assert.match(null, m_fs.open('/tmp/f.txt', 'r').error());
		});
	});

	it('popen() in read mode returns a handle that reads the virtual command output', () => {
		mock.inject('fs', { commands: { 'echo hello': 'hello\n' } }, (m_fs) => {
			const f = m_fs.popen('echo hello', 'r');
			assert.match('hello\n', f.read('all'));
			f.close();
		});
	});

	it('popen() in write mode stores written data under the command key', () => {
		mock.inject('fs', { commands: {} }, (m_fs) => {
			const f = m_fs.popen('cat > /tmp/sink', 'w');
			f.write('piped data');
			f.close();
			const r = m_fs.popen('cat > /tmp/sink', 'r');
			assert.match('piped data', r.read('all'));
			r.close();
		});
	});

	it('popen() throws in strict mode for unmocked command', () => {
		assert.throws(() => {
			mock.inject('fs', { strict: true, commands: {} }, (m_fs) => {
				m_fs.popen('unknown command', 'r');
			});
		}, /strict mock/);
	});

	it('inject with strict:false suppresses a global strict:true', () => {
		mock.global.patch('fs', { strict: true, data: { '/base': 'x' } });
		// Without the fix, is_strict() always returned true because it checked
		// global first; the inner inject's strict:false was silently ignored.
		mock.inject('fs', { strict: false, data: {} }, (m_fs) => {
			assert.match(null, m_fs.readfile('/unmocked'), 'strict:false layer must win over global strict:true');
		});
		mock.global.unpatch('fs');
	});

	it('readfile() returns null (not a strict error) for a path deleted with unlink()', () => {
		// In strict mode: if readfile() cannot distinguish a deleted key (value null)
		// from an absent key, it falls through to the strict guard and dies.
		mock.inject('fs', { strict: true, data: { '/tmp/sentinel.txt': 'content' } }, (m_fs) => {
			m_fs.unlink('/tmp/sentinel.txt');
			assert.match(null, m_fs.readfile('/tmp/sentinel.txt'), 'deleted path must return null, not throw');
		});
	});

	it('access() returns false (not a real-fs lookup) for a path deleted with unlink()', () => {
		// /etc/banner exists on disk; without the fix, access() after unlink()
		// falls through to real.access() and returns truthy.
		mock.inject('fs', { data: { '/etc/banner': 'mocked' } }, (m_fs) => {
			m_fs.unlink('/etc/banner');
			assert.match(false, m_fs.access('/etc/banner'), 'deleted file must not be accessible');
		});
	});

	it('stat() returns null (not real stat) for a path deleted with unlink()', () => {
		mock.inject('fs', { data: { '/etc/banner': 'mocked' } }, (m_fs) => {
			m_fs.unlink('/etc/banner');
			assert.match(null, m_fs.stat('/etc/banner'), 'deleted file must stat to null');
		});
	});

});
