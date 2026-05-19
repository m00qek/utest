# How to mock the filesystem

Replace filesystem calls in your tests with an in-memory virtual filesystem seeded from a data map.

---

## Declare the module in the config file

Add `fs` to the `mocks` table in the config file:

```js
return {
    mocks: {
        fs: null
    }
};
```

---

## Seed the data map

Pass a `data` object whose keys are absolute paths and whose values are the file contents as strings. `null` as a value marks a path as absent (deleted):

```js
import { describe, it, mock } from 'utest';
import { assert } from 'utest.assert';

describe('fs mock', () => {
    it('reads virtual files', () => {
        mock.inject('fs', { data: {
            '/tmp/config.txt': 'enabled=1',
            '/tmp/other.txt':  'data'
        }}, (m_fs) => {
            assert.eq(m_fs.readfile('/tmp/config.txt'), 'enabled=1');
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
    assert.eq(m_fs.readfile('/tmp/writable.txt'), 'updated');
});
```

Writing to a path that was not pre-seeded also works — the path is created in the virtual layer:

```js
mock.inject('fs', { data: { '/tmp/seed.txt': 'seed' } }, (m_fs) => {
    m_fs.writefile('/tmp/new.txt', 'created');
    assert.eq(m_fs.readfile('/tmp/new.txt'), 'created');
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
    assert.eq(list, ['file1.txt', 'file2.txt', 'subdir']);
});
```

---

## glob

`glob()` matches virtual paths against a shell-style pattern. Only `*` is translated; `?` and `**` are not supported for virtual path matching. Real matches are included unless strict mode suppresses them:

```js
mock.inject('fs', { data: {
    '/tmp/glob/a.txt': 'a',
    '/tmp/glob/b.txt': 'b',
    '/tmp/glob/c.log': 'c'
}}, (m_fs) => {
    const files = m_fs.glob('/tmp/glob/*.txt');
    sort(files);
    assert.eq(files, ['/tmp/glob/a.txt', '/tmp/glob/b.txt']);
});
```

---

## access and stat

`access()` returns `true` for any path present in the data map, `null` for absent paths. `stat()` returns `{ size, mtime, type }` for present paths (size is the byte length of the string), `null` for absent paths:

```js
mock.inject('fs', { data: { '/tmp/data.txt': 'hello' } }, (m_fs) => {
    assert.ok(m_fs.access('/tmp/data.txt'));
    assert.eq(m_fs.access('/tmp/absent.txt'), null);

    let s = m_fs.stat('/tmp/data.txt');
    assert.eq(s.size, 5);
    assert.eq(s.type, 'regular');
});
```

---

## rename and unlink

`rename()` moves a virtual file by copying the data to the new path and setting the old path to `null`. `unlink()` removes a virtual file by setting its path to `null`, which also removes it from `lsdir()`:

```js
mock.inject('fs', { data: { '/tmp/old.txt': 'content' } }, (m_fs) => {
    assert.ok(m_fs.rename('/tmp/old.txt', '/tmp/new.txt'));
    assert.eq(m_fs.readfile('/tmp/new.txt'), 'content');
    assert.eq(m_fs.readfile('/tmp/old.txt'), null);
});

mock.inject('fs', { data: {
    '/tmp/dir/keep.txt': 'keep',
    '/tmp/dir/gone.txt': 'gone'
}}, (m_fs) => {
    m_fs.unlink('/tmp/dir/gone.txt');
    assert.eq(m_fs.lsdir('/tmp/dir'), ['keep.txt']);
});
```

---

## mkdir and chmod

`mkdir()` and `chmod()` are no-ops that return `true`. They exist so code that creates directories or changes permissions does not fail under the mock:

```js
mock.inject('fs', {}, (m_fs) => {
    assert.ok(m_fs.mkdir('/tmp/newdir', 493));
    assert.ok(m_fs.chmod('/tmp/file.txt', 420));
});
```

---

## error

`error()` returns `null` by default, indicating no error:

```js
mock.inject('fs', {}, (m_fs) => {
    assert.eq(m_fs.error(), null);
});
```

Supply a `behavior` override to simulate error states:

```js
mock.inject('fs', { behavior: { error: () => 'ENOENT' } }, (m_fs) => {
    assert.eq(m_fs.error(), 'ENOENT');
});
```

---

## Next steps

- Control what happens on unmocked paths: [How-to: Use strict mode](strict-mode.md)
- Intercept calls through the imported `fs` binding: [How-to: Patch global state with mock.global.patch()](mock-global-patch.md)
- Mock UCI configuration: [How-to: Mock UCI](mock-uci.md)
