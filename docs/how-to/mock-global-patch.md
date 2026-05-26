# How to patch global state with mock.global.patch()

Use `mock.global.patch()` when the code under test imports a module directly and calls it through the imported binding — `mock.inject()` does not intercept that binding, but the global patch does.

---

## When to use this instead of inject

If the code under test imports a module directly and calls it through its own binding, use `mock.global.patch()`. If you only need to intercept calls made through the proxy object inside a callback, use `mock.inject()`.

See [About mock.inject() vs mock.global.patch()](../explanation/inject-vs-patch.md) for the full trade-off analysis.

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
import { describe, it, mock, assert } from 'utest';
import * as fs from 'fs';

describe('global patch', () => {
    it('intercepts calls through the imported binding', () => {
        const m_fs = mock.global.patch('fs', { data: { '/tmp/setup.txt': 'setup' } });

        assert.match('setup', m_fs.readfile('/tmp/setup.txt'));
        assert.match('setup', fs.readfile('/tmp/setup.txt'), 'shim transparently intercepts global state');

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
assert.match('setup', m_fs.readfile('/tmp/setup.txt'));
mock.global.unpatch('fs');

assert.match(null, m_fs.readfile('/tmp/setup.txt'));
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
