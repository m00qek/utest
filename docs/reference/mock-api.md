# Mock API Reference

The `mock` object is importable from `'utest'`.

```js
import { mock } from 'utest';
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

**Returns:** nothing.

Pushes a transient state layer onto the named module's mock stack, calls `cb(proxy)`, then pops the layer. The real module is unaffected outside `cb`. Calls to `mock.inject` may be nested; inner layers shadow outer layers for matching keys while leaving unmatched keys visible to outer layers.

If `cb` throws, the layer is still popped and the exception is re-raised.

```js
mock.inject('fs', {
    data: { '/tmp/config': 'enabled=1' },
    strict: true
}, (m_fs) => {
    assert.eq(m_fs.readfile('/tmp/config'), 'enabled=1');
});
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
assert.eq(m_fs.readfile('/etc/myapp.conf'), 'debug=0');
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
