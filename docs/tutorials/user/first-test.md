# Writing your first test suite

In this tutorial, we will write a utest test suite from scratch, run it, observe a failure, and fix it. By the end you will have a working test file and know how to interpret utest's output.

---

## What we will build

A test file `test/unit/hello_test.uc` that exercises a small arithmetic helper. The suite will contain two tests: one that checks a return value with `assert.eq`, and one that checks a condition with `assert.ok`.

---

## Prerequisites

- **Docker** — utest runs inside the official OpenWrt 24.10 image. Install Docker and make sure the daemon is running.
- The `dev-utest` wrapper at the root of the project. If you have just cloned the repository it is already there.

You do not need an existing ucode project. You can follow along in any directory that contains the `dev-utest` script.

---

## Step 1 — Create the test file

Create the directory and file:

```bash
mkdir -p test/unit
touch test/unit/hello_test.uc
```

Open `test/unit/hello_test.uc` and add the following:

```js
import { describe, it } from 'utest';
import { assert } from 'utest.assert';

// The function under test — inline here for simplicity.
function add(a, b) {
    return a + b;
}

describe("add()", () => {
    it("returns the sum of two positive numbers", () => {
        assert.eq(add(2, 3), 5);
    });

    it("returns a negative result when the sum is negative", () => {
        assert.ok(add(-10, 3) < 0);
    });
});
```

!!! note
    All DSL functions (`describe`, `it`, etc.) are imported from `'utest'`. All assertion functions come from `'utest.assert'`.

---

## Step 2 — Run the suite

```bash
./dev-utest test/unit/hello_test.uc
```

utest pulls the OpenWrt Docker image on first use, then runs your tests inside it. You should see output similar to the following:

```
[test/unit/hello_test.uc] test/unit/hello_test.uc
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

The default reporter is `detailed`. Each test is shown on its own line with a `[PASS]`, `[FAIL]`, `[SKIP]`, or `[ERR!]` prefix.

---

## Step 3 — Introduce a deliberate failure

Change the first test so it expects the wrong value:

```js
    it("returns the sum of two positive numbers", () => {
        assert.eq(add(2, 3), 99);  // wrong expected value
    });
```

Run again:

```bash
./dev-utest test/unit/hello_test.uc
```

The output now shows what went wrong:

```
[test/unit/hello_test.uc] test/unit/hello_test.uc
  [FAIL] returns the sum of two positive numbers
         Assertion failed
           Actual:   5
           Expected: 99
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

`assert.eq` prints both the actual and expected values when the check fails, so you can see the mismatch at a glance. The process exits with a non-zero status, which signals failure to CI systems.

---

## Step 4 — Fix it and go green

Restore the correct expected value:

```js
    it("returns the sum of two positive numbers", () => {
        assert.eq(add(2, 3), 5);
    });
```

Run one more time:

```bash
./dev-utest test/unit/hello_test.uc
```

Both tests pass and the summary shows `Failed: 0`.

---

## What we just built

- A test file that imports from `'utest'` and `'utest.assert'`.
- A `describe` block containing two `it` tests.
- One test using `assert.eq` for an exact value check.
- One test using `assert.ok` for a condition check.
- Familiarity with the `detailed` reporter's pass and failure output.

---

## Next steps

- Learn to skip tests temporarily: [How-to: Skip tests](../../how-to/skip-tests.md)
- Filter which tests run by name: [How-to: Filter tests by name](../../how-to/filter-tests.md)
- Understand available assertions: [Reference: Assertions](../../reference/assertions.md)
- See the full DSL reference: [Reference: DSL](../../reference/dsl.md)
