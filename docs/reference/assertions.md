# Assertions Reference

The `assert` object and all combinator factories are exported from `'utest'`. Import each symbol by name:

```js
import { assert } from 'utest';                                    // assertion methods
import { contains, truthy, falsy, any } from 'utest';             // combinator factories
// All factories are imported the same way — see the full list below.
```

All assertions call `die()` on failure. They do not return a value. A passing assertion is silent.

---

### `assert.match(expected, actual, msg)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `expected` | any | A combinator, a plain value, or a nested structure mixing both. |
| `actual` | any | Value under test. |
| `msg` | string \| null | Optional failure message overriding the combinator's own message. |

Structural matching assertion. Recursively compares `actual` against `expected`:

- **Combinators** (values returned by the factories below) — delegates to the combinator's own `match` logic.
- **Plain objects** — compared key-for-key with exact key count (no extra keys allowed). Values may themselves be combinators.
- **Plain arrays** — compared element-by-element in order with exact length. Elements may be combinators.
- **Scalars** — compared with deep equality.

```js
import { assert, contains, any_order, any, regex, equals } from 'utest';

// Plain value — deep equality check
assert.match('ok', status);

// Partial object — only listed keys are checked
assert.match(contains({ code: 200 }), response);

// Nested combinators
assert.match(contains({
    code: 200,
    body: contains({ status: 'ok' })
}), response);

// Array with flexible matching
assert.match(any_order([
    contains({ id: 1 }),
    contains({ id: 2 })
]), items);
```

---

### `assert.throws(fn, pattern, msg)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `fn` | function | Function expected to throw. |
| `pattern` | regexp \| null | When provided, the stringified exception must match this pattern. |
| `msg` | string \| null | Optional failure message. |

Fails when `fn` completes without throwing. When `pattern` is given, also fails when the thrown exception's string representation does not match it. The string representation is `sprintf('%s', e)`: for `die("msg")` calls that is the message string directly; for runtime interpreter exceptions (null dereference, type errors, etc.) it is the interpreter error message text — for example, a null dereference produces `"left-hand side expression is null"`.

Failure message format — no exception thrown:
```
<msg or "Expected exception but none was thrown">
```

Failure message format — exception does not match pattern:
```
<msg or "Exception '<e>' did not match pattern <pattern>">
```

```js
assert.throws(() => { die("boom"); });
assert.throws(() => { null.x; }, /null/);
assert.throws(() => load_config("missing.uc"), /not found/, "missing config must throw");
```

---

## Combinator factories

Combinators are composable predicates used with `assert.match`. Import them from `'utest'`:

```js
import { equals, contains, truthy, falsy, not, pred, regex, any, any_order } from 'utest';
```

Each factory returns a combinator object. Combinators can be nested inside each other and inside the plain-value `expected` argument of `assert.match`.

---

### `equals(expected)`

Passes when `actual` is deeply equal to `expected`.

```js
assert.match(equals(42), result);
assert.match(any_order([equals('a'), equals('b')]), tags);
```

A plain scalar passed directly to `assert.match` performs an identical check.

---

### `contains(expected)`

A partial-match combinator with three modes:

- **String `actual`**: passes when `expected` is a substring of `actual`.
- **Array `actual`**: passes when `expected` (an array) is an ordered subsequence of `actual`. Elements of `expected` may themselves be combinators.
- **Object `actual`**: passes when `actual` contains at least all the keys in `expected`, with matching values. Extra keys in `actual` are ignored. Values in `expected` may be combinators.

```js
assert.match(contains("ERROR"), log_line);
assert.match(contains([1, 3]), [1, 2, 3]);
assert.match(contains({ code: 200 }), response);
assert.match(contains({ name: contains('Alice') }), user);
```

---

### `truthy()`

Passes when `actual` is truthy (`true`, non-zero number, non-empty string, object, etc.).

```js
assert.match(truthy(), is_connected);
assert.match(truthy(), items);
```

