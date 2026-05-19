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

### `assert.match(str, regex, msg)`

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
assert.match("OpenWrt 24.10", /24\.10/);
assert.match(body, /^{/, "body must be JSON");
```

---

### `assert.notMatch(str, regex, msg)`

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
assert.notMatch(log_output, /ERROR/);
```

---

### `assert.throws(fn, pattern, msg)`

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `fn` | function | Function expected to throw. |
| `pattern` | regexp \| null | When provided, the stringified exception must match this pattern. |
| `msg` | string \| null | Optional failure message. |

Fails when `fn` completes without throwing. When `pattern` is given, also fails when the thrown exception's string representation does not match it.

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
