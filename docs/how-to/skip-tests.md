# How to skip tests temporarily

Mark a test or an entire describe block as skipped so it is excluded from the current run without being deleted from the source.

---

## Skip a single test

Replace `it()` with `skip()` or its alias `xit()`. Both are equivalent — use whichever reads more naturally in context:

```js
import { describe, it, skip, xit } from 'utest';
import { assert } from 'utest.assert';

describe("Authentication", () => {
    it("works with valid credentials", () => {
        assert.ok(true);
    });

    skip("works with OAuth2 (not implemented yet)", () => {
        // This body is never executed.
        assert.ok(false);
    });

    xit("handles MFA (coming soon)", () => {
        assert.ok(false);
    });
});
```

The test body is registered but never called. You can leave failing assertions, incomplete stubs, or plain comments inside — none of it runs.

---

## Skip an entire describe block

Use `xdescribe()` instead of `describe()` to register every test inside the block as skipped:

```js
import { describe, it, xdescribe } from 'utest';
import { assert } from 'utest.assert';

describe("Stable feature", () => {
    it("works", () => {
        assert.ok(true);
    });
});

xdescribe("Experimental feature", () => {
    it("does something unfinished", () => {
        assert.ok(false);
    });

    it("does something else unfinished", () => {
        assert.ok(false);
    });
});
```

All tests inside `xdescribe` are skipped, including any in nested `describe` blocks.

---

## Read the output

Skipped tests appear as `[SKIP]` in the detailed reporter and are counted separately in the summary. They are never counted as failures:

```
  [PASS] works with valid credentials
  [SKIP] works with OAuth2 (not implemented yet)
  [SKIP] handles MFA (coming soon)
Summary:
  Total:   3
  Passed:  1
  Skipped: 2
  Failed:  0
```

---

## Next steps

- Run only a specific subset of tests without modifying source: [How-to: Filter tests by name](filter-tests.md)
- Understand how tests are isolated from each other: [About test isolation](../explanation/test-isolation.md)
- See the full DSL reference: [Reference: DSL](../reference/dsl.md)
