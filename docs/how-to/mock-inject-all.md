# How to mock multiple modules at once

Use `mock.inject_all()` to inject two or more modules in a single call when the
code under test depends on several mocked modules simultaneously.

---

## The problem with nested inject() calls

When a function under test reads UCI config and then makes a ubus call, you
need both modules mocked at the same time. Nesting `mock.inject` achieves this,
but the indentation grows quickly and the module names must be remembered across
multiple scopes:

```js
// works, but awkward
mock.inject('uci', { data: uci_data }, (m_uci) => {
    mock.inject('ubus', { data: ubus_data }, (m_ubus) => {
        result = apply_config(m_uci, m_ubus);
    });
});
```

`mock.inject_all()` collapses all the layers into one call.

---

## Basic usage

Pass a map of module names to state objects as the first argument. The callback
receives one proxy per module, destructured by name:

```js
import { describe, it, assert, mock } from 'utest';

describe('apply_config', () => {
    it('applies the uci setting via ubus', () => {
        const result = mock.inject_all({
            uci:  { data: { 'myapp': { 'cfg': { '.type': 'opts', 'enabled': '1' } } } },
            ubus: { data: { 'myapp:reload': { ok: true } } }
        }, ({ uci: m_uci, ubus: m_ubus }) => {
            return apply_config(m_uci, m_ubus);
        });

        assert.match(true, result.ok);
    });
});
```

Both layers are pushed before the callback is called and popped — in reverse
order — when the callback returns or throws.

---

## Destructure only what you need

If the callback does not need to call methods on every proxy directly, just
ignore the ones you don't need. The layers are still active for any code under
test that imports the same modules:

```js
mock.inject_all({
    uci:  { data: { 'network': { 'wan': { '.type': 'interface', 'proto': 'dhcp' } } } },
    ubus: { data: { 'network.interface': { up: true } } }
}, () => {
    // production code imports fs, uci, ubus via the shim —
    // both are mocked even though the callback ignores the proxies.
    const status = network_status_module.query();
    assert.match(true, status.up);
});
```

---

## Set different options per module

Each module gets its own independent state object. Set `strict`, `behavior`, or
extra channels independently:

```js
mock.inject_all({
    uci: {
        data:   { 'firewall': { 'rule1': { '.type': 'rule', 'target': 'ACCEPT' } } },
        strict: true    // die on any unmocked uci key
    },
    fs: {
        data:   { '/etc/fw4.nft': '' },
        strict: false   // allow unmocked fs calls through
    }
}, ({ uci: m_uci, fs: m_fs }) => {
    fw4.generate_ruleset(m_uci, m_fs);
});
```

---

## All targets are validated before any layer is pushed

`inject_all` validates every module name before it pushes any layer. If one
module name is not configured in `utest.config.uc`, the call dies immediately
and no layers are pushed — there is no partial state to clean up:

```js
// If 'missing_module' is not in mocks {}, this dies before touching uci.
mock.inject_all({
    uci:            { data: {} },
    missing_module: { data: {} }
}, () => {});
```

---

## Return a value from the callback

`inject_all` returns whatever the callback returns, just like `inject`:

```js
const calls_made = mock.inject_all({
    ubus: { data: { 'sys:info': { hostname: 'test' } } }
}, ({ ubus: m_ubus }) => {
    production_code.run(m_ubus);
    return spy(m_ubus).calls;
});
assert.match([ [] ], calls_made.connect);
```

---

## Next steps

- Inject a single module: [How-to: Mock a module with mock.inject()](mock-inject.md)
- Intercept real imported bindings: [How-to: Patch global state with mock.global.patch()](mock-global-patch.md)
- Full inject_all API: [Reference: Mock API — mock.inject_all()](../reference/mock-api.md#mockinject_allstates-cb)
