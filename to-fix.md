# Open items — after the clear-path batch on the 2026-07-03 (ff86ebc) review

The second full review (four-reviewer panel at `ff86ebc`; full report in git
history at commit `32509c5`) is mostly landed. This file now tracks only what
remains open. **Suite health:** `make meta-test` fully green — 451 PASS / 0 FAIL.

---

# Third review (2026-07-04, four-reviewer panel @ `1b04b7c`)

Beat grades: core library **A-**, mock subsystem **B-**, runner/orchestration
**B+**, tests/infra **A-**. Overall **B+**. All HIGHs and the headline MEDIUMs
were probe-confirmed against the real interpreter (seal breach, guard escape,
musl buffering, and contains() asymmetry re-verified independently by the lead).

## R3.3 LANDED (`7eb8d43`) — second-order object guard

The 2.4 guard covered only a proxy's own top-level methods; the objects those
methods return (fs open() handles, uci cursors, ubus connections, uclient
handles) close over the raw ctx and were unguarded, so a leaked handle's close()
polluted reg.global. Fixed at the chokepoint they all share: liveness is threaded
into ctx (`build_proxy`/`context` take `is_live`) and every state-touching ctx
method is gated, so any use after scope-end dies. Both guards share one predicate
per scope — inject reuses the live cell; global.patch keys on proxy identity
(late-bound), which survives snapshot()/restore() (restore preserves the proxy
ref) where a reg.global-identity check would not. spy()-on-stale was the one gap
this didn't auto-close (spy reads `__utest__` directly, not ctx) — see R3.16.

## R3.2 LANDED (`00aaa61`) — fs destructive-op seal

