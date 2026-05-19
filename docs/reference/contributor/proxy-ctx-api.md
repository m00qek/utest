# Proxy context API reference

Every proxy `create(name, real, ctx)` function receives a `ctx` object built by
`src/utest/mock/proxy_base.uc`. The object provides read/write access to the
mock engine's registry for the named module.

---

## `ctx.get_data(key)`

Searches the layer stack from top to bottom, then falls back to global state.
Returns the first value found for `key`, or `null` if no entry exists at any
level.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `key` | string | The data key to look up |

**Returns:** any value stored under `key`, or `null`.

**Notes:** A value of `null` stored explicitly is indistinguishable from
"not found" — use a sentinel object if you need to distinguish the two.

---

## `ctx.set_data(key, val)`

Writes `val` under `key`. If any layers are active (i.e. inside a
`mock.inject()` callback), the write goes to the innermost layer. If no layers
are active, the write goes to global state.

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

Returns an array of every key that exists across all layers and global state,
deduplicated. Order is not guaranteed.

**Returns:** array of strings.

**Usage:** proxy methods like `lsdir` and `glob` use this to enumerate all
virtual paths stored in mock data.

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
