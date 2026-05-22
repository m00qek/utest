# Assertions Reference

The `assert` object is imported from `'utest.assert'`.

```js
import { assert } from 'utest.assert';
```

All assertions call `die()` on failure. They do not return a value. A passing assertion is silent.

Equality checks use deep structural equality: arrays and objects are compared recursively. Strict type comparison (`===`) is used for scalars. Circular references are handled safely.

---

### `assert.eq(actual, expected, msg)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `actual` | any | Value under test. |
| `expected` | any | Expected value. |
| `msg` | string \| null | Optional failure message. |

Fails when `actual` is not deeply equal to `expected`.

Failure message format:
```
<msg or "Assertion failed">
  Actual:   <JSON of actual>
  Expected: <JSON of expected>
```

```js
assert.eq({ a: 1, b: [2, 3] }, { a: 1, b: [2, 3] });
assert.eq(result, 42, "counter must be 42");
```

---

### `assert.ne(actual, expected, msg)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `actual` | any | Value under test. |
| `expected` | any | Value that `actual` must not equal. |
| `msg` | string \| null | Optional failure message. |

Fails when `actual` is deeply equal to `expected`.

Failure message format:
```
<msg or "Expected values to differ">
  Value: <JSON of actual>
```

```js
assert.ne(status, 'error');
```

---

### `assert.ok(val, msg)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `val` | any | Value that must be truthy. |
| `msg` | string \| null | Optional failure message. |

Fails when `val` is falsy (`false`, `null`, `0`, `""`, or `undefined`).

Failure message format:
```
<msg or "Expected truthy value, got <JSON of val>">
```

```js
assert.ok(is_connected());
assert.ok(length(items) > 0, "items must not be empty");
```

---

### `assert.notOk(val, msg)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `val` | any | Value that must be falsy. |
| `msg` | string \| null | Optional failure message. |

Fails when `val` is truthy.

Failure message format:
```
<msg or "Expected falsy value, got <JSON of val>">
```

```js
assert.notOk(has_error());
```

---

### `assert.matches(str, regex, msg)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `str` | string | String to test. Must be of type `string`; a non-string causes an immediate fatal error. |
| `regex` | regexp | Pattern that `str` must match. |
| `msg` | string \| null | Optional failure message. |

Fails when `str` does not match `regex`.

Failure message format:
```
<msg or "Expected '<str>' to match <regex>">
```

```js
assert.matches("OpenWrt 24.10", /24\.10/);
assert.matches(body, /^{/, "body must be JSON");
```

---

### `assert.notMatches(str, regex, msg)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `str` | string | String to test. Must be of type `string`; a non-string causes an immediate fatal error. |
| `regex` | regexp | Pattern that `str` must not match. |
| `msg` | string \| null | Optional failure message. |

Fails when `str` matches `regex`.

Failure message format:
```
<msg or "Expected '<str>' not to match <regex>">
```

```js
assert.notMatches(log_output, /ERROR/);
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

### `assert.notThrows(fn, msg)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `fn` | function | Function expected to complete without throwing. |
| `msg` | string \| null | Optional failure message. |

Fails when `fn` throws any exception. The exception's string representation is appended to the failure message.

Failure message format:
```
<msg or "Expected no exception but got: <e>">
```

```js
assert.notThrows(() => parse_config(valid_input));
assert.notThrows(() => connect(), "connection must not throw");
```

---

### `assert.contains(haystack, needle, msg)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `haystack` | string \| array | Value to search within. Must be a string or array; any other type causes an immediate fatal error. |
| `needle` | string \| any | Substring to find (when `haystack` is a string), or element to find (when `haystack` is an array). Array element comparison uses deep structural equality. |
| `msg` | string \| null | Optional failure message. |

Fails when `needle` is not found in `haystack`.

Failure message format — string:
```
<msg or "Expected string to contain '<needle>'">
```

Failure message format — array:
```
<msg or "Expected array to contain <JSON of needle>">
```

```js
assert.contains("OpenWrt 24.10", "24.10");
assert.contains(interfaces, "eth0", "eth0 must be listed");
assert.contains(results, { status: "ok" });
```

---

### `assert.match(actual, expected, msg)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `actual` | any | Value under test. |
| `expected` | any | A combinator, a plain value, or a nested structure mixing both. |
| `msg` | string \| null | Optional failure message overriding the combinator's own message. |

Structural matching assertion. Recursively compares `actual` against `expected`:

- **Combinators** (values returned by the factories below) — delegates to the combinator's own `match` logic.
- **Plain objects** — compared key-for-key with exact key count (no extra keys allowed). Values may themselves be combinators.
- **Plain arrays** — compared element-by-element in order with exact length. Elements may be combinators.
- **Scalars** — compared with deep equality.

```js
import { assert } from 'utest.assert';
import { has, contains, any_order, any, matches, equals } from 'utest';

// Plain value — behaves like assert.eq
assert.match(status, 'ok');

// Partial object — only listed keys are checked
assert.match(response, has({ code: 200 }));

// Nested combinators
assert.match(response, has({
    code: 200,
    body: has({ status: 'ok' })
}));

// Array with flexible matching
assert.match(items, any_order([
    has({ id: 1 }),
    has({ id: 2 })
]));
```

---

## Combinator factories

Combinators are composable predicates used with `assert.match`. Import them from `'utest'`:

```js
import { equals, contains, has, any_order, any, matches } from 'utest';
```

Each factory returns a combinator object. Combinators can be nested inside each other and inside the plain-value `expected` argument of `assert.match`.

---

### `equals(val, msg)`

Passes when `actual` is deeply equal to `val`.

```js
assert.match(result, equals(42));
assert.match(tags, any_order([equals('a'), equals('b')]));
```

Plain scalars inside `assert.match` behave identically — `equals` is most useful inside other combinators.

---

### `contains(val, msg)`

Passes when `actual` contains `val`.

- When `actual` is a **string**: passes when `val` is a substring.
- When `actual` is an **array**: passes when any element is deeply equal to `val`.

```js
assert.match(log_line, contains("ERROR"));
assert.match(items, contains({ id: 3 }));
```

---

### `has(obj, msg)`

Passes when `actual` is an object that contains at least all the keys in `obj`, with matching values. Extra keys in `actual` are ignored.

Values in `obj` may be plain values (compared with `equals`) or nested combinators.

```js
assert.match(response, has({ code: 200 }));
assert.match(user, has({ role: 'admin', name: contains('Alice') }));
```

---

### `any_order(arr, msg)`

Passes when `actual` is an array of the same length as `arr` whose elements match the elements of `arr` in any order.

Elements of `arr` may be plain values (wrapped in `equals`) or combinators. Matching is greedy: each matcher claims the first element it matches.

```js
assert.match(result, any_order([1, 2, 3]));
assert.match(events, any_order([
    has({ type: 'connect' }),
    has({ type: 'auth' })
]));
```

---

### `any(msg)`

Always passes, regardless of what `actual` is. Use it as a wildcard inside larger structures.

```js
assert.match(record, has({ id: any(), name: 'Alice' }));
```

---

### `matches(re, msg)`

Passes when `actual` is a string that matches the regular expression `re`.

```js
assert.match(version, matches(/^\d+\.\d+/));
assert.match(log, has({ message: matches(/connected/) }));
```
