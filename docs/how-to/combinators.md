# How to use combinators with assert.match()

Use combinators to write flexible, composable assertions that go beyond exact equality. This guide covers when to reach for each combinator and how to compose them.

For the full signature of each combinator, see [Reference: Assertions](../reference/assertions.md#combinator-factories).

---

## When to use contains instead of a plain object

A plain object passed to `assert.match` requires an **exact** key count. If the actual value has extra keys, the assertion fails. Use `contains({...})` whenever the code under test may return fields you do not need to verify:

```js
const response = { code: 200, body: 'ok', latency_ms: 12, request_id: 'abc' };

// fails — extra keys not allowed in a plain object match
// assert.match({ code: 200, body: 'ok' }, response);

// passes — extra keys are ignored
assert.match(contains({ code: 200, body: 'ok' }), response);
```

`contains` also works on strings (substring match) and arrays (ordered subsequence):

```js
assert.match(contains('24.10'), 'OpenWrt 24.10');
assert.match(contains([1, 3]), [1, 2, 3, 4]);
```

---

## When to use any_order vs contains for arrays

Use `any_order([...])` when you need all elements present but order varies. Use `contains([...])` when you need a subset in order.

```js
// any_order — same elements, any sequence, exact count
assert.match(any_order([1, 2, 3]), [3, 1, 2]);

// contains — elements must appear in this relative order, others allowed
assert.match(contains([1, 3]), [1, 2, 3, 4]);
```

To match elements by partial structure rather than exact value, nest combinators inside either:

```js
assert.match(any_order([
    contains({ name: 'A' }),
    contains({ name: 'B' })
]), [{ name: 'B', id: 2 }, { name: 'A', id: 1 }]);
```

---

## When to use truthy/falsy instead of exact values

Use `truthy()` and `falsy()` when you care about truth value but not the exact representation:

```js
// avoid — brittle if the function ever returns 1 or "yes" instead of true
// assert.match(true, is_connected());

// prefer
assert.match(truthy(), is_connected());
assert.match(falsy(),  error_code);

// compose inside contains
assert.match(contains({ success: truthy(), error: falsy() }), result);
```

---

## When to use regex for generated or formatted strings

Use `regex(re)` when the value's exact content is not predictable but its shape or content is:

```js
assert.match(regex(/^\d+\.\d+\.\d+/), version_string);
assert.match(contains({ id: regex(/^[0-9a-f]{8}$/) }), record);
```

---

## When to use not

`not(combinator)` is most useful for asserting invariants — values that must never have a certain property:

```js
// a 5xx response must never be ok
assert.match(contains({ ok: not(equals(true)) }), build_response(500, ''));

// a hostname must not be empty
assert.match(not(equals('')), hostname);
assert.match(not(regex(/^\s*$/)), hostname);
```

---

## When to use any() as a wildcard

`any()` always passes. Use it to ignore fields or positions you do not care about:

```js
// only check name — ignore id and timestamp
assert.match(contains({ id: any(), name: 'Alice' }), record);

// first element can be anything; second must be 1
assert.match(any_order([any(), 1]), [2, 1]);
```

---

## When to use has_length, between, and is_type

Use `has_length(n)` to assert the length of a string, array, or object without specifying its contents:

```js
assert.match(has_length(0), errors);                          // empty list
assert.match(contains({ items: has_length(3) }), response);  // nested length
```

Use `between(min, max)` to assert a numeric value falls in a range:

```js
assert.match(between(0, 100), signal_strength);
assert.match(contains({ port: between(1024, 65535) }), config);
```

Use `is_type(t)` to assert the runtime type with a clear failure message. Pass the exact string that ucode's `type()` returns (`'int'`, `'string'`, `'bool'`, `'array'`, `'object'`, `'function'`):

```js
assert.match(is_type('int'),    result);
assert.match(is_type('string'), hostname);
```

---

## When to use starts_with and ends_with

Use `starts_with` and `ends_with` to assert prefixes and suffixes without fixing the full length:

```js
// string prefix / suffix
assert.match(starts_with('ERROR:'), log_line);
assert.match(ends_with('.uc'), filename);

// array prefix / suffix — length of the rest does not matter
assert.match(starts_with(['connect', 'auth']), event_log);
assert.match(ends_with(['done']), pipeline_steps);
```

Elements in the array form accept combinators:

```js
// first element is a connect event, second can be anything
assert.match(starts_with([contains({ type: 'connect' }), any()]), events);

// last element must be an error
assert.match(ends_with([contains({ ok: false })]), results);
```

---

## How to compose combinators into complex assertions

Combinators nest freely. Build complex assertions from simple parts:

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

If no built-in combinator fits, reach for `pred(fn)`:

```js
assert.match(pred(x => x % 2 == 0), value, 'expected even number');
assert.match(contains([pred(x => x > 2)]), items);
```

---

## Next steps

- Full signatures for all combinators: [Reference: Assertions](../reference/assertions.md#combinator-factories)
- Use combinators with mock call logs: [How-to: Inspect calls with spy()](spy.md)
- Learn combinators through a worked example: [Tutorial: Writing flexible assertions with combinators](../tutorials/user/first-combinators.md)
