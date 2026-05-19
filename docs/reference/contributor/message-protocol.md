# Worker ↔ coordinator message protocol reference

Each worker subprocess writes newline-delimited JSON to stdout. The coordinator
reads these lines and routes each object to the appropriate reporter method via
`dispatch()` in `src/utest/runner/executor/base.uc`.

Lines that cannot be parsed as JSON are silently discarded.

---

## SUITE_START

Emitted once per worker, before any test results. Carries the total count of
tests that will run (after filter and skip evaluation).

**Fields**

| Field | Type | Description |
|---|---|---|
| `event` | string | `"SUITE_START"` |
| `suite` | string | Absolute or relative path to the test file |
| `bundle` | string | Name of the bundle this file belongs to |
| `count` | integer | Number of tests that will produce a result in this suite |

**Example**

```js
{"event":"SUITE_START","suite":"examples/unit/01_assertions_test.uc","bundle":"examples/unit/01_assertions_test.uc","count":4}
```

**Coordinator action:** `reporter.suite_start(msg)`

---

## TEST_RESULT

Emitted once per test, in shuffle order.

**Fields**

| Field | Type | Description |
|---|---|---|
| `event` | string | `"TEST_RESULT"` |
| `suite` | string | Path to the test file |
| `bundle` | string | Bundle name |
| `status` | string | One of `PASS`, `FAIL`, `ERROR`, `SKIP`, `IGNORE` |
| `error` | string \| null | Failure message when status is `FAIL` or `ERROR`; `null` otherwise |
| `path` | array | Ordered list of `{id, name}` objects from root group to the test itself |
| `index` | integer | Stable insertion-order index of this test within its suite |

**`status` values**

| Value | Meaning |
|---|---|
| `PASS` | Test body completed without calling `die()` or throwing |
| `FAIL` | `die()` was called (assertion failure); `error` is the message string |
| `ERROR` | An unexpected exception was thrown; `error` is the exception string |
| `SKIP` | Test was declared with `skip()` or `xit()` |
| `IGNORE` | Test path did not match the `--filter` regex |

**`path` element**

| Field | Type | Description |
|---|---|---|
| `id` | integer | Node identifier; `0` denotes the implicit root group |
| `name` | string | Display name of the `describe` group or `it` block |

**Example**

```js
{
  "event": "TEST_RESULT",
  "suite": "examples/unit/01_assertions_test.uc",
  "bundle": "examples/unit/01_assertions_test.uc",
  "status": "PASS",
  "error": null,
  "path": [
    {"id": 0, "name": "root"},
    {"id": 1, "name": "Assertions"},
    {"id": 2, "name": "checks for deep equality with assert.eq()"}
  ],
  "index": 1
}
```

**Coordinator action:** `reporter.test_result(msg)`

---

## SUITE_END

Emitted once per worker, after all TEST_RESULT events.

**Fields**

| Field | Type | Description |
|---|---|---|
| `event` | string | `"SUITE_END"` |
| `suite` | string | Path to the test file |
| `bundle` | string | Bundle name |
| `duration_ms` | integer | Wall-clock time in milliseconds from suite start to suite end |

**Example**

```js
{"event":"SUITE_END","suite":"examples/unit/01_assertions_test.uc","bundle":"examples/unit/01_assertions_test.uc","duration_ms":3}
```

**Coordinator action:** `reporter.suite_end(msg)`

---

## FATAL

Emitted when the worker process itself fails — typically an uncaught exception
during test file loading, or a `setup()` / `teardown()` failure. After a FATAL
the suite produces no TEST_RESULT or SUITE_END events.

The parallel executor also synthesises a FATAL (without a corresponding worker
event) when a worker exceeds the configured timeout.

**Fields**

| Field | Type | Description |
|---|---|---|
| `event` | string | `"FATAL"` |
| `suite` | string | Path to the test file |
| `bundle` | string | Bundle name |
| `error` | string | Human-readable description of the failure |

**Example**

```js
{"event":"FATAL","suite":"examples/unit/06_imports_test.uc","bundle":"examples/unit/06_imports_test.uc","error":"Could not load test file: examples/unit/06_imports_test.uc"}
```

**Coordinator action:** `reporter.fatal(msg)`

---

## Event ordering guarantee

Within a single suite the coordinator always receives events in this order:

1. `SUITE_START` (exactly once)
2. `TEST_RESULT` (zero or more, in shuffled test order)
3. `SUITE_END` (exactly once) — **or** `FATAL` if the worker aborted early

When `--jobs` is greater than 1, events from different suites may be interleaved.
Reporters must use the `suite` field to demultiplex per-file state.

```mermaid
sequenceDiagram
    participant W as Worker
    participant C as Coordinator

    W->>C: SUITE_START {count: N}
    loop 0…N tests
        W->>C: TEST_RESULT {status: PASS|FAIL|ERROR|SKIP|IGNORE}
    end
    alt normal exit
        W->>C: SUITE_END {duration_ms: …}
    else worker aborted (load error, uncaught exception, timeout)
        W->>C: FATAL {error: "…"}
        Note over W,C: no SUITE_END follows a FATAL
    end
```
