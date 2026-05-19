# Contributing your first patch

In this tutorial, we will make a small, self-contained change to the utest framework, write a test for it, update the regression baseline, and verify that the full suite still passes. No prior knowledge of utest internals is assumed.

---

## What we will build

A new assertion, `assert.notNull`, that is an alias for the existing `assert.ok`. We will add it to `src/utest/assert.uc`, cover it with a test in `examples/unit/01_assertions_test.uc`, regenerate the JSON baseline for that example, and confirm that the regression suite is green.

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
./test/runner.sh
```

The script runs every example in `examples/` through the JSON reporter and compares the output against the stored baselines in `test/json/`. A passing run ends with:

```
Verification Started

  ...

SUCCESS: All features verified.
```

If any baseline mismatches, the script prints `FAILURE: Regressions found in: ...` and exits non-zero. Fix those before proceeding.

---

## Step 3 — Add `assert.notNull`

Open `src/utest/assert.uc`. The file exports a single `assert` object. Find the `notOk` function near the end of the object literal:

```js
    notOk: function(val, msg) {
        if (val) {
            die(msg || sprintf("Expected falsy value, got %s", sprintf('%J', val)));
        }
    },
```

Add `notNull` immediately after it, before the closing `notMatch` entry:

```js
    notOk: function(val, msg) {
        if (val) {
            die(msg || sprintf("Expected falsy value, got %s", sprintf('%J', val)));
        }
    },

    notNull: function(val, msg) {
        if (!val) {
            die(msg || sprintf("Expected non-null value, got %s", sprintf('%J', val)));
        }
    },
```

`assert.notNull` behaves identically to `assert.ok` — it fails when `val` is falsy. The separate name makes tests more readable when the intent is specifically to check that a value is not `null`.

!!! note
    `assert.ok` and `assert.notNull` share the same runtime behaviour. Adding a dedicated name is a documentation and readability choice, not a logic change.

---

## Step 4 — Write a test for the new assertion

Open `examples/unit/01_assertions_test.uc` and add a new `it` block inside the existing `describe("Assertions", ...)` block:

```js
    it("checks for non-null values with assert.notNull()", () => {
        assert.notNull("hello");
        assert.notNull(42);
        assert.notNull({ key: "value" });
    });
```

The full describe block should now look like this:

```js
describe("Assertions", () => {
    it("checks for deep equality with assert.eq()", () => {
        const actual = { a: 1, b: [2, 3] };
        const expected = { a: 1, b: [2, 3] };

        assert.eq(actual, expected, "Objects should be deeply equal");
    });

    it("checks for truthiness with assert.ok()", () => {
        assert.ok(true);
        assert.ok(length("hello") > 0);
        assert.ok({ some: "data" });
    });

    it("matches strings against regex with assert.match()", () => {
        assert.match("OpenWrt 24.10", /24\.10/);
        assert.match("utest@v1.0.0", /^utest/);
    });

    it("verifies exceptions with assert.throws()", () => {
        const block = () => {
            let x = null;
            return x.property;
        };

        assert.throws(block, /left-hand side is not a function|null/);
    });

    it("checks for non-null values with assert.notNull()", () => {
        assert.notNull("hello");
        assert.notNull(42);
        assert.notNull({ key: "value" });
    });
});
```

Run the example once to make sure it passes before regenerating the baseline:

```bash
./dev-utest examples/unit/01_assertions_test.uc
```

You should see five passing tests.

---

## Step 5 — Regenerate the baseline

The regression suite compares live JSON output against the files in `test/json/`. Because you added a test, the baseline file is now stale and must be updated:

```bash
./dev-utest --reporter json examples/unit/01_assertions_test.uc \
    > test/json/unit/01_assertions_test.json
```

!!! warning
    Only regenerate baselines for files you intentionally changed. Regenerating an unrelated baseline can hide regressions.

---

## Step 6 — Run the regression suite again

```bash
./test/runner.sh
```

The suite should end with:

```
SUCCESS: All features verified.
```

If it does, your patch is complete and self-consistent.

---

## What we just built

- A new `assert.notNull` entry in `src/utest/assert.uc`, added after `notOk`.
- A new `it` block in `examples/unit/01_assertions_test.uc` that exercises the new assertion.
- An updated JSON baseline at `test/json/unit/01_assertions_test.json`.
- A full regression run confirming nothing regressed.

---

## Next steps

- Add a proxy for a new OpenWrt subsystem: [How-to: Add a built-in proxy](../../how-to/contributor/add-proxy.md)
- Add a custom reporter: [How-to: Add a reporter](../../how-to/contributor/add-reporter.md)
- Run the regression suite on its own: [How-to: Run the regression suite](../../how-to/contributor/run-regression.md)
