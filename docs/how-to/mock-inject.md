# How to mock a module with mock.inject()

Use `mock.inject()` to replace a module's behaviour inside a single callback scope, leaving the real imported binding completely unaffected outside it.

---

## Prefer dependency injection

If your code receives a module as a parameter rather than importing it directly, pass the proxy straight to it. No `utest.config.uc` is needed:

```js
// src/reader.uc
export function read_config(fs, path) {
    return fs.readfile(path);
}
```

```js
// test
import { read_config } from 'reader';

mock.inject('fs', { data: { '/etc/config': 'mode=prod' } }, (m_fs) => {
    assert.match('mode=prod', read_config(m_fs, '/etc/config'));
});
```


---

## Declare the module in the config file

Create `utest.config.uc` at the project root and list the module under `mocks`:

```js
return {
    mocks: {
        fs: null
    }
};
```

---

## Write the inject call

Import `mock` from `'utest'` in your test file, then call `mock.inject()` with three arguments: the module name, a state object, and a callback that receives the proxy:

```js
import { describe, it, mock, assert } from 'utest';
import * as fs from 'fs';

describe('my feature', () => {
    it('reads from virtual path', () => {
        mock.inject('fs', { data: { '/tmp/config.txt': 'hello' } }, (m_fs) => {
            assert.match('hello', m_fs.readfile('/tmp/config.txt'));
        });
    });
});
```

The proxy object `m_fs` is the mock. All calls go through it.

---

## Confirm the mock does not affect the real imported binding

The state layer is active only for the duration of the callback. Once the callback returns, the layer is removed.

The real imported binding (`fs`) is never intercepted by `mock.inject()`. Calls on it always reach the real module, even from inside the callback:

```js
mock.inject('fs', { data: { '/tmp/scoped': 'data' } }, (m_fs) => {
    assert.match('data', m_fs.readfile('/tmp/scoped'));
    assert.match(null, fs.readfile('/tmp/scoped'), 'real fs is unaffected inside callback');
});
```

If you need the real imported binding to be intercepted, use `mock.global.patch()` instead.

---

## Override individual functions with behavior

Supply a `behavior` map to replace specific functions entirely:

```js
let created = [];

mock.inject('fs', { behavior: { mkdir: (path) => {
    push(created, path);
    return true;
}}}, (m_fs) => {
    m_fs.mkdir('/tmp/custom_path');
});
assert.match(['/tmp/custom_path'], created);
```

---

## Nest inject calls

`mock.inject()` calls stack. An inner call inherits all data from outer layers and can add its own:

```js
mock.inject('fs', { data: { '/a': '1' } }, (m_fs) => {
    assert.match('1', m_fs.readfile('/a'));

    mock.inject('fs', { data: { '/b': '2' } }, (m_fs2) => {
        assert.match('1', m_fs2.readfile('/a'));
        assert.match('2', m_fs2.readfile('/b'));
    });

    assert.match('1', m_fs.readfile('/a'));
    assert.match(null, m_fs.readfile('/b'), 'inner state is gone after inner callback');
});
```

---

## Next steps

- Intercept the real imported binding: [How-to: Patch global state with mock.global.patch()](mock-global-patch.md)
- Fail loudly on unmocked calls: [How-to: Use strict mode](strict-mode.md)
- Mock the filesystem in detail: [How-to: Mock the filesystem](mock-fs.md)
