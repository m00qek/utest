# About the mocking architecture

utest intercepts module calls without requiring any changes to the code under test — no dependency injection, no interface swaps, no test-aware code paths. This non-invasive property is the central design goal, and it shapes why the framework has three collaborating parts: a **shim**, a **proxy**, and a **mock engine**.

The diagram below shows how a call travels at runtime:

```mermaid
graph LR
    T["Test body"]
    S["Shim\n(generated at startup)"]
    P["Proxy\n(built-in or custom)"]
    D["Mock data\n/ behavior"]
    R["Real module"]

    T -->|"import 'fs'"| S
    S -->|"proxy active"| P
    S -->|"no proxy"| R
    P -->|"data / behavior hit"| D
    P -->|"fallthrough\n(non-strict)"| R
```

---

## The layer model

`mock.inject()` pushes a new layer onto a per-module stack rather than overwriting current state. An inner inject call can override specific keys without destroying what outer layers declared, and each layer is popped automatically when its callback exits — even if the callback throws.

The alternative, a flat mutable map, would require every test to save and restore state explicitly around any nested mock. A forgotten restore would silently corrupt all subsequent tests in the file. The stack makes cleanup unconditional and invisible to the test author.

The proxy searches the stack top-down on every call, then falls back to global state (set by `mock.global.patch()`).

```mermaid
graph TD
    subgraph "module registry (e.g. 'fs')"
        L2["layer 2  ← innermost inject()"]
        L1["layer 1  ← outer inject()"]
        GL["global state  ← mock.global.patch()"]
        REAL["real module"]

        L2 -. "key not found → fall through" .-> L1
        L1 -. "key not found → fall through" .-> GL
        GL -. "no proxy / non-strict → fall through" .-> REAL
    end

    T["Test body"] -->|"m_fs.readfile('/a')"| L2
```

---

## Why three layers?

Each part has a single, narrow responsibility.

The **shim** only intercepts or delegates — it has no knowledge of what mock data exists or which functions should be overridden. This lets shims be generated mechanically from a module's export list.

The **proxy** only handles mock logic — it looks up data, invokes behavior overrides, enforces strict mode, and falls through to the real module. It has no knowledge of how the import was resolved, which means proxies can be swapped per-project via custom proxy factories without touching shims.

The **mock engine** only owns the layer stack and snapshot/restore cycle. It has no knowledge of any specific module, which means the same isolation guarantee applies uniformly across all proxied modules.

Collapsing any two of these into one would couple concerns that need to evolve independently.

---

## See also

- Term definitions: [Reference: Glossary](../reference/glossary.md)
- How shims are generated at startup: [About shim generation](shim-generation.md)
- How inject() and patch() differ at the shim level: [About mock.inject() vs mock.global.patch()](inject-vs-patch.md)
- The layer stack and registry internals (contributor-level detail): [About the mock engine](mock-engine.md)
