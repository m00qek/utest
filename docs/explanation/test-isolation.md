# About test isolation in utest

Test isolation determines how much one test can affect another. utest provides strong isolation between files and practical isolation within a file, but the two levels work differently and the distinction matters when you run into unexpected test interactions.

---

## File-level isolation: separate subprocesses

Each test file runs in its own ucode subprocess — a worker process launched by the coordinator. The coordinator collects results over stdout as JSON lines, then aggregates them into the final report.

This architecture means a crash, an infinite loop, or an unhandled `die()` in one test file cannot corrupt the state of another. The worker process simply exits (or times out), the coordinator records a fatal error for that file, and the remaining files continue normally. This was a deliberate choice: in a firmware testing context, test files often exercise independent subsystems, and a panic in one subsystem should never silence unrelated tests.

---

## Within-file isolation: mock state snapshots

Within a single file, all tests share the same ucode process and therefore the same global scope. They are not isolated in the operating system sense. What utest does instead is snapshot and restore the mock state around each test.

The sequence for each test is:

1. Run all `beforeEach` hooks in order (outermost describe first).
2. Take a snapshot of all current mock state (`mock.snapshot()`).
3. Run the test body.
4. If the test body threw, restore the snapshot immediately — before `afterEach` runs. This guarantees that `afterEach` hooks see clean mock state even when the test leaks a `mock.global.patch()` without a matching `mock.global.unpatch()`.
5. Run all `afterEach` hooks in reverse order (innermost describe first).
6. Restore the full snapshot unconditionally — this cleans up any patches that `afterEach` itself may have set.

The result is that each test starts with the same mock state, regardless of what previous tests did. A test that calls `mock.global.patch('fs', ...)` and then crashes before calling `mock.global.unpatch('fs')` will not leave `fs` patched for the next test.

---

## Why beforeEach and afterEach are scoped to their describe block

`beforeEach` and `afterEach` hooks are inherited from outer describe blocks but not from siblings. A hook registered in a nested `describe` does not run for tests in a different nested `describe` at the same level.

This reflects the mental model that a `describe` block represents a shared context — a set of preconditions that apply to everything inside it. Scoping hooks to their block makes it possible to read a test and understand exactly which hooks will run without scanning the entire file. It also means you can add setup to a subsuite without accidentally affecting sibling suites.

---

## What isolation does not cover

Top-level `let` declarations in a test file persist across all tests in that file. If a test mutates a module-level variable, the next test will see the mutation. This is intentional: `beforeEach` exists precisely to reset that kind of shared state. The pattern is to declare the variable at module level and reset it inside `beforeEach`:

```js
let counter = 0;

describe("my suite", () => {
    beforeEach(() => { counter = 0; });

    it("increments", () => { counter++; assert.eq(counter, 1); });
    it("still starts at zero", () => { assert.eq(counter, 0); });
});
```

If you need true isolation from other tests in the same file, the only mechanism available is the mock snapshot/restore cycle described above. Shared ucode globals — functions, tables, imported module references — are not snapshotted.

---

## Next steps

- Understand how mock.inject() scoping works: [About mock.inject() vs mock.global.patch()](inject-vs-patch.md)
- Use strict mode to catch unintended mock access: [About strict mode](strict-mode.md)
- See the DSL reference for beforeEach and afterEach: [Reference: DSL](../reference/dsl.md)
