# Glossary

Definitions of terms used throughout this documentation.

---

## Test, suite, bundle

A **test** is a single `it()` block — one named assertion sequence that either passes or fails.

A **suite** is a single `.uc` test file. It may contain any number of `describe` groups and `it` blocks.

A **bundle** is a named collection of suites passed on the command line (`[Name:]glob`). Bundles are a reporting convenience; they do not affect how tests run.

---

## Mock

A **mock** is a controlled substitute for a real module. When code under test calls `fs.readfile('/etc/config/uci')`, a mock intercepts that call and returns a canned value instead of touching the real filesystem.

---

## Shim

A **shim** is a generated ES-module that sits between the test file and the real module. When utest is configured to mock `fs`, it generates a thin file named `fs.uc` and places it first on the worker's module search path. Every `import * as fs from 'fs'` in the test file (and in any module the test file imports) resolves to the shim instead of the real module.

On every call the shim checks whether a proxy is active. If one is, the call goes to the proxy. If not, the call falls through to the real module unchanged.

For code under test that loads modules with `require()` rather than `import`, a companion `require()` override in the worker covers the same role. See [About shim generation](../explanation/shim-generation.md#intercepting-require-in-program-mode-code).

---

## Proxy

A **proxy** is the object that implements mock behaviour. When a shim detects that a mock is active, it delegates the call to the proxy for that module.

The proxy is responsible for:

- Checking whether a **behavior override** is registered for the called function.
- Looking up a value in the **mock data** for the call's key.
- Enforcing **strict mode** if enabled.
- Falling through to the real module if none of the above apply.

utest ships built-in proxies for `fs`, `uci`, `ubus`, `uloop`, and `uclient`.

---

## Mock data

**Mock data** is a key→value map supplied in the `data` field of a state object. What "key" means is proxy-specific:

| Proxy | Key | Value |
| :--- | :--- | :--- |
| `fs` | filesystem path | file contents (string), or `null` for absent |
| `uci` | package name | section/option map |
| `ubus` | `'object:method'` or `'object'` | response object or function |
| `uclient` | request URL | response descriptor (`status`, `headers`, `body`) |

---

## Behavior override

A **behavior override** is a function registered under a method name in the `behavior` field of a state object. When the proxy sees a call to that method, it invokes the override instead of consulting mock data or the real module.

---

## inject() and patch()

**`mock.inject(name, state, callback)`** pushes a transient state layer, passes the proxy to the callback, and pops the layer when the callback returns or throws. The real imported binding in the test file is unaffected.

**`mock.global.patch(name, state)`** writes into the shim's global state. Every call through the module's imported binding (`import * as mod from 'name'`) or via `require('name')` — including in the code under test — is intercepted until `mock.global.unpatch(name)` is called.

See [About mock.inject() vs mock.global.patch()](../explanation/inject-vs-patch.md) for the full trade-off analysis.

---

## Layer

A **layer** is the unit of state pushed onto the mock engine's stack by each `inject()` call. It holds a copy of the `data`, `behavior`, and `strict` settings for that injection.

Layers stack: an inner `inject()` creates a new layer on top and shadows outer layers for matching keys. When the callback exits, its layer is popped and the outer layer's values become visible again.

---

## Strict mode

**Strict mode** (`strict: true`) changes what happens when a call has no mock data and no behavior override: instead of falling through to the real module, the proxy calls `die()`, which the runner records as `FAIL`.

See [About strict mode](../explanation/strict-mode.md).

---

## Worker and coordinator

utest runs each test file in its own subprocess (the **worker**). A separate process (the **coordinator**) spawns workers, reads their JSON output, and feeds events to the reporter.

See [About the worker/coordinator architecture](../explanation/worker-coordinator.md).

---

## Spy

A **spy** is the call log attached to every proxy object. `spy(proxy)` returns an object whose `calls` map records every method invocation — method name → array of argument arrays. It is used with `assert.match` and combinators to assert that specific functions were called, with specific arguments, and in a specific order.

See [Reference: Mock API — spy](mock-api.md#call-inspection) and [How-to: Inspect calls with spy()](../how-to/spy.md).

---

## Combinator

A **combinator** is a composable predicate object used with `assert.match`. It is created by a factory function (`contains`, `truthy`, `falsy`, `any`, etc.) and has a single `match(actual)` method that returns `{ ok: true }` on success or `{ ok: false, message: '...' }` on failure.

Combinators can be nested inside each other and inside plain object or array values passed to `assert.match`. This lets you build complex assertions from simple, reusable parts — for example, `contains({ code: 200, body: regex(/ok/) })` is a single combinator composed from two others.

See [Reference: Assertions — Combinator factories](assertions.md#combinator-factories).
