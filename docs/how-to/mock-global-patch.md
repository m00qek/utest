# How to patch global state with mock.global.patch()

Use `mock.global.patch()` when the code under test imports a module directly and calls it through the imported binding — `mock.inject()` does not intercept that binding, but the global patch does.

---

## When to use this instead of inject

`import * as fs from 'fs'` in your production code gives that file a direct reference to the real module (or the shim, when mocks are configured). `mock.inject()` passes a proxy to the callback but leaves the shim's global state untouched, so calls made through the imported binding bypass the proxy.

`mock.global.patch()` writes into the shim's global state. Any call through the imported binding — whether in the test file or in the module under test — is transparently intercepted.

---

## Declare the module in the config file

Add the module to `mocks` in the config file so the framework generates a shim:

```js
return {
    mocks: {
        fs: null
    }
};
```

---

## Call patch and unpatch

Call `mock.global.patch()` with the module name and a state object. It returns the proxy. Call `mock.global.unpatch()` when done to clear global state:

```js
import { describe, it, mock } from 'utest';
import { assert } from 'utest.assert';
import * as fs from 'fs';

describe('global patch', () => {
    it('intercepts calls through the imported binding', () => {
        const m_fs = mock.global.patch('fs', { data: { '/tmp/setup.txt': 'setup' } });

        assert.eq(m_fs.readfile('/tmp/setup.txt'), 'setup');
        assert.eq(fs.readfile('/tmp/setup.txt'), 'setup', 'shim transparently intercepts global state');

        mock.global.unpatch('fs');
    });
});
```

Always call `mock.global.unpatch()` before the test ends. Unpaired patches leak state into subsequent tests.

---

## Observe state clearing after unpatch

After `unpatch()`, the proxy object returned by `patch()` reflects the cleared state. Calls on it return `null` for data that was previously seeded:

```js
const m_fs = mock.global.patch('fs', { data: { '/tmp/setup.txt': 'setup' } });
assert.eq(m_fs.readfile('/tmp/setup.txt'), 'setup');
mock.global.unpatch('fs');

assert.eq(m_fs.readfile('/tmp/setup.txt'), null);
```

---

## Use the same state options as inject

The state object accepts `data`, `behavior`, and `strict` — the same keys as `mock.inject()`:

```js
const m_ubus = mock.global.patch('ubus', {
    data: { 'system:board': { hostname: 'patched' } }
});
// ... test code that calls ubus.connect().call(...) through the real import ...
mock.global.unpatch('ubus');
```

---

## Next steps

- Scope a mock to a callback instead: [How-to: Mock a module with mock.inject()](mock-inject.md)
- Fail loudly on unmocked calls: [How-to: Use strict mode](strict-mode.md)
- Write a proxy that intercepts absent modules: [How-to: Write a custom proxy](custom-proxy.md)
