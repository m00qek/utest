# About the reporter architecture

utest uses two separate reporter objects: a worker-side emitter that serialises
events as JSON, and a coordinator-side renderer that turns those events into
human- or machine-readable output. Understanding why they are split, and how the
coordinator-side hook model works, makes the reporter interface easier to reason
about when adding a new output format.

---

## Why two reporters?

Workers run in separate subprocesses. A worker has no direct access to the
coordinator's output stream, and the coordinator has no direct access to a
worker's in-process state. The only communication channel between them is stdout.

The worker-side reporter (`src/utest/runner/worker/reporter.uc`) therefore has a
single job: serialise every significant event — SUITE_START, TEST_RESULT,
SUITE_END, FATAL — as a JSON line to stdout. It knows nothing about formatting,
colour, or output destination. It is not extensible and not intended to be.

The coordinator-side reporter (`src/utest/runner/reporter/`) has the opposite
job: receive those events, accumulate statistics, and render them. This is the
part that users can extend.

The split means that all output formatting is centralised in one process and one
module hierarchy, regardless of how many workers ran in parallel or how their
output was interleaved.

---

## The coordinator-side hook model

The coordinator reporter is built around `ReporterBase`
(`src/utest/runner/reporter/base.uc`). `ReporterBase` handles everything that is
the same for every reporter: counting passes, failures, errors, and skips;
recording which tests failed; tracking wall-clock time; and holding the random
seed for the summary line.

A concrete reporter extends `ReporterBase` via prototype and overrides only the
`render_*` hooks it cares about. `ReporterBase` calls a hook only when the
concrete reporter defines it, so an unimplemented hook is simply skipped — there
is no need to provide a no-op stub.

This design has two consequences:

- A minimal reporter that only shows the summary can implement a single
  `render_summary` hook and ignore everything else.
- Adding a new event type to the coordinator in the future only requires adding
  a new optional hook; existing reporters need no changes.

The available hooks, and the data each receives, are documented in
[Reporter API reference](../reference/contributor/reporter-api.md).

---

## Why `ReporterBase` accumulates stats rather than the concrete reporter

Stats accumulation involves edge cases — double-counting suites, handling FATAL
events that produce no TEST_RESULT lines, distinguishing errors from assertion
failures — that every reporter would have to solve identically. Putting that
logic in `ReporterBase` means a concrete reporter can read `ctx.stats` at summary
time and trust the numbers without reimplementing the accounting.

It also means that the `render_*` hooks receive pre-processed arguments (e.g., a
`stats` object) rather than raw JSON payloads. Concrete reporters work at the
level of what to display, not how to parse events.

---

## See also

- Hook signatures, status values, and stats fields: [Reporter API reference](../reference/contributor/reporter-api.md)
- How to add a new output format: [How-to: Add a reporter](../how-to/contributor/add-reporter.md)
- How workers and the coordinator communicate: [About the worker/coordinator architecture](worker-coordinator.md)
