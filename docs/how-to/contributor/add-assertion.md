# How to add an assertion

Assertions live in a single object exported from `src/utest/assert.uc`. Adding a
new one takes three steps: implement the function, test it, regenerate the
baseline.

---

## 1. Add the function to `assert.uc`

Open `src/utest/assert.uc` and add a new key to the `assert` object. Use `die()`
to signal failure — the runner catches it and records the test as FAIL.

```js
// src/utest/assert.uc  (excerpt)
export const assert = {
    // ... existing assertions ...

    includes: function(haystack, needle, msg) {
        if (type(haystack) != 'array')
            die(sprintf("assert.includes: expected an array, got %s", type(haystack)));
        for (let item in haystack) {
            if (item === needle) return;
        }
        die(msg || sprintf("Expected array to include %s", sprintf('%J', needle)));
    }
};
```

Conventions to follow:

- Accept an optional trailing `msg` parameter for caller-supplied context.
- Prefer `sprintf('%J', value)` to serialise values in error messages — it
  produces compact JSON that is easy to read in output.
- Call `die(message)` for failure. Never `return false` or throw manually.
- Guard unexpected types with an explicit `die()` before the main logic, as
  `assert.matches` and `assert.notMatches` do.

---

## 2. Add a test in the assertions example

Open `examples/unit/01_assertions_test.uc` and add an `it` block that covers
both the passing and the failing case:

```js
// examples/unit/01_assertions_test.uc  (excerpt)
import { describe, it } from 'utest';
import { assert } from 'utest.assert';

describe("Assertions", () => {
    // ... existing tests ...

    it("checks array membership with assert.includes()", () => {
        assert.includes([1, 2, 3], 2);
        assert.throws(
            () => assert.includes([1, 2, 3], 99),
            /Expected array to include/
        );
    });
});
```

Covering both the success path and the failure path in the same test file keeps
the baseline predictable: a broken implementation shows up as a FAIL rather than
as an unexpected exception.

---

## 3. Regenerate the baseline JSON

The regression suite compares json reporter output against a stored baseline.
After changing the test file, update the baseline:

```bash
make -f dev.mk test ARGS="-r json examples/unit/01_assertions_test.uc" \
    > test/json/unit/01_assertions_test.json
```

Then verify the full suite still passes:

```bash
./test/runner.sh
```

---

## Next steps

- Run `./test/runner.sh` to confirm no existing baselines regressed.
- If your assertion requires deep equality, reuse the module-private
  `deep_equal()` helper already present in `assert.uc` rather than writing a
  new recursive comparator.
