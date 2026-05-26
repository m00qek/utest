# Writing flexible assertions with combinators

In this tutorial, we will write tests for a module that returns structured response objects. We will start with exact matching, discover its limits, and progressively replace brittle assertions with combinators. By the end you will have used `contains`, `regex`, `truthy`, `falsy`, `any_order`, and `not`, and you will know how to compose them.

---

## What we will build

A source module `src/response.uc` with a `build_response` helper and a `fetch_pages` aggregator, and a test file `test/unit/response_test.uc` that exercises them. The helper returns objects with known fields alongside generated ones (`id`, `timestamp`), which makes exact matching brittle. Combinators let us assert what matters without specifying what doesn't.

---

## Prerequisites

- Completed [Writing your first test suite](first-test.md). You should be comfortable with `describe`, `it`, `assert.match`, and the `-l` flag.

---

## Step 1 — Create the source module

Write `src/response.uc`:

```js
export function build_response(code, body) {
    return {
        code:      code,
        body:      body,
        ok:        code >= 200 && code < 300,
        id:        sprintf('%08x', rand() & 0xffffffff),  // random hex string
        timestamp: time()                                  // current epoch second
    };
}

export function fetch_pages() {
    let pages = [
        build_response(200, 'home'),
        build_response(404, 'not found'),
        build_response(200, 'about'),
    ];
    // Sort by the randomly-generated id — order varies between runs.
    return sort(pages, (a, b) => a.id < b.id ? -1 : 1);
}
```

---

## Step 2 — Start with exact matching

Create `test/unit/response_test.uc`:

```js
import { describe, it, assert } from 'utest';
import { build_response } from 'response';

describe("build_response()", () => {
    it("returns the expected shape", () => {
        const r = build_response(200, 'hello');
        assert.match({
            code:      200,
            body:      'hello',
            ok:        true,
            id:        r.id,
            timestamp: r.timestamp
        }, r);
    });
});
```

Run it:

```bash
utest -l src test/unit/response_test.uc
```

The test passes. But try removing the `id` and `timestamp` lines from the expected object and run again — the test fails because a plain object match requires an exact key count. We cannot simply omit the generated fields.

---

## Step 3 — Use `contains` to ignore fields you don't control

Replace `test/unit/response_test.uc` with:

```js
import { describe, it, assert, contains } from 'utest';
import { build_response } from 'response';

describe("build_response()", () => {
    it("returns the expected code, body, and ok flag", () => {
        assert.match(contains({ code: 200, body: 'hello', ok: true }), build_response(200, 'hello'));
    });
});
```

Run again:

```bash
utest -l src test/unit/response_test.uc
```

The test passes and is shorter. `contains` checks only the listed keys and ignores the rest. Change `code` to `201` and it fails; change `ok` to `false` and it fails. We are asserting exactly what matters.

---

## Step 4 — Assert the shape of generated fields

We can't know the exact values of `id` or `timestamp`, but we can assert their shapes. Replace the file with:

```js
import { describe, it, assert, contains, truthy, falsy, regex } from 'utest';
import { build_response } from 'response';

describe("build_response()", () => {
    it("returns the expected code, body, and ok flag", () => {
        assert.match(contains({ code: 200, body: 'hello', ok: true }), build_response(200, 'hello'));
    });

    it("ok is truthy for 2xx and falsy for 4xx", () => {
        assert.match(contains({ ok: truthy() }), build_response(200, ''));
        assert.match(contains({ ok: falsy() }),  build_response(404, ''));
    });

    it("id is an 8-character hex string", () => {
        assert.match(contains({ id: regex(/^[0-9a-f]{8}$/) }), build_response(200, ''));
    });
});
```

Run again. All three tests pass.

---

## Step 5 — Test an unordered list with `any_order`

`fetch_pages()` sorts by the randomly-generated `id`, so the element order varies between runs. Replace the file with:

```js
import { describe, it, assert, contains, truthy, falsy, regex, any_order } from 'utest';
import { build_response, fetch_pages } from 'response';

describe("build_response()", () => {
    it("returns the expected code, body, and ok flag", () => {
        assert.match(contains({ code: 200, body: 'hello', ok: true }), build_response(200, 'hello'));
    });

    it("ok is truthy for 2xx and falsy for 4xx", () => {
        assert.match(contains({ ok: truthy() }), build_response(200, ''));
        assert.match(contains({ ok: falsy() }),  build_response(404, ''));
    });

    it("id is an 8-character hex string", () => {
        assert.match(contains({ id: regex(/^[0-9a-f]{8}$/) }), build_response(200, ''));
    });
});

describe("fetch_pages()", () => {
    it("returns all three pages regardless of order", () => {
        assert.match(any_order([
            contains({ code: 200, body: 'home' }),
            contains({ code: 404, body: 'not found' }),
            contains({ code: 200, body: 'about' }),
        ]), fetch_pages());
    });
});
```

`any_order([...])` passes when the actual array contains the same elements as the expected array matched in any order. A plain array assertion would fail whenever the sort order changes; `any_order` removes that brittleness while still verifying that all three responses are present.

Run again. All four tests pass.

---

## Step 6 — Invert a combinator with `not`

A 5xx response must never have `ok: true`. Add `not` and `equals` to the import, then add a new `describe` block at the bottom:

```js
import { describe, it, assert, contains, truthy, falsy, regex, any_order, not, equals } from 'utest';
import { build_response, fetch_pages } from 'response';

describe("build_response()", () => {
    it("returns the expected code, body, and ok flag", () => {
        assert.match(contains({ code: 200, body: 'hello', ok: true }), build_response(200, 'hello'));
    });

    it("ok is truthy for 2xx and falsy for 4xx", () => {
        assert.match(contains({ ok: truthy() }), build_response(200, ''));
        assert.match(contains({ ok: falsy() }),  build_response(404, ''));
    });

    it("id is an 8-character hex string", () => {
        assert.match(contains({ id: regex(/^[0-9a-f]{8}$/) }), build_response(200, ''));
    });
});

describe("fetch_pages()", () => {
    it("returns all three pages regardless of order", () => {
        assert.match(any_order([
            contains({ code: 200, body: 'home' }),
            contains({ code: 404, body: 'not found' }),
            contains({ code: 200, body: 'about' }),
        ]), fetch_pages());
    });
});

describe("build_response() — error status", () => {
    it("5xx response is never ok", () => {
        assert.match(contains({ ok: not(equals(true)) }), build_response(500, 'server error'));
    });
});
```

`not(combinator)` passes when the wrapped combinator would fail. `not(equals(true))` accepts any value that is not exactly `true`. Run one final time:

```bash
utest -l src test/unit/response_test.uc
```

All five tests pass.

---

## What we just built

- A source module `src/response.uc` that exports two functions.
- Used `contains` to assert partial objects, ignoring fields we cannot control.
- Used `regex` to assert the shape of a generated string field.
- Used `truthy()` and `falsy()` to assert truthiness without an exact value.
- Used `any_order` to assert a list whose order varies between runs.
- Used `not` to invert a combinator.
- Composed combinators freely — `contains({ id: regex(...) })` nests two combinators.

---

## Next steps

- See every combinator's full signature: [Reference: Assertions — Combinator factories](../../reference/assertions.md#combinator-factories)
- Apply combinators to mock call logs: [How-to: Inspect calls with spy()](../../how-to/spy.md)
- Go deeper on individual combinators: [How-to: Use combinators with assert.match()](../../how-to/combinators.md)
