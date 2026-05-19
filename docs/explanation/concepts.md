# About the key concepts

A short glossary of the terms used throughout this documentation. Read this before the how-to guides if the vocabulary is unfamiliar.

---

## Test suite, bundle, and test

A **test** is a single `it()` block — one named assertion sequence that either passes or fails.

A **suite** is a single `.uc` test file. It may contain any number of `describe` groups and `it` blocks.

A **bundle** is a named collection of suites passed on the command line (`[Name:]glob`). Bundles are a reporting convenience; they do not affect how tests run.

---

## Mock

A **mock** is a controlled substitute for a real module. When code under test calls `fs.readfile('/etc/config/uci')`, a mock can intercept that call and return a canned value instead of touching the real filesystem.

Mocking in utest is non-invasive: the test file does not need to rewrite the module import or pass a dependency explicitly into the code under test. The framework intercepts calls at the module boundary transparently.

---

## Shim

A **shim** is a generated ES-module that sits between the test file and the real module. When utest is configured to mock `fs`, it generates a thin file named `fs.uc` and places it first on the worker's module search path. Every `import * as fs from 'fs'` in the test file (and in any module the test file imports) resolves to the shim instead of the real module.

The shim's job is minimal: on every call it checks whether a proxy is active. If one is, the call goes to the proxy. If not, the call falls through to the real module unchanged.

This design means mocking is opt-in per module (declared in the config file) and has zero cost when no mock is active.

See [About shim generation](shim-generation.md) for how shims are built at runtime.

---

## Proxy

A **proxy** is the object that actually implements mock behaviour. When a shim detects that a mock is active, it delegates the call to the proxy for that module.

The proxy is responsible for:

- Checking whether a **behavior override** is registered for the called function.
- Looking up a value in the **mock data** for the call's key.
- Enforcing **strict mode** if enabled.
- Falling through to the real module if none of the above apply.

utest ships built-in proxies for `fs`, `uci`, `ubus`, `uloop`, and `uclient`. You can also [write a custom proxy](../how-to/custom-proxy.md) for any other module.

---

## Mock data

**Mock data** is a key→value map you supply when setting up a mock. What "key" means is proxy-specific:

- For `fs`: the key is a file path, the value is the file contents.
- For `uci`: the key is a package name, the value is a nested section/option map.
- For `ubus`: the key is `'object:method'`, the value is the response.
- For `uclient`: the key is a URL, the value is a response object with `status`, `headers`, and `body`.

The proxy consults mock data when a call arrives and no behavior override is registered.

---

## Behavior override

A **behavior override** (also called a **behavior**) is a function you register under a specific method name. When the proxy sees a call to that method, it invokes your function instead of consulting mock data or the real module.

Use behavior overrides when the return value depends on the call's arguments in a way that a static data map cannot express.

```js
mock.inject('fs', {
    behavior: {
        readfile: function(path) {
            return path === '/etc/hostname' ? 'myrouter' : null;
        }
    }
}, (m_fs) => { ... });
```

---

## inject() and patch()

These are the two mechanisms for activating a mock.

**`mock.inject(name, state, callback)`** creates a proxy and passes it to the callback as an argument. The mock is active only for the duration of the callback. When the callback returns (or throws), the proxy is discarded and the layer is removed. The real imported binding in the test file is unaffected.

**`mock.global.patch(name, state)`** installs a proxy into the shim itself, so every call to the module — including calls made through top-level imports in the code under test — is intercepted. The proxy remains active until `mock.global.unpatch(name)` is called or the test ends.

See [About inject() vs global.patch()](inject-vs-patch.md) for the full trade-off analysis.

---

## Layer

A **layer** is the unit of state pushed onto the mock engine's stack by each `inject()` call. It holds a copy of the `data`, `behavior`, and `strict` settings for that injection.

Layers stack. An inner `inject()` creates a new layer on top; the proxy searches from the top of the stack downward. When the inner callback exits, its layer is popped and the outer layer's values are visible again. This makes nested mocking safe and predictable.

---

## Strict mode

**Strict mode** changes what happens when code calls a proxied function with a key that has no mock data and no behavior override. Normally the proxy falls through to the real module (returning `null` if the real module is absent). With `strict: true`, the proxy calls `die()` immediately, which the runner reports as a `FAIL`.

Strict mode is useful in narrow unit tests where you want to be told explicitly if the code under test touches a path you did not anticipate.

See [About strict mode](strict-mode.md).

---

## Worker and coordinator

utest runs each test file in its own subprocess (the **worker**). A separate process (the **coordinator**) spawns workers, reads their JSON output, and feeds events to the reporter.

The subprocess boundary provides two guarantees: a crash in one test file cannot affect another, and global state (imports, monkey-patching) cannot bleed between files.

See [About the worker/coordinator architecture](worker-coordinator.md).
