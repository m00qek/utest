# How to mock the filesystem

Replace filesystem calls in your tests with an in-memory virtual filesystem seeded from a data map.

Declare `fs: null` in your `utest.config.uc` `mocks` table before using any of the patterns below. See [How-to: Mock a module with mock.inject()](mock-inject.md) for the setup steps.

---

## Seed the data map

Pass a `data` object whose keys are absolute paths and whose values are the file contents as strings. `null` as a value marks a path as absent (deleted):

```js
import { describe, it, mock, assert, truthy } from 'utest';

describe('fs mock', () => {
    it('reads virtual files', () => {
        mock.inject('fs', { data: {
            '/tmp/config.txt': 'enabled=1',
            '/tmp/other.txt':  'data'
        }}, (m_fs) => {
            assert.match('enabled=1', m_fs.readfile('/tmp/config.txt'));
        });
    });
});
```

---

## readfile and writefile

`readfile()` returns the seeded string, or `null` for an unmocked path. `writefile()` stores the data so subsequent reads return the new value:

```js
mock.inject('fs', { data: { '/tmp/writable.txt': 'initial' } }, (m_fs) => {
    m_fs.writefile('/tmp/writable.txt', 'updated');
    assert.match('updated', m_fs.readfile('/tmp/writable.txt'));
});
```

Writing to a path that was not pre-seeded also works — the path is created in the virtual layer:

```js
mock.inject('fs', { data: { '/tmp/seed.txt': 'seed' } }, (m_fs) => {
    m_fs.writefile('/tmp/new.txt', 'created');
    assert.match('created', m_fs.readfile('/tmp/new.txt'));
});
```

---

## lsdir

`lsdir()` returns the immediate children of a path. Virtual entries are merged with real entries from the underlying filesystem (unless strict mode is active, which suppresses the real entries):

```js
mock.inject('fs', { data: {
    '/tmp/mockdir/file1.txt': '1',
    '/tmp/mockdir/file2.txt': '2',
    '/tmp/mockdir/subdir/file3.txt': '3'
}}, (m_fs) => {
    const list = m_fs.lsdir('/tmp/mockdir');
    sort(list);
    assert.match(['file1.txt', 'file2.txt', 'subdir'], list);
});
```

---

## glob

`glob()` matches virtual paths against a shell-style pattern. Three wildcards are supported:

| Wildcard | Matches |
| :--- | :--- |
| `*` | Any sequence of characters within one path component |
| `?` | Any single character within one path component |
| `**` | Any sequence of characters including path separators |

Character classes (`[abc]`, `[0-9]`) are not supported. Real matches are merged with virtual matches unless strict mode suppresses them.

```js
// * matches within one directory level
mock.inject('fs', { data: {
    '/tmp/glob/a.txt': 'a',
    '/tmp/glob/b.txt': 'b',
    '/tmp/glob/c.log': 'c'
}}, (m_fs) => {
    const files = m_fs.glob('/tmp/glob/*.txt');
    sort(files);
    assert.match(['/tmp/glob/a.txt', '/tmp/glob/b.txt'], files);
});
```

```js
// ? matches exactly one character — test_10 has two digits and does not match
mock.inject('fs', { data: {
    '/tmp/test_1.uc': 'a',
    '/tmp/test_2.uc': 'b',
    '/tmp/test_10.uc': 'c'
}}, (m_fs) => {
    const files = m_fs.glob('/tmp/test_?.uc');
    sort(files);
    assert.match(['/tmp/test_1.uc', '/tmp/test_2.uc'], files);
});
```

```js
// ** matches across directory boundaries
mock.inject('fs', { data: {
    '/etc/init/a/main.cfg': 'a',
    '/etc/init/a/sub/extra.cfg': 'b',
    '/etc/other.txt': 'c'
}}, (m_fs) => {
    const files = m_fs.glob('/etc/init/**/*.cfg');
    sort(files);
    assert.match(['/etc/init/a/main.cfg', '/etc/init/a/sub/extra.cfg'], files);
});
```

---

## access and stat

`access()` returns `true` for any virtual file or any directory that contains one, `null` for everything else. `stat()` returns `{ size, mtime, type }` for virtual files (`type: 'regular'`, size in bytes) and `{ size: 0, mtime: 0, type: 'directory' }` for virtual directories, `null` for absent paths:

```js
mock.inject('fs', { data: { '/tmp/dir/data.txt': 'hello' } }, (m_fs) => {
    // virtual file
    assert.match(truthy(), m_fs.access('/tmp/dir/data.txt'));
    let s = m_fs.stat('/tmp/dir/data.txt');
    assert.match(5, s.size);
    assert.match('regular', s.type);

    // virtual directory — inferred from the file path above
    assert.match(truthy(), m_fs.access('/tmp/dir'));
    let d = m_fs.stat('/tmp/dir');
    assert.match('directory', d.type);

    // absent path
    assert.match(null, m_fs.access('/tmp/absent.txt'));
    assert.match(null, m_fs.stat('/tmp/absent.txt'));
});
```

---

## rename and unlink

`rename()` moves a virtual file by copying the data to the new path and setting the old path to `null`. `unlink()` removes a virtual file by setting its path to `null`, which also removes it from `lsdir()`:

```js
mock.inject('fs', { data: { '/tmp/old.txt': 'content' } }, (m_fs) => {
    assert.match(truthy(), m_fs.rename('/tmp/old.txt', '/tmp/new.txt'));
    assert.match('content', m_fs.readfile('/tmp/new.txt'));
    assert.match(null, m_fs.readfile('/tmp/old.txt'));
});

mock.inject('fs', { data: {
    '/tmp/dir/keep.txt': 'keep',
    '/tmp/dir/gone.txt': 'gone'
}}, (m_fs) => {
    m_fs.unlink('/tmp/dir/gone.txt');
    assert.match(['keep.txt'], m_fs.lsdir('/tmp/dir'));
});
```

---

## mkdir and chmod

`mkdir()` and `chmod()` are no-ops that return `true`. They exist so code that creates directories or changes permissions does not fail under the mock:

```js
mock.inject('fs', {}, (m_fs) => {
    assert.match(truthy(), m_fs.mkdir('/tmp/newdir', 493));
    assert.match(truthy(), m_fs.chmod('/tmp/file.txt', 420));
});
```

---

## error

`error()` returns `null` by default, indicating no error:

```js
mock.inject('fs', {}, (m_fs) => {
    assert.match(null, m_fs.error());
});
```

Supply a `behavior` override to simulate error states:

```js
mock.inject('fs', { behavior: { error: () => 'ENOENT' } }, (m_fs) => {
    assert.match('ENOENT', m_fs.error());
});
```

---

## Next steps

- Control what happens on unmocked paths: [How-to: Use strict mode](strict-mode.md)
- Intercept calls through the imported `fs` binding: [How-to: Patch global state with mock.global.patch()](mock-global-patch.md)
- Mock UCI configuration: [How-to: Mock UCI](mock-uci.md)
