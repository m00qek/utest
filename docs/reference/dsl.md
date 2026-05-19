# DSL Reference

All DSL symbols are importable from `'utest'`. They may only be called during module evaluation — calling any DSL function while a test is executing causes a fatal error.

```js
import { describe, it, skip, xit, xdescribe,
         beforeEach, afterEach, setup, teardown, mock } from 'utest';
```

---

## Suite structure

### `describe(name, fn)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `name` | string | Human-readable label for the group. |
| `fn` | function | Synchronous body. Must register tests and nested groups; must not run assertions. |

Creates a named group of tests. Groups may be nested arbitrarily. Hooks and skip status propagate downward through nesting.

```js
describe("Router config", () => {
    it("loads the default section", () => { /* … */ });
});
```

---

### `xdescribe(name, fn)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `name` | string | Label for the skipped group. |
| `fn` | function | Body. Called immediately so nested structure is collected, but all contained tests are marked skipped. |

Marks an entire suite as skipped. Equivalent to wrapping every `it` inside with `skip`. The body is still executed at collection time so syntax errors surface immediately.

```js
xdescribe("Unfinished feature", () => {
    it("not run yet", () => { /* … */ });
});
```

---

## Test registration

### `it(name, fn)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `name` | string | Human-readable test label. |
| `fn` | function | Test body. Throws (via `die`) on failure. |

Registers one test case in the enclosing group. The test is executed in a worker process; any uncaught exception or `die()` call marks it failed.

```js
it("returns the configured hostname", () => {
    assert.eq(get_hostname(), "OpenWrt");
});
```

---

### `skip(name, fn)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `name` | string | Label reported as skipped. |
| `fn` | function | Body. Registered but never called. |

Registers a test that is unconditionally skipped. The test appears in output as skipped rather than being silently omitted.

```js
skip("feature not yet implemented", () => {
    assert.ok(false);
});
```

---

### `xit(name, fn)`

Alias for [`skip`](#skipname-fn). The two are identical.

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `name` | string | Label reported as skipped. |
| `fn` | function | Body. Registered but never called. |

```js
xit("pending", () => { /* … */ });
```

---

## Hooks

### `beforeEach(fn)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `fn` | function | Called before every test in the enclosing group and all descendant groups. |

Registers a setup function that runs before each test in scope. Multiple `beforeEach` calls in the same group execute in registration order.

```js
describe("with state", () => {
    beforeEach(() => { state = new_state(); });
    it("uses fresh state", () => { assert.ok(state); });
});
```

---

### `afterEach(fn)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `fn` | function | Called after every test in the enclosing group and all descendant groups, regardless of test outcome. |

Registers a teardown function that runs after each test in scope. Guaranteed to run even when the test fails. Multiple `afterEach` calls execute in registration order.

```js
describe("with cleanup", () => {
    afterEach(() => { cleanup(); });
    it("is cleaned up even on failure", () => { /* … */ });
});
```

---

### `setup(fn)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `fn` | function | Called once before any test in the file runs. |

Registers a module-level setup function. Must be called at the top level of the file, outside any `describe` block. Only one `setup` per file is permitted.

```js
setup(() => {
    connect_db();
});
```

---

### `teardown(fn)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `fn` | function | Called once after all tests in the file have run. |

Registers a module-level teardown function. Must be called at the top level of the file, outside any `describe` block. Only one `teardown` per file is permitted.

```js
teardown(() => {
    disconnect_db();
});
```
