# Writing your first test suite

In this tutorial, we will write a utest test suite from scratch, run it, observe a failure, and fix it. By the end you will have a working test file and know how to interpret utest's output.

---

## What we will build

A test file `test/unit/hello_test.uc` that exercises a small arithmetic helper. The suite will contain two tests that check return values with `assert.match`.

---

## Prerequisites

- **Docker** — utest runs inside the official OpenWrt 24.10 image. Install Docker and make sure the daemon is running.
- **GNU make** — used to invoke the Docker-based runner via `make -f dev.mk test`.

You do not need an existing ucode project. You can follow along in any directory that contains the cloned repository.

---

## Step 1 — Create the test file

Create the directory and file:

```bash
mkdir -p test/unit
touch test/unit/hello_test.uc
```

Open `test/unit/hello_test.uc` and add the following:

```js
import { describe, it, assert } from 'utest';

// The function under test — inline here for simplicity.
function add(a, b) {
    return a + b;
}

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
    Everything needed in a test file — DSL functions, assertions, and mocks — is imported from `'utest'`.

---

## Step 2 — Run the suite

```bash
make -f dev.mk test ARGS="test/unit/hello_test.uc"
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

The default reporter is `detailed`. Each test is shown on its own line with a `[PASS]`, `[FAIL]`, `[SKIP]`, or `[ERROR]` prefix.

---

## Step 3 — Introduce a deliberate failure

Change the first test so it expects the wrong value:

```js
    it("returns the sum of two positive numbers", () => {
        assert.match(99, add(2, 3));  // wrong expected value
    });
```

Run again:

```bash
make -f dev.mk test ARGS="test/unit/hello_test.uc"
```

The output now shows what went wrong:

```
[test/unit/hello_test.uc] test/unit/hello_test.uc
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

## Step 4 — Fix it and go green

Restore the correct expected value:

```js
    it("returns the sum of two positive numbers", () => {
        assert.match(5, add(2, 3));
    });
```

Run one more time:

```bash
make -f dev.mk test ARGS="test/unit/hello_test.uc"
```

Both tests pass and the summary shows `Failed: 0`.

---

## What we just built

- A test file that imports everything from `'utest'`.
- A `describe` block containing two `it` tests.
- Two tests using `assert.match` for exact value checks.
- Familiarity with the `detailed` reporter's pass and failure output.

---

## Next steps

- Write flexible assertions for structured data: [Tutorial: Writing flexible assertions with combinators](first-combinators.md)
- Learn to skip tests temporarily: [How-to: Skip tests](../../how-to/skip-tests.md)
- Filter which tests run by name: [How-to: Filter tests by name](../../how-to/filter-tests.md)
- Understand available assertions: [Reference: Assertions](../../reference/assertions.md)
- See the full DSL reference: [Reference: DSL](../../reference/dsl.md)
