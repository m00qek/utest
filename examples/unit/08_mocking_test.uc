import { describe, it, mock, truthy, regex } from 'utest';
import { assert } from 'utest.assert';
import * as fs from 'fs';

/**
 * FS Mocking Example
 *
 * Demonstrates how to intercept filesystem calls. `import * as fs from 'fs'`
 * always gives the real module. Mock proxies are received via the callback
 * parameter (mock.inject) or the return value (mock.patch).
 */

describe('FS Mocking', () => {
	it('real fs is unaffected by default', () => {
		const content = fs.readfile('/etc/banner');
		assert.match(content, regex(/OpenWrt/));
	});

	it('patches global state via mock.global.patch()', () => {
		const m_fs = mock.global.patch('fs', { data: { '/tmp/setup.txt': 'setup' } });
		assert.match(m_fs.readfile('/tmp/setup.txt'), 'setup');
		assert.match(fs.readfile('/tmp/setup.txt'), 'setup', 'shim transparently intercepts global state');
		mock.global.unpatch('fs');

		assert.match(m_fs.readfile('/tmp/setup.txt'), null);
	});

	it('injects scoped mock via mock.inject()', () => {
		mock.inject('fs', { data: { '/tmp/scoped': 'data' } }, (m_fs) => {
			assert.match(m_fs.readfile('/tmp/scoped'), 'data');
			assert.match(fs.readfile('/tmp/scoped'), null, 'real fs is unaffected inside callback');
		});
	});

	it('supports nesting mock.inject()', () => {
		mock.inject('fs', { data: { '/a': '1' } }, (m_fs) => {
			assert.match(m_fs.readfile('/a'), '1');

			mock.inject('fs', { data: { '/b': '2' } }, (m_fs2) => {
				assert.match(m_fs2.readfile('/a'), '1');
				assert.match(m_fs2.readfile('/b'), '2');
			});

			assert.match(m_fs.readfile('/a'), '1');
			assert.match(m_fs.readfile('/b'), null, "Mock state should be restored");
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
		assert.match(created, ['/tmp/custom_path']);
	});

	it('intercepts readfile calls when enabled', () => {
		const m_fs = mock.global.patch('fs', { data: { '/tmp/virtual.txt': 'hello virtual world' } });
		assert.match(m_fs.readfile('/tmp/virtual.txt'), 'hello virtual world');
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
		assert.match(list, ['file1.txt', 'file2.txt', 'subdir']);
		mock.global.unpatch('fs');
	});

	it('merges real and virtual files in lsdir()', () => {
		const m_fs = mock.global.patch('fs', { data: { '/etc/virtual_config': 'v' } });
		const list = m_fs.lsdir('/etc');

		let has_virtual = false;
		let has_real = false;
		for (let name in list) {
			if (name == 'virtual_config') has_virtual = true;
			if (name == 'banner' || name == 'hosts') has_real = true;
		}

		assert.match(has_virtual, truthy(), 'Should find virtual file');
		assert.match(has_real, truthy(), 'Should find real file');
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
		assert.match(files, ['/tmp/glob/a.txt', '/tmp/glob/b.txt']);
		mock.global.unpatch('fs');
	});

	it('supports writing to pre-registered virtual files', () => {
		const m_fs = mock.global.patch('fs', { data: { '/tmp/writable.txt': 'initial' } });
		m_fs.writefile('/tmp/writable.txt', 'updated');
		assert.match(m_fs.readfile('/tmp/writable.txt'), 'updated');
		mock.global.unpatch('fs');
	});

	it('supports writing to new virtual paths when mock is active', () => {
		const m_fs = mock.global.patch('fs', { data: { '/tmp/seed.txt': 'seed' } });
		m_fs.writefile('/tmp/new.txt', 'created');
		assert.match(m_fs.readfile('/tmp/new.txt'), 'created');
		mock.global.unpatch('fs');
	});

	it('access() returns true for virtual files', () => {
		mock.inject('fs', { data: { '/tmp/present.txt': 'yes' } }, (m_fs) => {
			assert.match(m_fs.access('/tmp/present.txt'), truthy());
			assert.match(m_fs.access('/tmp/absent.txt'), null);
		});
	});

	it('stat() returns size and type for virtual files', () => {
		mock.inject('fs', { data: { '/tmp/data.txt': 'hello' } }, (m_fs) => {
			let s = m_fs.stat('/tmp/data.txt');
			assert.match(s.size, 5);
			assert.match(s.type, 'regular');
			assert.match(m_fs.stat('/tmp/missing.txt'), null);
		});
	});

	it('rename() moves a virtual file', () => {
		mock.inject('fs', { data: { '/tmp/old.txt': 'content' } }, (m_fs) => {
			assert.match(m_fs.rename('/tmp/old.txt', '/tmp/new.txt'), truthy());
			assert.match(m_fs.readfile('/tmp/new.txt'), 'content');
			assert.match(m_fs.readfile('/tmp/old.txt'), null);
		});
	});

	it('unlink() removes a virtual file and it disappears from lsdir()', () => {
		mock.inject('fs', { data: {
			'/tmp/dir/keep.txt': 'keep',
			'/tmp/dir/gone.txt': 'gone'
		}}, (m_fs) => {
			assert.match(m_fs.unlink('/tmp/dir/gone.txt'), truthy());
			assert.match(m_fs.readfile('/tmp/dir/gone.txt'), null);
			const list = m_fs.lsdir('/tmp/dir');
			assert.match(list, ['keep.txt']);
		});
	});

	it('mkdir() and chmod() are no-ops returning true', () => {
		mock.inject('fs', {}, (m_fs) => {
			assert.match(m_fs.mkdir('/tmp/newdir', 493), truthy());
			assert.match(m_fs.chmod('/tmp/file.txt', 420), truthy());
		});
	});

	it('error() returns null by default', () => {
		mock.inject('fs', {}, (m_fs) => {
			assert.match(m_fs.error(), null);
		});
	});

	it('access() returns true for virtual directories', () => {
		mock.inject('fs', { data: { '/tmp/dir/file.txt': 'content' } }, (m_fs) => {
			assert.match(m_fs.access('/tmp/dir'), truthy(), 'parent dir of a virtual file must be accessible');
			assert.match(m_fs.access('/tmp'), truthy(), 'ancestor dir must be accessible');
			assert.match(m_fs.access('/tmp/other'), null, 'unrelated path must return null');
		});
	});

	it('stat() returns directory type for virtual directories', () => {
		mock.inject('fs', { data: { '/tmp/dir/file.txt': 'content' } }, (m_fs) => {
			let s = m_fs.stat('/tmp/dir');
			assert.match(s.type, 'directory');
			assert.match(s.size, 0);
			assert.match(m_fs.stat('/tmp/missing'), null);
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
			assert.match(files, ['/tmp/test_1.uc', '/tmp/test_2.uc']);
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
			assert.match(files, ['/tmp/globstar/a/b/c.txt', '/tmp/globstar/a/d.txt']);
		});
	});
});
