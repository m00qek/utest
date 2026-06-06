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
| *channel* | object | Some proxies declare additional named channels beyond `data`. For example, `fs` uses `commands` for `popen` data. Pass the channel as a top-level key in the state object: `{ data: {...}, commands: {...} }`. See [Proxy Data Models](proxy-data-models.md) for which channels each proxy supports. |

---

## Scoped injection

### `mock.inject_builtin(name, fn, cb)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `name` | string | Name of the built-in global to replace (e.g. `'warn'`, `'system'`, `'print'`). |
| `fn` | function | Replacement function installed in `global[name]` for the duration of `cb`. |
| `cb` | function | Called with no arguments while the replacement is active. The original is restored when it returns or throws. |

**Returns:** the value returned by `cb`.

Saves the current value of `global[name]`, installs `fn` in its place, calls `cb()`, then restores the original. The restore is guaranteed even if `cb` throws — the exception is caught, the global is restored, then the exception is re-raised.

Unlike `mock.inject()`, this function targets the global scope directly. It works for built-ins such as `warn`, `system`, and `print` that are not loadable modules and are therefore unreachable via the shim-based mock API.

Calls to `mock.inject_builtin` may be nested. The inner call saves whatever `global[name]` holds at the moment of the call — which may itself be a replacement — and restores it on exit, so inner and outer scopes remain independent.

```js
const captured = [];
mock.inject_builtin('warn', (...args) => push(captured, join('', args)), () => {
    warn('test message\n');
});
assert.match(['test message\n'], captured);
```

---

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

Installs persistent global state for the named module and returns a proxy. When a shim is active for that module, code that loads the module via `import * as mod from 'name'` or via `require('name')` transparently routes through the same mock engine, making the global state visible to production code under test.

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

### `mock.global.patch_builtin(name, fn)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `name` | string | Name of the built-in global to replace (e.g. `'warn'`, `'system'`, `'print'`). |
| `fn` | function | Replacement function installed in `global[name]` until `unpatch_builtin` is called. |

**Returns:** nothing.

Saves the current value of `global[name]` and installs `fn` in its place. The replacement persists until `mock.global.unpatch_builtin(name)` is called. Unlike `mock.inject_builtin()`, there is no automatic cleanup.

Calling `mock.inject_builtin()` while a `patch_builtin` is active layers on top of it correctly: `inject_builtin` saves the patched function and restores it when its callback exits, leaving the persistent patch in place.

```js
const captured = [];
mock.global.patch_builtin('warn', (...args) => push(captured, join('', args)));
// ... code under test runs here ...
mock.global.unpatch_builtin('warn');
```

---

### `mock.global.unpatch_builtin(name)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `name` | string | Name of the built-in global whose original should be restored. |

**Returns:** nothing.

Restores `global[name]` to the value that was saved by the most recent `mock.global.patch_builtin(name)` call. If `patch_builtin` was never called for `name`, this is a no-op.

```js
mock.global.unpatch_builtin('warn');
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
- Scoped injection vs global state: [About mock.inject() vs mock.global.patch()](../explanation/inject-vs-patch.md)
- Data key format for each built-in proxy: [Proxy Data Models](proxy-data-models.md)