The fs mock now seals the six filesystem-mutating ops it does not model — `rmdir`,
`symlink`, `chown`, `chdir`, `mkdtemp`, `mkstemp` — so a call under an active mock
dies (both modes) instead of falling through to the real fs, unless a `behavior:`
override is supplied. Read-only fall-throughs (lstat/readlink/realpath/opendir)
are left alone (that's R3.6, fidelity not safety). **Follow-up:** uci/ubus have the
same generic non-strict fall-through-to-real class (an unmocked `cursor().commit()`
or real `ubus.call()`), lower-frequency and untracked — consider a general stance.

## Green-light batch LANDED (`eb86d89`..`21cb9b6`, meta-test green)

Mechanical / no-decision fixes, each with a regression test where testable:
**R3.1** worker reporter flushes stdout per event (partial results survive the
timeout kill; pinned via the hang fixture + `-s 7`). **R3.5** ubus/uclient replies
deep-cloned. **R3.7** mock glob sorted. **R3.8** unexpected missing baseline now
fails meta-test. **R3.9** meta-test.sh cd's to PROJECT_ROOT. **R3.11** shrink
budget cap honoured. **R3.13** integer size/count generator options validated.
**R3.14** persist id-mismatch guard. **R3.17** utest.sh traps INT/TERM/HUP.
**R3.21** mkdocs nav orphans + stale doc/comment refs. Plus nits: between()
reversed-bounds guard, forall runs>=1, uloop.done() per bundle, seed_from_clock
reuse, replayed-report seed qualifier.

## Simple-decisions batch LANDED (`4c6fff7`..`22e2718`, meta-test green)

- **R3.4** (decision: subsequence everywhere) — `contains()` now matches a nested
  array as a subsequence and a nested object as a key-subset at every level,
  whether inside an array or an object; wrap in `equals()` for exact.
  `contains_array` forward-declared for the mutual recursion.
- **R3.12** (decision: die at declaration) — it/describe/beforeEach/afterEach
  validate the callback is a function at declaration (it points at skip()).
- **R3.18** (decision: leave documented) — cross-referenced comments at both kill
  sites explain the SIGKILL(-jN)/SIGTERM+143(-j1) split; no behavior change.
- **R3.20** (decision: add both) — public `assert.fail(msg)` (FAIL-classified) and
  umbrella `is_combinator` re-export.

## R3.6 LANDED (`9412711`, meta-test green) — fs read-side family

`lstat`/`readlink`/`realpath`/`opendir` were never overridden, so `ctx.base()`
wrapped them with `make_behavior_fn`: during an active mock they fell through to
the REAL fs (non-strict) or died "not mocked" even for a known path (strict) — a
mocked path stat'd as a file but lstat'd as null. Now modeled against the same
data channel as stat/lsdir: lstat==stat (no symlinks; symlink is sealed), readlink
returns null for any known path, realpath canonicalizes `.`/`..` (new
`normalize_path`) and confirms existence, opendir serves the merged listing via a
cursor handle (read/tell/seek/close/error). `stat_of()`/`list_dir()` factor the
shared logic; each honours a `behavior:` override, records for spy(), and
strict-dies on a wholly unknown path. Also fixed `stat().type` to the real fs
vocabulary (`'file'`, not `'regular'`) so a SUT switching on it matches live —
11_mocking_fs updated (the value isn't embedded in the PASS baseline, so no regen),
fidelity coverage added to 27_mock_fidelity.

## R3.10 LANDED (`bd0755b`, meta-test green) — top-level schema pin

verify.uc compared stats/results/failures/bundles but never the run-level key
*set* or `files[]`, so baselines drifted into three vintages (with/without
duration_ms/seed) undetected and a dropped/renamed top-level key would pass
silently. Added three checks: Schema keys (scrubbed top-level key set matches),
Run metadata (duration_ms + seed still emitted — asserted on live output only),
and Files (discovered list, sorted). **No baseline churn:** the key set is
compared after `normalize` scrubs duration_ms/seed, so all three vintages pass
as-is. Negative-tested (missing files / corrupted files / extra key all fail).

## R3.16 / R3.19 LANDED (`816c768`, `840ef9d`, meta-test green)

- **R3.16** (spy-on-stale) — `guard_proxy` now carries the scope-liveness
  predicate on `__utest__`, and `spy()` gates its live registry lookup on it: a
  proxy used past its inject()/patch() scope dies with "used outside its scope"
  instead of silently reporting the current (empty global) layer's calls. Inner
  objects and unguarded proxies are unaffected (no `is_live`). Test in
  17_spy_test.uc covers both a leaked inject proxy and a post-unpatch proxy.
- **R3.19** (error-path coverage) — meta-test now pins two gaps: `assert_cli_error`
  also checks an unknown flag (`-Z`) and a missing `-c` config; and a new
  `examples/loadfail/broken_import.uc` fixture (outside the `*_test.uc` discovery
  glob, so no baseline) verifies a compile/load failure surfaces as a clean FATAL
  with non-zero exit and no runner stack trace. Complements 22_fatal_setup (the
  later runtime setup-fatal path).

## R3.15 LANDED (`d376852`, meta-test green) — uloop timer handle

The mock's `timer()` returned nothing, so a SUT storing its timer to reschedule
or cancel it crashed on a null handle, only under test. Now returns a handle
mirroring the real uloop.timer resource: `remaining()` (the armed deadline, or -1
once cancelled — the mock has no clock), `cancel()` (marks the handle dead;
run() skips it), `set(ms)` (re-arms, clearing a prior cancel). The handle is
stored in the timer queue by reference (channel get/set don't clone), so run()
filters cancelled handles and sorts on each handle's CURRENT ms — a set() before
run() reschedules correctly, and the deadline-order + registration tiebreak is
preserved. Both mutators return the handle for chaining. Single-pass semantics
unchanged (a callback-armed/re-armed timer still needs another run()). Coverage
in 14_uloop_test.

## Still open — NIT

- manager.uc shim gen: exported names assumed to be valid identifiers
  (`export const delete = …` won't compile); dotted module names with `..`
  escape run_dir (PLAUSIBLE, robustness not security).
- fs write-mode edges: `open(p,'w')` truncates only at close; `r+`/`w+` writes
  discarded; `readfile(p, size)` ignores size; handles lack seek/tell/flush.
  Negated-class trailing `-` escape wrongly excludes `\` (backslash filenames).
  `mkdir()` returns true but leaves no stat-able trace; uci `delete()` of a
  missing section returns true.
- `elapsed_ms` int division (name implies float — left as-is; ms integers are
  fine, changing the format is debatable). busybox "Terminated" noise in -j1
  timeout output; slow1/slow2 burn 4s of sleep per meta-test; build-package.sh
  `chmod 777`.

## Panel verdicts on the standing questions

- **Performance**: measured ~8.7 ms/suite at -j1 in-container; -jN scales
  near-linearly to 8 workers (209→33 ms over 24 suites); file-redirect I/O
  design sound; no perf defects found.
- **uloop**: keep the split. Parallel uloop usage is idiomatic (init/process/
  timer/end lifecycle traced clean); -j1 without uloop keeps the module a soft
  dependency (works on minimal images) and provides live streaming. Converge
  semantics (flush R3.1, signal R3.18), not machinery.

## Landed in this batch (12 commits, `6fd8ff2`..`d0f2188`)

All §1 correctness defects except the 1.15 nit, plus the readability sweep and
three test-coverage additions:

- **1.1** parallel workers inherit the parent env via `getenv()` (+ env-probe
  fixture run under -j1 and -j2, gap 3.1); false comment fixed (4.3).
- **1.2 / 1.9** `is_event` validates path *elements* (object with string `name`)
  and requires a known `status`.
- **1.3** ^C stops the whole multi-bundle run (parallel executor returns an
  interrupted flag; runner breaks the bundle loop).
- **1.4 / 1.4b** `gen.int` requires integer bounds (kills NaN + double bounds).
- **1.5** fs seal follow-through: `unlink` reality-probe, append overlay-read.
- **1.6** `lsdir` dies under strict for an unmocked dir; returns `[]` (not null)
  for an emptied dir. `glob` left as a search (empty is valid), documented.
- **1.7** uloop mock fires timers by deadline, tie-broken on registration order.
- **1.8** uci `get`/`get_all`/`foreach` return deep copies, not live references
  (exposed `engine.deep_clone` as `ctx.clone()`).
- **1.10** durations use `clock(true)` (monotonic) via `util.mono_clock()`.
- **1.11** interrupt FATAL no longer inflates the suite count (aggregate flag).
- **1.12** `-j`/`-s`/config `reporter` coercions validated; default seed via
  `seed_from_clock` (4.1).
- **1.13** `gen.float` always returns a double.
- **1.14** `equals()` unwraps a top-level combinator.
- **2.1** unknown state keys rejected, channel-aware (allowlist =
  `{behavior, strict}` ∪ `get_proxy_channels`, so fs's `commands` is accepted).
- **2.6** `assert.throws` no longer swallows a nested assertion failure or
  property sentinel — rejected unless a supplied pattern matches it.
- **2.3** `deep_clone` dies cleanly on cyclic data (ancestor-tracking; DAGs
  still clone). **2.5** uloop timer queue moved to its own `timers` channel.
- **2.7** combinator pattern rendered as a label, not a serialized object.
  **2.8** `equals(NaN)` explains NaN never compares equal. **2.9** ambiguous
  keys rendered as quoted brackets. **2.12** Seed line notes it reproduces the
  original value. **2.13** shim name emitted as a `%J` literal.
- **2.2 / 2.2b** glob mock matches real glob(3), verified against the interpreter:
  `**` is no longer globstar, and character classes (`[abc]`, ranges, `[!..]`/
  `[^..]` negation, literal leading `]`) are honored via a proper glob→regex parser.
- **2.4** a proxy used outside its `inject()`/`inject_all()`/`global.patch()` scope
  now dies (`guard_proxy` in the engine) instead of falling through to the real
  module and defeating the seal. inject/inject_all guard on a per-call live cell;
  global.patch guards on proxy identity (dies after unpatch/restore/re-patch).
- **2.10** generator name threaded into `gen.alphanumeric`/`gen.ascii` errors.
- **3.2** -j2 rendering-contiguity smoke. **3.3** `failures[]` compared in
  verify.uc. **3.5** SKIP/IGNORE smoke tokens.
- **4.2** proxy_base label; **4.3** both false comments; **4.4** path-asymmetry
  note; **4.5** compact dedup + wrap-width comment; **4.6** registry header.

- **1.15** parallel spawn-failure handling is iterative (folded the terminal check
  into `pump`, dropped `advance`), so a burst of synchronous spawn failures no
  longer nests a stack frame per failure. **2.11** per-case seeds are avalanched
  through a Murmur3 fmix32 before `srand` — ucode's LCG first-draw is near-linear
  in the seed, so `base_seed + i` marched consecutive cases in lockstep; the mix
  decorrelates them while keeping the linear seed as the reported/reproducible
  token. Verified empirically (old: 5 distinct steps / 12 cases; new: 11) with a
  regression test in `99_property_test.uc`.

---

## Still open

### Carried over (from the first review; unchanged)
- **shell escaping**: `utest.sh` `json_str` doesn't escape control chars.
- **process-group kill**: timeout kill targets the worker PID only;
  grandchildren survive; sequential read can hang past timeout.
- **dup-file across bundles** corrupts per-suite bookkeeping; **test-dir require
  templates** shadow shim paths. Both contrived.
- **2.3-prev** patch_builtin outside snapshot/restore (documented manual cleanup).

### Test gaps still open
- **3.4** Parallel-interrupt branch (1.3/1.11) has no automated test — needs
  mid-run signaling; verified by construction. (Hard, acknowledged.)
- **Carried over:** CLI `-f`/`-l` untested directly; seed reproducibility
  asserted nowhere; `utest.sh` json_str escaping untested; warning paths
  unasserted (a few warnings leak into meta output as unasserted byproducts).

### Readability carried over
- 4.6-prev (`dispatch` exported but only used in-file); 4.9-prev (no single
  architecture-overview doc).
