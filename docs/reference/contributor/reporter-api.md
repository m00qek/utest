# Reporter API reference

The coordinator reporter API is the interface between the executor and concrete reporter implementations. Reporters extend `ReporterBase` from `src/utest/runner/reporter/base.uc`.

---

## Render hooks

All hooks are optional. `ReporterBase` calls a hook only if the concrete reporter defines it.

| Hook | When called | Argument fields |
| :--- | :--- | :--- |
| `render_suite_start(msg)` | First event from a worker process | `suite`, `bundle`, `count` |
| `render_test_result(msg)` | After each individual test | `suite`, `bundle`, `status`, `error`, `path`, `index` |
| `render_fatal(msg)` | Worker crash, timeout, or run interrupt | `suite`, `bundle`, `error`, `aggregate` |
| `render_suite_end(msg)` | After all tests in a file | `suite`, `bundle`, `duration_ms`, `stats` |
| `render_bundle_start(name)` | Before the first file in a bundle | bundle name string |
| `render_bundle_end(name, duration_ms, stats)` | After the last file in a bundle | name, elapsed ms, aggregate stats |
| `render_summary(ctx)` | Once at the very end | `stats`, `failures`, `results`, `files`, `duration_ms`, `seed` |

---

## `status` values

The `status` field on `render_test_result` messages:

| Value | Meaning |
| :--- | :--- |
| `PASS` | Test body ran and did not throw |
| `FAIL` | `die()` was called (assertion failure) |
| `ERROR` | An unexpected exception was thrown |
| `SKIP` | Test was declared with `skip()` or `xit()` |
| `IGNORE` | Test was excluded by the `-f` regex |

---

## Aggregate stats object

The `stats` object present in `render_bundle_end` and in `ctx.stats` at summary time:

| Field | Type | Description |
| :--- | :--- | :--- |
| `total` | integer | All test results, **including** ignored (the sum of the other test-result counters) |
| `passed` | integer | Tests that passed |
| `failed` | integer | Tests that failed via `die()` (assertion failure) |
| `errors` | integer | Tests that threw unexpectedly (including a strict-mock `die()`) |
| `fatals` | integer | Suites that produced a FATAL event |
| `skipped` | integer | Tests declared with `skip()` or `xit()` |
| `ignored` | integer | Tests filtered out by `-f` |
| `suites` | integer | Number of test files processed (an `aggregate` FATAL does not count) |

The per-suite `stats` passed to `render_suite_end` is keyed on `(bundle, file)`,
so the same file appearing in two bundles gets its own counts rather than
sharing one bucket.

An `aggregate` FATAL (the parallel-run interrupt, `suite: "<parallel run>"`)
carries `aggregate: true`; `render_fatal` receives it like any other FATAL, but
it is not counted toward `suites`.
