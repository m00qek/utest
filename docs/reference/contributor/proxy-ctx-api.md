# Proxy context API reference

Every proxy `create(name, real, ctx)` function receives a `ctx` object built by
`src/utest/mock/proxy_base.uc`. The object provides read/write access to the
mock engine's registry for the named module.

---

## `ctx.get(channel, key)`

Searches the layer stack from top to bottom, then falls back to global state,
looking only within `channel`. Returns the first value found for `key`, or
`null` if no entry exists at any level.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `channel` | string | Channel name, e.g. `'data'` or `'commands'` |
| `key` | string | The key to look up |

**Returns:** any value stored under `key` in `channel`, or `null`.

**Notes:** `get` alone cannot tell an explicitly-stored `null` from "not found"
(both return `null`). Use `ctx.has(channel, key)` / `ctx.has_data(key)` when
that distinction matters — for example, the `fs` proxy treats a path stored as
`null` as *explicitly absent* rather than unseeded.

---

## `ctx.set(channel, key, val)`

Writes `val` under `key` in `channel`. If any layers are active (i.e. inside a
`mock.inject()` callback), the write goes to the innermost layer. If no layers
are active, the write goes to global state.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `channel` | string | Channel name, e.g. `'data'` or `'commands'` |
| `key` | string | The key to write |
| `val` | any | The value to store |

**Returns:** nothing.

---

## `ctx.all_keys(channel)`

Returns an array of every key that exists across all layers and global state
within `channel`, deduplicated. Order is not guaranteed.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `channel` | string | Channel name, e.g. `'data'` |

**Returns:** array of strings.

**Usage:** proxy methods like `lsdir` and `glob` use this to enumerate all
virtual paths in the `data` channel without seeing keys from other channels.

---

## `ctx.get_data(key)`

Shorthand for `ctx.get('data', key)`. Prefer the generic form when writing
new proxy code; this shorthand is retained for backward compatibility.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `key` | string | The data key to look up |

**Returns:** any value stored under `key` in the `data` channel, or `null`.

---

## `ctx.set_data(key, val)`

Shorthand for `ctx.set('data', key, val)`.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `key` | string | The data key to write |
| `val` | any | The value to store |

**Returns:** nothing.

---

## `ctx.get_behavior(name)`

Returns the override function registered for `name`, using the same top-down
layer-then-global search as `get_data`. Returns `null` if no override is
registered.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `name` | string | The function name to look up (e.g. `'readfile'`, `'call'`) |

**Returns:** a function, or `null`.

**Usage pattern in proxy methods:**

```js
proxy.readfile = function(path) {
    let f = ctx.get_behavior('readfile');
    if (f) return f(path);   // caller-supplied override takes precedence
    // ... data-driven logic below
};
```

---

## `ctx.is_strict()`

Returns `true` if any active layer or the global state has `strict: true`.
In strict mode a proxy method should call `die()` when no mock data covers the
call, rather than falling through to the real module.

**Returns:** boolean.

---

## `ctx.is_active()`

Returns `true` if any mock state is currently active for this module: at least
one layer is present, or global data/behavior/proxy is non-empty.

**Returns:** boolean.

**Usage:** proxy write methods use this to decide whether to record the write
in mock state or pass it to the real module:

```js
proxy.writefile = function(path, data) {
    if (ctx.is_active()) {
        ctx.set_data(path, data);  // capture in mock state
        return length(data);
    }
    return real.writefile(path, data);
};
```

---

## `ctx.get_all_data_keys()`

Shorthand for `ctx.all_keys('data')`.

**Returns:** array of strings.

---

## `ctx.has(channel, key)` / `ctx.has_data(key)`

Returns `true` if `key` exists in `channel` at any layer or in global state,
even when its stored value is `null`. `has_data(key)` is shorthand for
`has('data', key)`. Use this to distinguish an explicitly-stored `null` from an
absent key (see the note under `ctx.get`).

**Returns:** boolean.

---

## `ctx.record_call(name, args)`

Appends `args` (an array) to the recorded call log for method `name`, which is
what `spy(proxy).calls.<name>` reads. **Every proxy method must call this** (as
its first action) so the method is visible to `spy()`; a method that skips it
silently records nothing.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `name` | string | The method name being recorded (e.g. `'readfile'`) |
| `args` | array | The argument list the method received |

**Returns:** nothing.

```js
proxy.readfile = function(path, size) {
    ctx.record_call('readfile', size === null ? [path] : [path, size]);
    // ... behavior override → data → strict → real ...
};
```

---

## `ctx.real_call(name, args, fallback)`

Calls `name(...args)` on the real module and returns its result, or returns
`fallback` when the real module is absent (`real` is `null` — e.g. a module not
present on the host). Use it for the final fall-through step in a non-strict
proxy method.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `name` | string | Real-module function to call |
| `args` | array | Arguments to pass |
| `fallback` | any | Returned when the real module is unavailable |

**Returns:** the real function's result, or `fallback`.

---

## `ctx.clone(v)`

Returns a deep copy of `v`. Use it when a read method should hand back a fresh
value the way a real module does (real `uci`/`fs` return copies), so a caller
that mutates the result cannot corrupt the mock's stored data.

**Returns:** a deep copy of `v`.

---

## `ctx.base()`

Constructs and returns a generic proxy object that covers every exported
function of `real`. For each function `fn` on `real`, the generated proxy
method checks for a behavior override via `get_behavior(fn_name)` first, then
calls `real.fn(...)`. Non-function properties are copied by reference.

**Returns:** an object.

**Usage:** call `ctx.base()` at the start of `create()` to get a complete
passthrough proxy, then override only the methods that need custom logic:

```js
create: function(name, real, ctx) {
    let proxy = ctx.base();   // all real functions are proxied generically
    proxy.read = function(key) {
        // custom logic here
    };
    return proxy;
}
```

If `real` is `null` (module absent from rootfs), `ctx.base()` returns an empty
object `{}`.
