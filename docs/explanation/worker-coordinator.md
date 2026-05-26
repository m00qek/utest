# About the worker/coordinator architecture

utest runs each test file in a separate ucode subprocess. Understanding why, and
how the two sides communicate, makes it easier to reason about failures, timeouts,
and reporter output.

---

## Why subprocesses?

ucode has no threads and no exception isolation between modules loaded into the
same interpreter instance. If a test file crashes — an uncaught exception, a
`die()` call outside a test body, a corrupt global — the crash would take the
entire test run with it.

Running each file in its own subprocess means the blast radius of any single
failure is bounded to that file. The coordinator receives a FATAL event, marks
the file as errored, and continues with the remaining files. A crash in
`10_standard_shim_test.uc` cannot prevent `03_aftereach_guarantee_test.uc` from
running.

Subprocess isolation also gives each test file a clean address space. Global
variables, imported module state, and any monkey-patching done by one file
cannot bleed into another file's execution.

---

## How the coordinator discovers files

The coordinator parses each bundle argument from the command line (`[Name:]path`),
expands any directory paths using the active glob pattern, and sorts the resulting
file list for stable ordering.

Before spawning any workers, the coordinator runs the shim generator, which
produces a shim file for every module listed in `config.mocks` and places them in
a temporary directory. That directory is then prepended to every worker's `-L`
module search path so the shims shadow the real modules. See
[Reference: Source layout](../reference/contributor/source-layout.md) for which
modules implement each phase.

---

## How workers are spawned and how output flows back

Each worker is a fresh `ucode` invocation:

```bash
ucode -L <shim_dir> -L <src_dir> -L <cwd> \
      src/utest/runner/worker/bootstrap.uc \
      '{"file":"...","filter":"...","bundle":"...","seed":...}'
```

`bootstrap.uc` receives the JSON argument, loads the test file with
`loadfile()`, then calls `worker_runner.run_tests()`. The worker reporter in
`src/utest/runner/worker/reporter.uc` writes JSON objects to stdout — one per
event, terminated by a newline. The coordinator reads those lines and routes them
to the coordinator-side reporter.

```mermaid
sequenceDiagram
    participant C as Coordinator
    participant W as Worker process

    C->>W: spawn ucode -L … bootstrap.uc '{"file":…}'
    W->>C: {"event":"SUITE_START","count":N}
    loop for each test
        W->>C: {"event":"TEST_RESULT","status":"PASS|FAIL|…"}
    end
    alt normal exit
        W->>C: {"event":"SUITE_END","duration_ms":…}
    else uncaught exception or load failure
        W->>C: {"event":"FATAL","error":"…"}
    end
```

---

## Sequential vs parallel executor

The executor choice is made by `src/utest/runner/executor.uc` based on the
`jobs` configuration key:

**Sequential** (`jobs: 1`, the default): opens each worker with `fs.popen()`,
reads lines from the pipe synchronously, closes the pipe before starting the
next worker. Output arrives in the order tests run. No temporary files are
involved.

**Parallel** (`jobs: N`): launches up to N workers simultaneously using shell
background jobs. Each worker's stdout is redirected to a temporary file in
`$run_dir/pipes/`. The coordinator polls those files in a loop, advancing a
byte offset as new complete lines appear. A `done` sentinel file signals that a
worker has exited. The coordinator enforces a per-worker wall-clock timeout
(default 60 seconds, configurable via `timeout` in `utest.config.uc`); a worker
that exceeds it is killed with `SIGKILL` and a synthetic FATAL event is emitted.

The trade-off: sequential is simpler and produces interleaved output in a single
stream; parallel reduces total wall time for slow test suites but requires
polling and temporary storage.

---

## Why the parallel executor polls at a fixed 50 ms interval

The coordinator wakes every 50 ms to read new output from active workers. The
interval was chosen to balance two constraints: below ~100 ms, reporter output
feels live to a human watching the terminal; above ~5 ms per wake, polling
overhead is negligible on the low-power embedded hardware utest targets. An
event-driven alternative (inotify, FIFOs) would require either a native C
extension or a significantly different worker spawn strategy — both introduce
maintenance cost that the 50 ms interval avoids without any practical
performance difference for realistic test suites.

```mermaid
flowchart TD
    A["executor.uc"] -->|"jobs: 1 (default)"| B["Sequential executor"]
    A -->|"jobs: N"| C["Parallel executor"]

    B --> B1["fs.popen(worker)"]
    B1 --> B2["read lines synchronously"]
    B2 --> B3["close pipe"]
    B3 --> B4{"more files?"}
    B4 -->|yes| B1
    B4 -->|no| DONE["done"]

    C --> C1["spawn up to N workers\n(shell background jobs)"]
    C1 --> C2["poll temp files\nfor new lines"]
    C2 --> C3{"done sentinel\nappeared?"}
    C3 -->|no| C4{"per-worker\ntimeout exceeded?"}
    C4 -->|no| C2
    C4 -->|yes| C5["SIGKILL worker\nsynthesize FATAL"]
    C5 --> C6{"more files?"}
    C3 -->|yes| C6
    C6 -->|yes| C1
    C6 -->|no| DONE
```

---

## The FATAL event

FATAL is the "something went catastrophically wrong" signal. It can originate
from three places:

- **The worker itself** (`bootstrap.uc`): if `loadfile()` fails, or if the test
  file throws an uncaught exception during the module-level evaluation phase, or
  if `setup()` / `teardown()` throws. The worker prints the FATAL JSON line and
  exits with code 1.
- **Timeout** (parallel executor, coordinator side): if a worker exceeds its
  wall-clock timeout, the coordinator kills it with `SIGKILL` and synthesises a
  FATAL event.
- **Spawn failure** (parallel executor, coordinator side): if the worker process
  exits without having produced any valid JSON output — for example because
  `ucode` was not found on `PATH`, or because the worker binary crashed before
  writing anything — the coordinator reads whatever the shell wrote to
  `out_file` and reports it as a FATAL. This distinguishes a spawn failure (zero
  output) from a test file that runs and reports results normally.

After a FATAL, that suite produces no TEST_RESULT or SUITE_END events. Reporters
count fatals separately from errors and failures, and the run exits with a
non-zero code if any fatals occurred.
