# Mock API Reference

The `mock` object and `spy()` function are importable from `'utest'`.

```js
import { mock, spy } from 'utest';
```

A module must be declared in the `mocks` key of `utest.config.uc` before it can be intercepted. See [CLI and Configuration — The `mocks` key](cli.md#the-mocks-key).

---

## State object

All mock entry points accept a `state` object that configures what the proxy does. All fields are optional.

| Field | Type | Description |
| :--- | :--- | :--- |
| `data` | object | Key-value map of mock data. Keys and value shapes are proxy-specific; see [Proxy Data Models](proxy-data-models.md). |
| `behavior` | object | Map of function names to replacement implementations. A matching entry completely replaces the proxy's built-in handling for that function. |
| `strict` | boolean | When `true`, any call that hits an unmocked key dies with a `strict mock:` error instead of falling through to the real module. Defaults to `false`. |

---

## Scoped injection

### `mock.inject(name, state, cb)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `name` | string | Module name as it appears in `import` statements (e.g. `'fs'`, `'ubus'`). |
| `state` | object | State object applied for the duration of `cb`. |
| `cb` | function | Receives the proxy as its sole argument. The state layer is pushed before `cb` is called and popped when it returns or throws. |

**Returns:** the value returned by `cb`.

Pushes a transient state layer onto the named module's mock stack, calls `cb(proxy)`, then pops the layer. The real module is unaffected outside `cb`. Calls to `mock.inject` may be nested; inner layers shadow outer layers for matching keys while leaving unmatched keys visible to outer layers.

If `cb` throws, the layer is still popped and the exception is re-raised.

```js
const content = mock.inject('fs', {
    data: { '/tmp/config': 'enabled=1' },
    strict: true
}, (m_fs) => m_fs.readfile('/tmp/config'));
assert.match('enabled=1', content);
```

---

## Global mock

### `mock.global.patch(name, state)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `name` | string | Module name. |
| `state` | object | State object applied globally until `unpatch` is called. |

**Returns:** proxy object.

Installs persistent global state for the named module and returns a proxy. When a shim is active for that module, code that imported the real module via `import * as mod from 'name'` transparently routes through the same mock engine, making the global state visible to production code under test.

Global state is independent of scoped layers. `mock.inject` layers shadow global state but do not erase it; the global state becomes visible again when all layers are popped.

```js
const m_fs = mock.global.patch('fs', {
    data: { '/etc/myapp.conf': 'debug=0' }
});
assert.match('debug=0', m_fs.readfile('/etc/myapp.conf'));
mock.global.unpatch('fs');
```

---

### `mock.global.unpatch(name)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `name` | string | Module name whose global state is to be cleared. |

**Returns:** nothing.

Removes all global state for the named module and clears the stored proxy. Scoped layers (from `mock.inject`) are unaffected.

```js
mock.global.unpatch('ubus');
```

---

## Call inspection

### `spy(proxy)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `proxy` | object | A proxy returned by `mock.inject()` or `mock.global.patch()`, or a nested object returned by the proxy (e.g. a UCI cursor or a ubus connection). |

**Returns:** an object `{ calls: { <method>: [[args], ...] } }`.

Returns the call log for a proxy object. `calls` is a plain object keyed by method name; each value is an array of argument arrays — one element per invocation, in call order.

Call records are fresh for each `mock.inject()` scope: a new `inject()` call starts with empty records even if the same module was previously injected. Records from `mock.global.patch()` accumulate until `mock.global.unpatch()` is called.

```js
import { mock, spy, assert, contains, any } from 'utest';

mock.inject('fs', { data: { '/a': 'x', '/b': 'y' } }, (m_fs) => {
    m_fs.readfile('/a');
    m_fs.readfile('/b');

    // each element is the argument list for one call
    assert.match([ ['/a'], ['/b'] ], spy(m_fs).calls.readfile);

    // contains matches a subset of calls keys
    assert.match(contains({
        readfile: [ ['/a'], ['/b'] ]
    }), spy(m_fs).calls);

    // use any() to ignore specific arguments
    assert.match([
        [ any() ],
        [ any() ]
    ], spy(m_fs).calls.readfile);
});
```

For proxies that return inner objects (UCI cursor, ubus connection, uclient instance), call `spy()` on the inner object:

```js
mock.inject('uci', {
    data: { network: { wan: { '.type': 'interface', proto: 'dhcp' } } }
}, (m_uci) => {
    let cursor = m_uci.cursor();
    cursor.get('network', 'wan', 'proto');
    assert.match([ ['network', 'wan', 'proto'] ], spy(cursor).calls.get);
});
```

---

## Snapshot and restore

### `mock.snapshot()`

**Parameters:** none.

**Returns:** snapshot object representing the current global state of all registered modules.

Captures the global `data`, `behavior`, `strict`, and proxy of every module that has been registered with the mock engine. The snapshot does not include transient scoped layers from `mock.inject`.

```js
const snap = mock.snapshot();
```

---

### `mock.restore(snap)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `snap` | object | Snapshot previously returned by `mock.snapshot()`. |

**Returns:** nothing.

Restores global state to exactly what it was when `snap` was taken. All current scoped layers are cleared. Modules that existed at snapshot time are reset to their saved state; modules registered after the snapshot was taken are cleared entirely.

```js
const snap = mock.snapshot();
mock.global.patch('uci', { data: { 'myapp': { 'cfg': { '.type': 'opts', 'x': '1' } } } });
// … test code …
mock.restore(snap);
```

---

## See also

- How mocking works end-to-end: [About the mocking architecture](../explanation/concepts.md)
- When to use inject vs patch: [About mock.inject() vs mock.global.patch()](../explanation/inject-vs-patch.md)
- Data key format for each built-in proxy: [Proxy Data Models](proxy-data-models.md)
