# How to add an assertion

Add a new combinator factory to the combinators module, re-export it from the public entry point, and cover it with a test.

## 1. Add the combinator factory to `combinators.uc`

Open `src/utest/combinators.uc` and add your factory alongside `equals`, `contains`, `truthy`, and the others. Each factory must wrap the returned object with `proto({...}, Combinator)` so that `is_combinator()` recognises it:

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

Conventions:

- Wrap with `proto({...}, Combinator)` — without this, `assert.match` treats the return value as a plain expected object instead of a combinator.
- Return only `{ ok: true }` or `{ ok: false, message: '...' }` from `match` — nothing else.
- Use `sprintf('%J', value)` to serialise values in failure messages.
- Mark the factory `export` so it can be re-exported from `src/utest.uc`.
- Do not accept a `msg` parameter — callers pass custom failure messages as the third argument to `assert.match`.

---

## 2. Re-export from `utest.uc`

Open `src/utest.uc`. Two edits are required.

Add the new name to the existing destructuring import:

```js
import { equals as _equals, /* … */ not_null as _not_null } from 'utest.combinators';
```

Add an export constant after the other combinator exports:

```js
export const not_null = _not_null;
```

---

## 3. Cover both paths in the assertions example

Open `examples/unit/01_assertions_test.uc` and add an `it` block that tests the passing case and the failing case:

```js
it("not_null() passes for non-null values and fails for null", () => {
    assert.match(not_null(), 'hello');
    assert.match(not_null(),      42);
    assert.throws(
        () => assert.match(not_null(), null),
        /non-null/
    );
});
```

Update the import at the top to include the new factory.

---

## 4. Regenerate the baseline and verify

```bash
make -s test ARGS="-r json examples/unit/01_assertions_test.uc" \
    > test/json/unit/01_assertions_test.json

make meta-test
```

---

## Next steps

- See all existing combinator factories: [Reference: Assertions — Combinator factories](../../reference/assertions.md#combinator-factories)
- Run `make meta-test` after every change to catch regressions early.
