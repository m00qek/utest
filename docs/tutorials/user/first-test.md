# Writing your first test suite

In this tutorial, we will write a ucode source module, import it from a test file, run the suite, and observe both a passing run and a deliberate failure. By the end you will have a working project layout and know how to interpret utest's output.

---

## What we will build

A source module `src/math.uc` that exports an `add` function, and a test file `test/unit/math_test.uc` that imports and exercises it. We will use the `-l` flag to tell utest where to find the source module.

---

## Prerequisites

- utest installed: `opkg install ucode-utest` (OpenWrt ≤ 24.10) or `apk add ucode-utest` (OpenWrt ≥ 25.12).
- A directory to work in. You do not need an existing ucode project.

---

## Step 1 — Create the source module

Create `src/math.uc`:

```bash
mkdir -p src
```

```js
export function add(a, b) {
    return a + b;
}
```

---

## Step 2 — Create the test file

Create `test/unit/math_test.uc`:

```bash
mkdir -p test/unit
```

```js
import { describe, it, assert } from 'utest';
import { add } from 'math';

describe("add()", () => {
    it("returns the sum of two positive numbers", () => {
        assert.match(5, add(2, 3));
    });

    it("returns a negative result when the sum is negative", () => {
        assert.match(-7, add(-10, 3));
    });
});
```

!!! note
    Everything needed from the test framework — DSL functions, assertions, and mocks — is imported from `'utest'`. Your own modules are imported by name, resolved against the search path.

---

## Step 3 — Run the suite

Pass `-l src` to add `src/` to the module search path so utest can resolve `import { add } from 'math'`:

```bash
utest -l src test/unit/math_test.uc
```

You should see:

```
[test/unit/math_test.uc] test/unit/math_test.uc
  [PASS] returns the sum of two positive numbers
  [PASS] returns a negative result when the sum is negative
Summary:
  Suites: 1
  Total:  2
  Passed: 2
  Failed: 0
  Errors: 0
  Time:   4 ms
  Seed:   ...
```

The default reporter is `detailed`. Each test is shown on its own line with a `[PASS]`, `[FAIL]`, `[SKIP]`, or `[ERROR]` prefix.

---

## Step 4 — Introduce a deliberate failure

Change the first test so it expects the wrong value:

```js
    it("returns the sum of two positive numbers", () => {
        assert.match(99, add(2, 3));  // wrong expected value
    });
```

Run again:

```bash
utest -l src test/unit/math_test.uc
```

The output now shows what went wrong:

```
[test/unit/math_test.uc] test/unit/math_test.uc
  [FAIL] returns the sum of two positive numbers
         Expected 99
           got 5
  [PASS] returns a negative result when the sum is negative
Summary:
  Suites: 1
  Total:  2
  Passed: 1
  Failed: 1
  Errors: 0
  Time:   5 ms
  Seed:   ...
```

`assert.match` prints both the expected and actual values when the check fails, so you can see the mismatch at a glance. The process exits with a non-zero status, which signals failure to CI systems.

---

## Step 5 — Fix it and go green

Restore the correct expected value:

```js
    it("returns the sum of two positive numbers", () => {
        assert.match(5, add(2, 3));
    });
```

Run one more time:

```bash
utest -l src test/unit/math_test.uc
```

Both tests pass and the summary shows `Failed: 0`.

---

## What we just built

- A source module `src/math.uc` that exports a function.
- A test file `test/unit/math_test.uc` that imports and exercises it.
- The `-l src` flag that adds `src/` to the module search path.
- Familiarity with the `detailed` reporter's pass and failure output.

---

## Next steps

- Mock modules your code depends on: [Tutorial: Writing your first mock](first-mock.md)
- Write flexible assertions for structured data: [Tutorial: Writing flexible assertions with combinators](first-combinators.md)
- Learn to skip tests temporarily: [How-to: Skip tests](../../how-to/skip-tests.md)
- Filter which tests run by name: [How-to: Filter tests by name](../../how-to/filter-tests.md)
- Understand available assertions: [Reference: Assertions](../../reference/assertions.md)
- See the full DSL reference: [Reference: DSL](../../reference/dsl.md)
