# Writing flexible assertions with combinators

In this tutorial, we will write tests for a function that returns structured response objects. We will start with exact matching, discover its limits, and progressively replace brittle assertions with combinators. By the end you will have used `contains`, `regex`, `truthy`, `falsy`, `any_order`, and `not`, and you will know how to compose them.

---

## What we will build

A test file `test/unit/response_test.uc` that exercises a `build_response` helper. The helper returns objects with known fields alongside generated ones (`id`, `timestamp`), which makes exact matching brittle. Combinators let us assert what matters without specifying what doesn't.

---

## Prerequisites

- Completed [Writing your first test suite](first-test.md). You should be comfortable with `describe`, `it`, and `assert.match`.

---

## Step 1 — Create the test file

Create `test/unit/response_test.uc` with the following content:

```js
import { describe, it, assert } from 'utest';

function build_response(code, body) {
    return {
        code:      code,
        body:      body,
        ok:        code >= 200 && code < 300,
        id:        sprintf('%08x', rand() & 0xffffffff),  // random hex string
        timestamp: time()                                  // current epoch second
    };
}

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
make -f dev.mk test ARGS="test/unit/response_test.uc"
```

The test passes. But try changing the `code` in the assert to `201` and run again — it fails as expected. Now try removing the `id` and `timestamp` lines entirely: the test fails because a plain object match requires exact key count. We cannot just omit the generated fields.

---

## Step 2 — Use `contains` to ignore fields you don't control

Replace `test/unit/response_test.uc` with the following:

```js
import { describe, it, assert, contains } from 'utest';

function build_response(code, body) {
    return {
        code:      code,
        body:      body,
        ok:        code >= 200 && code < 300,
        id:        sprintf('%08x', rand() & 0xffffffff),
        timestamp: time()
    };
}

describe("build_response()", () => {
    it("returns the expected code, body, and ok flag", () => {
        assert.match(contains({ code: 200, body: 'hello', ok: true }),build_response(200, 'hello'));
    });
});
```

Run again:

```bash
make -f dev.mk test ARGS="test/unit/response_test.uc"
```

The test passes and is shorter. Change `code` to `201` and it fails; change `ok` to `false` and it fails. We are asserting exactly what matters.

---

## Step 3 — Assert the shape of generated fields

We can't know the exact values of `id` or `timestamp`, but we can assert their shapes. Replace the file with:

```js
import { describe, it, assert, contains, truthy, falsy, regex } from 'utest';

function build_response(code, body) {
    return {
        code:      code,
        body:      body,
        ok:        code >= 200 && code < 300,
        id:        sprintf('%08x', rand() & 0xffffffff),
        timestamp: time()
    };
}

describe("build_response()", () => {
    it("returns the expected code, body, and ok flag", () => {
        assert.match(contains({ code: 200, body: 'hello', ok: true }),build_response(200, 'hello'));
    });

    it("ok is truthy for 2xx and falsy for 4xx", () => {
        assert.match(contains({ ok: truthy() }), build_response(200, ''));
        assert.match(contains({ ok: falsy() }), build_response(404, ''));
    });

    it("id is an 8-character hex string", () => {
        assert.match(contains({ id: regex(/^[0-9a-f]{8}$/) }),build_response(200, ''));
    });
});
```

Run again. All three tests pass.

---

## Step 4 — Test an unordered list with `any_order`

Add a second function that aggregates multiple responses. It sorts by the randomly-generated `id` field, so the order of results varies between runs. Replace the file with:

```js
import { describe, it, assert, contains, truthy, falsy, regex, any_order } from 'utest';

function build_response(code, body) {
    return {
        code:      code,
        body:      body,
        ok:        code >= 200 && code < 300,
        id:        sprintf('%08x', rand() & 0xffffffff),
        timestamp: time()
    };
}

function fetch_pages() {
    // Sort by generated id — order varies between runs.
    let pages = [
        build_response(200, 'home'),
        build_response(404, 'not found'),
        build_response(200, 'about'),
    ];
    return sort(pages, (a, b) => a.id < b.id ? -1 : 1);
}

describe("build_response()", () => {
    it("returns the expected code, body, and ok flag", () => {
        assert.match(contains({ code: 200, body: 'hello', ok: true }),build_response(200, 'hello'));
    });

    it("ok is truthy for 2xx and falsy for 4xx", () => {
        assert.match(contains({ ok: truthy() }), build_response(200, ''));
        assert.match(contains({ ok: falsy() }), build_response(404, ''));
    });

    it("id is an 8-character hex string", () => {
        assert.match(contains({ id: regex(/^[0-9a-f]{8}$/) }),build_response(200, ''));
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

`any_order([...])` passes when the actual array contains the same elements as the expected array, matched in any order. A plain `assert.match` against an array would fail whenever the sort order changes; `any_order` removes that brittleness while still verifying that all three responses are present.

Run again. All four tests pass.

---

## Step 5 — Invert a combinator with `not`

A 5xx response must never have `ok: true`. Add `not` and `equals` to the import, then add a new describe block at the bottom of the file.

Update the import line:

```js
import { describe, it, assert, contains, truthy, falsy, regex, any_order, not, equals } from 'utest';
```

Add this block at the bottom, after the existing `describe("fetch_pages()")` block:

```js
describe("build_response() — error status", () => {
    it("5xx response is never ok", () => {
        assert.match(contains({ ok: not(equals(true)) }),build_response(500, 'server error'));
    });
});
```

`not(combinator)` passes when the wrapped combinator would fail. `not(equals(true))` accepts any value that is not exactly `true`. Run one final time:

```bash
make -f dev.mk test ARGS="test/unit/response_test.uc"
```

All five tests pass.

---

## What we just built

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
