# How to mock a module with mock.inject()

Use `mock.inject()` to replace a module's behaviour inside a single callback scope, leaving the real imported binding completely unaffected outside it.

---

## Declare the module in the config file

Create a config file alongside your test file (e.g. `my_config.uc`) and list the module under `mocks`. Use `null` to request the built-in proxy:

```js
return {
    mocks: {
        fs: null
    }
};
```

The framework reads this file and generates a shim for `fs` before running any tests.

---

## Write the inject call

Import `mock` from `'utest'` in your test file, then call `mock.inject()` with three arguments: the module name, a state object, and a callback that receives the proxy:

```js
import { describe, it, mock } from 'utest';
import { assert } from 'utest.assert';
import * as fs from 'fs';

describe('my feature', () => {
    it('reads from virtual path', () => {
        mock.inject('fs', { data: { '/tmp/config.txt': 'hello' } }, (m_fs) => {
            assert.eq(m_fs.readfile('/tmp/config.txt'), 'hello');
        });
    });
});
```

The proxy object `m_fs` is the mock. All calls go through it.

---

## Understand the callback scope

The mock state is active only for the duration of the callback. Once the callback returns, the state layer is removed.

The real imported binding (`fs`) is never intercepted by `mock.inject()`. Calls on it always reach the real module, even from inside the callback:

```js
mock.inject('fs', { data: { '/tmp/scoped': 'data' } }, (m_fs) => {
    assert.eq(m_fs.readfile('/tmp/scoped'), 'data');
    assert.ok(fs.readfile('/tmp/scoped') == null, 'real fs is unaffected inside callback');
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
    assert.eq(created, ['/tmp/custom_path']);
});
```

---

## Nest inject calls

`mock.inject()` calls stack. An inner call inherits all data from outer layers and can add its own:

```js
mock.inject('fs', { data: { '/a': '1' } }, (m_fs) => {
    assert.eq(m_fs.readfile('/a'), '1');

    mock.inject('fs', { data: { '/b': '2' } }, (m_fs2) => {
        assert.eq(m_fs2.readfile('/a'), '1');
        assert.eq(m_fs2.readfile('/b'), '2');
    });

    assert.eq(m_fs.readfile('/a'), '1');
    assert.ok(m_fs.readfile('/b') == null, 'inner state is gone after inner callback');
});
```

---

## Next steps

- Intercept the real imported binding: [How-to: Patch global state with mock.global.patch()](mock-global-patch.md)
- Fail loudly on unmocked calls: [How-to: Use strict mode](strict-mode.md)
- Mock the filesystem in detail: [How-to: Mock the filesystem](mock-fs.md)