---

### `falsy()`

Passes when `actual` is falsy (`false`, `null`, `0`, `""`, or `undefined`).

```js
assert.match(falsy(), error_flag);
assert.match(falsy(), m_fs.readfile('/absent'));
```

---

### `not(combinator)`

Inverts a combinator — passes when `combinator` would fail.

```js
assert.match(not(equals(4)), 5);
assert.match(not(regex(/^\d+/)), 'hello');
assert.match(not(contains({ code: 200 })), { code: 404 });
```

---

### `pred(fn)`

Passes when the predicate function `fn(actual)` returns a truthy value.

```js
assert.match(pred(x => x % 2 == 0), 4);
assert.match(contains([pred(x => x > 2)]), [1, 2, 3]);
```

When the predicate fails, the `msg` argument of `assert.match` is used as the failure message if provided; otherwise the default is `"Predicate failed for <value>"`.

```js
assert.match(pred(x => x % 2 == 0), 3, 'expected even');
// → fails with: expected even
```

---

### `regex(re)`

Passes when `actual` is a string that matches the regular expression `re`.

```js
assert.match(regex(/^\d+\.\d+/), version);
assert.match(contains({ message: regex(/connected/) }), log);
```

---

### `any_order(expected)`

Passes when `actual` is an array of the same length as `expected` whose elements match the elements of `expected` in any order.

Elements of `expected` may be plain values (compared with `equals`) or combinators. The matcher backtracks: a wildcard (`any()`) will not permanently block a later specific matcher from claiming its element.

```js
assert.match(any_order([1, 2, 3]), [3, 1, 2]);
assert.match(any_order([
    contains({ type: 'connect' }),
    contains({ type: 'auth' })
]), events);
```

---

### `any()`

Always passes, regardless of what `actual` is. Use it as a wildcard inside larger structures.

```js
assert.match(contains({ id: any(), name: 'Alice' }), record);
assert.match(any_order([any(), 1]), [1, 2]);
```

---

### `starts_with(expected)`

- **String `actual`**: passes when `actual` starts with the string `expected`.
- **Array `actual`**: passes when `actual` has at least as many elements as `expected` and its leading elements match `expected` element-by-element. Elements of `expected` may be plain values (compared with `equals`) or combinators.

```js
assert.match(starts_with('OpenWrt'), 'OpenWrt 24.10');
assert.match(starts_with([1, 2]), [1, 2, 3, 4]);
assert.match(starts_with([any(), 2]), [99, 2, 3]);
```

---

### `ends_with(expected)`

- **String `actual`**: passes when `actual` ends with the string `expected`.
- **Array `actual`**: passes when `actual` has at least as many elements as `expected` and its trailing elements match `expected` element-by-element. Elements of `expected` may be plain values (compared with `equals`) or combinators.

```js
assert.match(ends_with('24.10'), 'OpenWrt 24.10');
assert.match(ends_with([3, 4]), [1, 2, 3, 4]);
assert.match(ends_with([any(), 4]), [1, 2, 3, 4]);
```

---

### `has_length(n)`

Passes when `actual` is a string, array, or object whose `length` equals `n`.

```js
assert.match(has_length(3), [1, 2, 3]);
assert.match(has_length(5), 'hello');
assert.match(contains({ items: has_length(0) }), response);
```

---

### `between(min, max)`

Passes when `actual` is a number in the range `[min, max]` (inclusive).

```js
assert.match(between(0, 100), signal_strength);
assert.match(contains({ port: between(1024, 65535) }), config);
```

---

### `is_type(t)`

Passes when `type(actual) == t`. The type string must match ucode's `type()` return values: `'int'`, `'double'`, `'string'`, `'bool'`, `'array'`, `'object'`, `'function'`.

```js
assert.match(is_type('int'),    result);
assert.match(is_type('string'), hostname);
assert.match(contains({ timeout: is_type('int') }), config);
```

