# Contributing your first patch

In this tutorial, we will make a small, self-contained change to the utest framework, write a test for it, update the regression baseline, and verify that the full suite still passes. No prior knowledge of utest internals is assumed.

---

## What we will build

A new combinator factory, `not_null()`, that passes when the actual value is not `null`. We will add it to `src/utest/assert.uc`, re-export it from `src/utest.uc`, cover it with a test in `examples/unit/01_assertions_test.uc`, regenerate the JSON baseline for that example, and confirm that the regression suite is green.

---

## Prerequisites

- **Docker** — both the test runner and the regression suite use Docker. Make sure the daemon is running.
- **git** — to clone the repository and track your change.

---

## Step 1 — Clone the repository

```bash
git clone https://github.com/m00qek/utest.git
cd utest
```

---

## Step 2 — Run the regression suite

Before touching anything, confirm that the baseline is clean:

```bash
make meta-test
```

The script runs every example in `examples/` through the JSON reporter and compares the output against the stored baselines in `test/json/`. A passing run ends with:

```
Verification Started

  ...

SUCCESS: All features verified.
```

If any baseline mismatches, the script prints `FAILURE: Regressions found in: ...` and exits non-zero. Fix those before proceeding.

---

## Step 3 — Add `not_null()`

Open `src/utest/combinators.uc`. This file defines and exports all combinator factories (`equals`, `contains`, `truthy`, `falsy`, and others). Add `not_null` after the `falsy` factory:

```js
export function not_null() {
    return proto({
        match: function(actual) {
            if (actual !== null)
                return { ok: true };
            return { ok: false, message: 'Expected a non-null value' };
        }
    }, Combinator);
};
```

See [Reference: Assertions — Combinator factories](../../reference/assertions.md#combinator-factories) for the full combinator contract. Note the use of `proto({...}, Combinator)` — all combinator factories in this file use the shared `Combinator` prototype so that `is_combinator()` recognises them correctly.

---

## Step 4 — Re-export from `utest.uc`

Open `src/utest.uc`. It re-exports each combinator individually using explicit `export const` statements. Two edits are needed.

First, add `not_null as _not_null` to the destructuring import from `'utest.combinators'`:

```js
// existing combinator import line — add not_null as _not_null to the end
import { equals as _equals, /* … */ is_type as _is_type,
         not_null as _not_null } from 'utest.combinators';
```

Then add the export after the other combinator exports:

```js
export const not_null = _not_null;
```

After both edits, users can import it from `'utest'` as `import { not_null } from 'utest'`.

---

## Step 5 — Write a test for the new combinator

Open `examples/unit/01_assertions_test.uc` and add a new `it` block inside the existing `describe("Assertions", ...)` block:

```js
    it("not_null() passes for non-null values and fails for null", () => {
        assert.match(not_null(),    "hello");
        assert.match(not_null(),         42);
        assert.match(not_null(), { key: 1 });
        assert.throws(
            () => assert.match(not_null(), null),
            /non-null/
        );
    });
```

Update the import at the top of the file to include `not_null`:

```js
import { describe, it, assert, not_null } from 'utest';
```

The full describe block should now look like this:

```js
import { describe, it, assert, not_null } from 'utest';

describe("Assertions", () => {
    it("assert.match() passes for deeply equal values", () => {
        assert.match({ a: 1, b: [2, 3] }, { a: 1, b: [2, 3] });
        assert.throws(() => assert.match(2, 1), /Expected/);
        assert.throws(() => assert.match(2, 1, 'custom'), /custom/);
        assert.throws(() => assert.match({ x: 1, y: 2 }, { x: 1 }), /keys/);
    });

    it("assert.throws() passes when exception is thrown, with optional pattern", () => {
        assert.throws(() => { let x = null; return x.property; }, /null/);
        assert.throws(() => assert.throws(() => {}), /Expected exception/);
        assert.throws(
            () => assert.throws(() => die('boom'), /xyz/),
            /did not match/
        );
    });

    it("not_null() passes for non-null values and fails for null", () => {
        assert.match(not_null(),    "hello");
        assert.match(not_null(),         42);
        assert.match(not_null(), { key: 1 });
        assert.throws(
            () => assert.match(not_null(), null),
            /non-null/
        );
    });
});
```

Run the example once to make sure it passes before regenerating the baseline:

```bash
make test ARGS="examples/unit/01_assertions_test.uc"
```

You should see three passing tests.

---

## Step 6 — Regenerate the baseline

The regression suite compares live JSON output against the files in `test/json/`. Because you added a test, the baseline file is now stale and must be updated:

```bash
make -s test ARGS="-r json examples/unit/01_assertions_test.uc" \
    > test/json/unit/01_assertions_test.json
```

!!! warning
    Pass `-s` (silent) to suppress Make's command echo. Without it, the docker invocation line is captured into the JSON file and corrupts the baseline. Only regenerate baselines for files you intentionally changed.

---

## Step 7 — Run the regression suite again

```bash
make meta-test
```

The suite should end with:

```
SUCCESS: All features verified.
```

If it does, your patch is complete and self-consistent.

---

## What we just built

- A new `not_null()` combinator factory in `src/utest/combinators.uc`.
- A re-export in `src/utest.uc` (import alias + `export const`) so users can import it from `'utest'`.
- A new `it` block in `examples/unit/01_assertions_test.uc` that exercises the new combinator.
- An updated JSON baseline at `test/json/unit/01_assertions_test.json`.
- A full regression run confirming nothing regressed.

---

## Next steps

- Add a proxy for a new OpenWrt subsystem: [How-to: Add a built-in proxy](../../how-to/contributor/add-proxy.md)
- Add a custom reporter: [How-to: Add a reporter](../../how-to/contributor/add-reporter.md)
- Run the regression suite on its own: [How-to: Run the regression suite](../../how-to/contributor/run-regression.md)
