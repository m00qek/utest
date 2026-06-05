# How to add a reporter

Add a new output format that users can select with `-r <name>`.

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

See [Reporter API reference](../../reference/contributor/reporter-api.md) for the full hook signatures, status values, and stats object fields.

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

The `type` string is what users pass to `-r` on the command line.

---

## 3. Verify manually

Run the examples with your new reporter to check the output looks correct:

```bash
make test ARGS="-r tap examples/unit/"
```

There is no baseline mechanism for reporters other than `json`. If the reporter
produces machine-readable output (TAP, JUnit XML, etc.) consider adding a
dedicated integration test in `test/` by hand.

---

## Next steps

- Consult hook signatures, status values, and stats fields: [Reporter API reference](../../reference/contributor/reporter-api.md)
- Study `src/utest/runner/reporter/detailed.uc` for an example of colour
  handling using the `colors.uc` helper.
- Study `src/utest/runner/reporter/compact.uc` for an example that buffers
  failure details and prints them after each bundle.
- Read [About the reporter architecture](../../explanation/reporter-architecture.md)
  to understand why two reporters exist and how `ReporterBase` handles stats.
- Read [About the worker/coordinator architecture](../../explanation/worker-coordinator.md)
  to understand when each event fires in relation to subprocess lifecycle.
