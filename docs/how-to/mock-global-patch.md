# How to patch global state with mock.global.patch()

Use `mock.global.patch()` to intercept calls made through the module's imported binding — including calls in production code that your test imports.

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

## Test code that loads modules with require()

`mock.global.patch()` also intercepts `require()` calls in code under test — no extra configuration is needed. Declare the module in the config as usual, then patch as normal:

```js
// utest.config.uc
return { mocks: { uci: null } };
```

```js
// production code (uses require, not import)
export function get_hostname(uci_mod) {
    return (uci_mod || require('uci')).cursor().get('system', '@system[0]', 'hostname');
}
```

```js
import { describe, it, mock, assert } from 'utest';
import { get_hostname } from 'mylib';

describe('get_hostname()', () => {
    it('reads hostname from uci via require()', () => {
        mock.global.patch('uci', {
            data: { system: { '@system[0]': { '.type': 'system', hostname: 'myrouter' } } }
        });
        assert.match('myrouter', get_hostname());
        mock.global.unpatch('uci');
    });
});
```

The `require('uci')` call inside `get_hostname` is intercepted by the worker's `require()` override and returns the proxy while the global patch is active.

**Important:** the `require()` call must happen at runtime — inside the function body — not at module initialisation time. A module-level `const uci = require('uci')` captures the real module before any patch is applied and will not be intercepted. See [About mock.inject() vs mock.global.patch()](../explanation/inject-vs-patch.md#the-require-constraint) for details.

---

## Next steps

- Decide between inject and patch: [About mock.inject() vs mock.global.patch()](../explanation/inject-vs-patch.md)
- Scope a mock to a callback instead: [How-to: Mock a module with mock.inject()](mock-inject.md)
- Fail loudly on unmocked calls: [How-to: Use strict mode](strict-mode.md)
- Write a proxy that intercepts absent modules: [How-to: Write a custom proxy](custom-proxy.md)
