# How to use combinators with assert.match()

Use combinators to write flexible, composable assertions that go beyond exact equality.

---

## Import combinators

All combinators are exported from `'utest'` alongside the DSL:

```js
import { describe, it, assert, equals, contains, truthy, falsy,
         not, pred, regex, any, any_order } from 'utest';
```

---

## Match a partial object

`contains({...})` passes when the actual object contains at least the listed keys. Extra keys are ignored:

```js
describe('partial object matching', () => {
    it('checks a response without caring about extra fields', () => {
        const response = { code: 200, body: 'ok', latency_ms: 12 };
        assert.match(contains({ code: 200, body: 'ok' }), response);
    });
});
```

Plain object expected values in `assert.match` require **exact** key count. Use `contains` whenever the code under test may return fields you do not need to verify.

---

## Match a substring or array subsequence

`contains` also works on strings and arrays:

```js
// substring
assert.match(contains('24.10'), 'OpenWrt 24.10');

// ordered subsequence — elements must appear in order, not necessarily adjacent
assert.match(contains([1, 3]), [1, 2, 3, 4]);
```

Array elements inside `contains([...])` may themselves be combinators:

```js
assert.match(contains([contains({ id: 1 })]),[{ id: 1, extra: 'ignored' }, { id: 2 }]);
```

---

## Match regardless of array order

`any_order([...])` passes when the actual array has the same elements as the expected array in any order:

```js
assert.match(any_order([1, 2, 3]), [3, 1, 2]);
assert.match(any_order([contains({ name: 'A' }), contains({ name: 'B' })]),[{ name: 'B' }, { name: 'A' }]);
```

The length must match exactly. Use `contains` when you want a subset; use `any_order` when you want all elements without caring about sequence.

---

## Match against a regex

`regex(re)` passes when the actual value is a string matching the pattern:

```js
assert.match(regex(/^utest/), 'utest@v1.2.3');
assert.match(contains({ version: regex(/^\d+\.\d+/) }),{ version: '1.2.3' });
```

---

## Check truthiness or falsiness

`truthy()` and `falsy()` test the truthiness of the actual value:

```js
assert.match(truthy(), is_connected());
assert.match(falsy(), error_code);
assert.match(contains({ success: truthy(), error: falsy() }), result);
```

---

## Invert a combinator

`not(combinator)` passes when the wrapped combinator would fail:

```js
assert.match(not(equals(4)), 5);
assert.match(not(regex(/^\d+/)), 'hello');
assert.match(not(contains({ code: 200 })), { code: 404 });
```

---

## Apply a custom predicate

`pred(fn)` passes when the predicate function returns truthy. Use this when no built-in combinator fits:

```js
assert.match(pred(x => x % 2 == 0), 4);
assert.match(contains([pred(x => x > 2)]), [1, 2, 3]);
```

Pass a message via `assert.match` to make failures readable:

```js
assert.match(pred(t => t > 0), timestamp, 'timestamp must be positive');
```

---

## Use any() as a wildcard

`any()` always passes. Use it to ignore specific fields or positions:

```js
// ignore the id field — only check name
assert.match(contains({ id: any(), name: 'Alice' }), record);

// first element can be anything, second must be 1
assert.match(any_order([any(), 1]), [2, 1]);
```

---

## Compose combinators

Combinators nest freely. Build complex assertions by composing simple ones:

```js
const event = {
    type: 'response',
    payload: {
        code: 200,
        headers: ['content-type: application/json', 'x-request-id: abc']
    }
};

assert.match(contains({
    type: 'response',
    payload: contains({
        code: 200,
        headers: contains(['content-type: application/json'])
    })
}), event);
```

---

## Next steps

- See every combinator's signature: [Reference: Assertions](../reference/assertions.md#combinator-factories)
- Use combinators with mock spy call logs: [How-to: Inspect calls with spy()](spy.md)
- Understand the full `assert.match` semantics: [Reference: Assertions — assert.match](../reference/assertions.md#assertmatchexpected-actual-msg)
