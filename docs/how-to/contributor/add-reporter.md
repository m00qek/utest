# How to add a reporter

Reporters format test output for the coordinator process. The coordinator calls
reporter methods as events arrive from workers. Adding a reporter takes three
steps: create the module, register it in the factory, and verify it manually.

---

## 1. Create the reporter module

Create `src/utest/runner/reporter/<name>.uc`. A reporter is a prototype-extended
object that overrides one or more `render_*` hooks from `ReporterBase`. The base
object handles all bookkeeping (stats, failure lists, timing); the reporter
provides only the rendering.

```js
// src/utest/runner/reporter/tap.uc
import { ReporterBase } from 'utest.runner.reporter.base';

export function create() {
    let test_number = 0;

    return proto({
        render_suite_start: function(msg) {
            // msg fields: suite (file path), bundle (bundle name), count (int)
            print("# " + msg.suite + "\n");
        },

        render_test_result: function(msg) {
            // msg fields: suite, bundle, status, error (string|null),
            //             path (array of {id, name}), index (int)
            test_number++;
            let name = msg.path[length(msg.path) - 1].name;
            if (msg.status == "PASS") {
                print("ok " + test_number + " - " + name + "\n");
            } else if (msg.status == "SKIP") {
                print("ok " + test_number + " - " + name + " # SKIP\n");
            } else if (msg.status == "IGNORE") {
                print("ok " + test_number + " - " + name + " # TODO filtered\n");
            } else {
                print("not ok " + test_number + " - " + name + "\n");
                if (msg.error) print("  # " + msg.error + "\n");
            }
        },

        render_fatal: function(msg) {
            // msg fields: suite, bundle, error (string)
            print("Bail out! " + msg.error + "\n");
        },

        render_suite_end: function(msg) {
            // msg fields: suite, bundle, duration_ms, stats (per-suite counts)
            // Optional: print per-file timing.
        },

        render_summary: function(ctx) {
            // ctx fields: stats, failures, results, files, duration_ms, seed
            let s = ctx.stats;
            print("1.." + s.total + "\n");
            print("# duration: " + ctx.duration_ms + " ms\n");
        }
    }, ReporterBase);
};
```

### Render hooks

All hooks are optional. The base class calls them only if they exist.

| Hook | When called | Key fields on argument |
|---|---|---|
| `render_suite_start(msg)` | First event from a test file | `suite`, `bundle`, `count` |
| `render_test_result(msg)` | After each individual test | `suite`, `bundle`, `status`, `error`, `path`, `index` |
| `render_fatal(msg)` | Worker crash or timeout | `suite`, `bundle`, `error` |
| `render_suite_end(msg)` | After all tests in a file | `suite`, `bundle`, `duration_ms`, `stats` |
| `render_bundle_start(name)` | Before the first file in a bundle | bundle name string |
| `render_bundle_end(name, duration_ms, stats)` | After the last file in a bundle | name, elapsed ms, aggregate stats |
| `render_summary(ctx)` | Once at the very end | `stats`, `failures`, `results`, `files`, `duration_ms`, `seed` |

### `status` values in `render_test_result`

| Value | Meaning |
|---|---|
| `PASS` | Test body ran and did not throw |
| `FAIL` | `die()` was called (assertion failure) |
| `ERROR` | An unexpected exception was thrown |
| `SKIP` | Test was marked with `skip()` or `xit()` |
| `IGNORE` | Test was excluded by the `--filter` regex |

### Aggregate stats object

The `stats` object passed to `render_bundle_end` and in `ctx.stats` at summary
time contains: `total`, `passed`, `failed`, `errors`, `fatals`, `skipped`,
`ignored`, `suites`.

---

## 2. Register the reporter in the factory

Open `src/utest/runner/reporter.uc` and add an import and an `else if` branch:

```js
import * as tap_repo from 'utest.runner.reporter.tap';

export function create_reporter(type, use_color, files, seed) {
    let reporter;

    if (type == "compact") {
        reporter = compact.create(use_color);
    } else if (type == "json") {
        reporter = json_repo.create();
    } else if (type == "tap") {
        reporter = tap_repo.create();
    } else {
        reporter = detailed.create(use_color);
    }

    reporter.init(use_color, files, seed);
    return reporter;
};
```

The `type` string is what users pass to `--reporter` on the command line.

---

## 3. Verify manually

Run the examples with your new reporter to check the output looks correct:

```bash
./dev-utest --reporter tap examples/unit/
```

There is no baseline mechanism for reporters other than `json`. If the reporter
produces machine-readable output (TAP, JUnit XML, etc.) consider adding a
dedicated integration test in `test/` by hand.

---

## Next steps

- Study `src/utest/runner/reporter/detailed.uc` for an example of colour
  handling using the `colors.uc` helper.
- Study `src/utest/runner/reporter/compact.uc` for an example that buffers
  failure details and prints them after each bundle.
- Read [About the worker/coordinator architecture](../../explanation/worker-coordinator.md)
  to understand when each event fires in relation to subprocess lifecycle.
