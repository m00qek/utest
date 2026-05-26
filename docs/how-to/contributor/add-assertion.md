# How to add an assertion

The correct extension point for new assertions is a **combinator factory** exported from `src/utest/assert.uc`. Combinators integrate with `assert.match` and compose freely with all existing combinators.

For a step-by-step walkthrough of adding a combinator from scratch, see [Tutorial: Contributing your first patch](../../tutorials/contributor/first-patch.md).

---

## 1. Add the combinator factory to `assert.uc`

Open `src/utest/assert.uc` and add your factory alongside `equals`, `contains`, `truthy`, and the others. Each factory returns an object with a `match(actual)` method:

```js
export function not_null() {
    return {
        match: function(actual) {
            if (actual !== null)
                return { ok: true };
            return { ok: false, message: 'Expected a non-null value' };
        }
    };
}
```

Conventions:

- Return only `{ ok: true }` or `{ ok: false, message: '...' }` — nothing else.
- Use `sprintf('%J', value)` to serialise values in failure messages.
- Mark the factory `export` so it can be re-exported from `src/utest.uc`.
- Do not accept a `msg` parameter — callers pass custom failure messages as the third argument to `assert.match`.

---

## 2. Re-export from `utest.uc`

Open `src/utest.uc`. Two edits are required.

Add the new name to the existing destructuring import on line 4:

```js
import { assert as _assert, equals as _equals, /* … */ not_null as _not_null } from 'utest.assert';
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
make -f dev.mk test ARGS="-r json examples/unit/01_assertions_test.uc" \
    > test/json/unit/01_assertions_test.json

make -f dev.mk meta-test
```

---

## Next steps

- See all existing combinator factories: [Reference: Assertions — Combinator factories](../../reference/assertions.md#combinator-factories)
- Run `make -f dev.mk meta-test` after every change to catch regressions early.
