# Full-project review — 2026-07-03 @ `3dab30e`

Four-reviewer panel (mock subsystem, runner/execution, property/DSL,
quality+tests). The highest-impact claims were re-verified directly against the
code or live runs before landing here; two reviewers additionally verified
their findings by executing them against a real ucode interpreter (marked
*empirically verified*). This replaces the previous to-fix.md (removed at
3dab30e after its batch completed — see git history).

**Suite health at review time:** `make meta-test` fully green — 314 PASS /
0 FAIL, exit 0, 13.4s warm (docker `openwrt/rootfs:x86-64-25.12.4`).

**Grades:** mock subsystem **A-** · runner/executor/uloop **B+** ·
property/DSL/combinators **B+** · readability **A-** · test quality **B+** ·
**Overall B+** (up from B at `0d1966e`). Theme holding it at B+: the remaining
bugs are all *silent* failures — green exit with missing suites, a generator
that quietly stops generating, an assertion that quietly always passes, strict
mode that quietly doesn't apply. Items 1.1–1.6 are small, localized fixes;
with those plus a reporter smoke test this is an A- project.

---

## FIXED — Tier 1 batch (2026-07-03, after the review above)

All items with a clear, localized, no-judgment-call path are **done and
committed**, each verified via `make meta-test` (still fully green):

- **1.1** parallel interrupt now emits a FATAL when `finished < total` after
  `uloop.run()` → honest summary + non-zero exit.
- **1.3** `is_event()` guard in the decoder: a malformed/forged protocol line is
  captured as diagnostics, never dispatched (was crashing the whole runner).
- **1.4** `regex()` validates its argument (kills the `not(regex("str"))`
  always-pass). Regression tests in 16_combinators.
- **1.5** uci strict mode now enforced on `get_all`/`delete` (die on unmocked
  package, like `get`/`foreach`); `load` returns `false` for an unmocked package
  (real-uci fidelity) rather than dying — the read accessors still catch typos.
  Regression tests in 13_uci.
- **1.6** a generator dying on a shrink candidate is classified invalid, not
  fatal — the real counterexample survives.
- **1.7** `gen.float` rejects non-finite bounds (NaN/Inf) via `math.isnan`.
  Regression tests in 99_property.
- **1.8** uclient resets `_body_served` per request (handle reuse serves the
  body). Regression test in 15_uclient.
- **1.14** removed dead `fs.popen` read; memoized `engine.get_real()`.
- **3.2** sequential (`-j1`) timeout watchdog now covered (baseline
  `timeout_seq_test.json`).
- **3.3** `verify.uc` now deep-compares the `bundles{}` map.
- **§4 cleanup:** 4.1 (dedup describe/xdescribe + it/skip), 4.2 (shared
  `seed_from_clock`/`elapsed_ms`), 4.3/4.5/4.10 (comments + docstring fixes).

### Tier 2 (decisions made, now done)

- **1.2/1.2b** gen.int now rejects a span > 2^62 or one that overflows int64,
  with a clear message (decision: reject rather than widen the draw, which would
  churn the shrink goldens for a case nobody hits). Regression tests in
  99_property.
- **3.1** reporter smoke tests added to meta-test.sh (`smoke_reporter`): the
  detailed and compact reporters are run `--no-color` over PASS / FAIL+ERROR /
  FATAL fixtures, asserting exit code, non-empty output, no stack trace, and key
  tokens (decision: smoke + tokens, not brittle golden text).

**1.6 note:** the fix is verified ad-hoc but has no baselined test — a
deterministic repro needs a magic seed + brittle shrink goldens (see 3.5).

### §2 policy (decided)

- **2.1/2.2** destructive-fs sandboxing — **Option A (seal)** chosen and done:
  `unlink`/`rename` on an unmocked path no longer touch the real filesystem
  while a mock is active (unlink tombstones; rename overlay-reads + moves within
  the mock). Consistent with the already-sealed writes. Regression tests in
  11_mocking_fs prove a real sentinel survives. Related `popen('r')`
  real-command execution left as-is (an overlay read the author writes
  explicitly; different class).

- **2.4** reserved channel-name validation — **done**: `get_proxy_channels()`
  now dies if a custom proxy declares a channel named after reserved metadata
  (fns/strict/calls/proxy/channels). Regression test via a custom-proxy fixture
  (28_reserved_channel — first exercise of the `mocks:{proxy:...}` path).

- **2.5** `mock.global.patch` state validation — **done**: mirrors inject's
  non-null-object guard (was crashing with a bare "left-hand side expression is
  null"). Regression test in 09_mock_state.

- **4.11** structural key-paths in `equals()` failures — **done**: a nested
  mismatch now reads `at user.age:` / `at items[1].name:`. Path is accumulated
  bottom-up in the result (equals_object/equals_array prepend their segment) and
  formatted once in assert.match() via `path_str()`; non-structural combinators
  unchanged but get location context when nested; top-level scalars unchanged
  (no baseline churn). Covers the `equals` path only — contains/any_order/
  starts_with keep their own element-matching (out of scope). Tests in
  16_combinators.

**Still open** (Tier 3/4 — need real work or a policy call): 1.9 (shell
control-char escaping), 1.10/1.11 (process-group kill — shell restructuring),
1.12/1.13 (bookkeeping/search-order edges), 3.5 (de-brittle shrink goldens),
remaining §2 (2.3 patch_builtin isolation, 2.6–2.12 lesser), and §4 (4.4
combinator-list check, 4.6, 4.9 architecture overview).

---

## 1. Correctness defects (ranked, all verified)

### 1.1 MAJOR — SIGINT/SIGTERM during a parallel run → green exit with missing suites
- `src/utest/runner/executor/parallel.uc:128-131`
- libubox's `uloop_run()` installs its own SIGINT/SIGTERM handlers; on signal it
  sets `uloop_cancelled` and **returns normally**. Pending exit callbacks never
  fire, `finished` stays `< total`, `run()` falls off the end, the bundle loop
  and `summary()` proceed, and `runner.uc:63` computes the exit code only from
  failures actually seen. Ctrl-C (or CI SIGTERM) mid `-j4` → remaining suites
  silently vanish, summary prints, **exit 0**. Orphaned workers keep writing
  into `run_dir`, which `utest.sh` then `rm -rf`s. (`-j1` is unaffected: the
  signal kills the runner process itself.)
- **Fix:** post-condition after `uloop.run()`: if `finished < total`, emit a
  FATAL per unaccounted file (or one aggregate FATAL) so stats/exit code
  reflect the truncation. ~3 lines.

### 1.2 MAJOR — `gen.int` over the full 64-bit range silently generates only 0 *(empirically verified)*
- `src/utest/generators.uc:55` — `const span = hi - lo + 1;` overflows for
  ranges ≥ 2^63. For `gen.int(INT64_MIN, INT64_MAX)` span wraps to 0,
  `source.draw(0)` hits the `bound <= 1` branch (property.uc:44/:65) and
  returns 0 — every generated value is the zero-point. Verified: 100 draws
  produced only `0`. A property claiming "for any int64" is tested against a
  single value with no warning. Widths in (2^63, 2^64) wrap negative with the
  same degenerate result.
- **Fix:** detect overflow (`span <= 0` when `hi >= lo`) and `die()` with an
  actionable message, or handle the full range explicitly.

### 1.2b MINOR — spans in (2^62, 2^63) silently truncated *(empirically verified)*
- `src/utest/property.uc:49-52` — the two-draw combine yields 62 bits
  (`bits ∈ [0, 2^62-1]`), so for `bound > 2^62`, values in `[2^62, bound-1]`
  are unreachable — the exact failure mode the comment claims was fixed, one
  octave higher. Verified: `gen.int(0, 2^63-2)`, 5000 draws, max seen < 2^62.
- **Fix:** a third draw (93 bits) or rejection sampling above 2^62; update the
  comment either way.

### 1.3 MINOR (crash impact) — malformed `TEST_RESULT` event kills the whole runner *(verified live)*
- `src/utest/runner/executor/base.uc:6-11` (`dispatch` — no schema validation);
  crash observed at `src/utest/runner/reporter/base.uc:79` (`s.total++` on the
  per-suite stats entry keyed by the missing `suite` field), earlier than the
  originally-suspected `detailed.uc:27`.
- A worker line `{"event":"TEST_RESULT","status":"PASS"}` (forged by a test's
  own stdout, or a corrupted line that happens to parse) aborts the entire run
  with a stack trace and no summary. The protocol is in-band on stdout, so this
  is the framework's own declared hostile-input surface.
- **Fix:** schema guard in `dispatch` (require `suite` string + `path` array
  for TEST_RESULT, `suite` for SUITE_START/END/FATAL); demote failures to the
  captured-diagnostics path.

### 1.4 MINOR (trust) — `regex()` with a non-regexp arg silently never matches → `not(regex(...))` always passes *(empirically verified)*
- `src/utest/combinators.uc:363-369` — `regex(expected)` never validates
  `type(expected) === 'regexp'`; ucode's `match(str, "foo")` returns no match
  for a string pattern. `assert.match(regex("foo"), "foo")` fails; the
  dangerous form is `assert.match(not(regex("...")), s)` — an invisible
  always-pass in an assertion library. Siblings (`contains`, `starts_with`,
  `ends_with`, `not`) all validate and die.
- **Fix:** validate like the siblings.

### 1.5 MINOR (trust) — uci proxy: strict mode not enforced on `get_all`, `delete`, `load`
- `src/utest/mock/proxy/uci.uc` — `get` (:29) and `foreach` (:58) die under
  strict for unmocked packages; `get_all` (returns null), `delete` (returns
  false), and `load` (always true) have no strict check. A typo'd package name
  in code under test passes a strict-mode test, violating the documented
  contract (mock.uc:117-118).
- **Fix:** add the same `ctx.is_strict()` check to the three methods.

### 1.6 MINOR — generator error on a shrink candidate destroys the property-failure report *(empirically verified)*
- `src/utest/property.uc:82-85` — during shrinking, `try_choices` replays
  candidate choice sequences the user never generated; if a `gen.bind`-derived
  generator dies on such a candidate (shrinking drives draws toward 0 — partial
  functions are the natural trap), the `die(e)` aborts the whole `forall`.
  Seed, original value, counterexample, and the real property error are lost;
  observed report was only "user generator bug for n=0".
- **Fix:** classify non-sentinel generation errors on *shrink candidates* as
  `'invalid'` (the original-generation die at forall :391-394 stays as-is).

### 1.7 MINOR — `gen.float` accepts NaN/infinite bounds, generates NaN forever *(empirically verified)*
- `src/utest/generators.uc:97` — `if (lo > hi)` is false when either bound is
  NaN (all NaN comparisons false). Quota arithmetic propagates NaN. Downstream
  everything misbehaves (`equals(NaN)` never matches since `NaN === NaN` is
  false).
- **Fix:** reject non-finite bounds.

### 1.8 MINOR — uclient mock: `_body_served` never resets between requests on a handle
- `src/utest/mock/proxy/uclient.uc:12,88-96` — flag set on first `read()`,
  never cleared; a second `request()` on the same handle serves no body.
  Real uclient serves each response's body (retry/redirect flows break).
- **Fix:** reset the flag in `request()`.

### 1.9 MINOR — `utest.sh` JSON encoder misses control characters
- `src/utest.sh:32` — `json_str` escapes `\` and `"` only; a filter/path arg
  containing a newline/tab produces invalid JSON → uncaught syntax error at
  `cli.uc:55` instead of a usage message.
- **Fix:** escape control chars (or at minimum `\n`, `\t`, `\r`).

### 1.10 MINOR — sequential watchdog leaks its `sleep`; comment claims otherwise
- `src/utest/runner/executor/sequential.uc:19-21` — `kill $_S` kills the
  watchdog *subshell* but not its `sleep` child (shells don't propagate
  SIGTERM); the sleep lingers up to `timeout` seconds, up to N concurrent for N
  fast files. Functionally harmless (dead subshell can never fire its kill),
  but the comment's stated invariant ("prevents a PID-table leak") is false.
- **Fix:** kill the process group, or restructure so the sleep is the tracked
  PID; at minimum fix the comment.

### 1.11 MINOR — timeout kill targets the worker PID, not its process group
- `parallel.uc:113`, `sequential.uc` kill path — children spawned by a test
  (popen'd daemons) survive the kill. Parallel stays live (exit callback fires
  on the worker's death). Sequential can hang **forever past the timeout**:
  `proc.read("line")` sees EOF only when *all* pipe writers close, and a
  surviving grandchild holds stdout open.
- **Fix:** `setsid` the worker and `kill -9 -PGID`, or kill the group.

### 1.12 NIT — same file in two bundles corrupts per-suite bookkeeping
- `reporter/base.uc:53-57` keys `_suite_stats` by file only; `detailed.uc:14-15`
  suppresses the second bundle's header. Only reachable with overlapping
  bundle patterns.

### 1.13 NIT — test-dir require templates shadow shim paths
- `worker/bootstrap.uc:48-49` unshifts test-dir globs *ahead* of shim paths; a
  file named `fs.uc`/`real_fs.uc` next to a test would shadow the mock shim,
  inverting the documented shadowing order for one directory.

### 1.14 NIT — dead code / unmemoized warn
- `proxy/fs.uc:81`: `let existing = ctx.get('commands', cmd);` computed, never
  used. `engine.uc:224-229`: `get_real` is unmemoized — for proxy-backed
  modules absent on host (e.g. uloop off-target) every inject re-runs two
  failed full-search-path requires and reprints the warning (the memoization
  fix applied to `proxy_module` wasn't applied here).

---

## 2. Design / trust concerns (not bugs; decide policy)

- **2.1 Destructive fs ops escape the sandbox** (sharpest risk):
  `writefile`/`open('w')` never touch the real fs while mock state exists, but
  `unlink` (`proxy/fs.uc:172`) and `rename` (:158) of *unmocked* paths fall
  through to `ctx.real_call` inside an active non-strict inject —
  `mock.inject('fs', { data: {} }, m => m.unlink('/real/file'))` deletes a real
  file. Consistent with the documented fall-through contract, but reads and
  deletes have very different blast radii. Consider: sandbox destructive ops
  like writes, or require strict for them.
- **2.2 `mock.reset()` mid-inject unsandboxes the rest of the callback** —
  after reset, `is_active()` is false and (per 2.1) subsequent proxy
  writes/unlinks hit the real fs; an inner reset destroys the outer layer.
  No crash (`pop([])` is null-safe, verified), just silent loss of isolation.
- **2.3 `patch_builtin` is outside snapshot/restore** — per-test
  `mock.restore(mock_snap)` doesn't reset `builtin_overrides`/`global[name]`;
  a test that forgets `unpatch_builtin` leaks into every later test in the
  worker. Documented manual-cleanup, but it's the one hole in per-test
  isolation.
- **2.4 User proxy channel names can collide with registry metadata keys** —
  channels live flat beside `fns`/`strict`/`calls`/`proxy` in the same dicts
  (`engine.uc:62-66`, `to_layer`, snapshot); a proxy declaring
  `channels: ['calls']` silently corrupts call recording. One `die()` on
  reserved names closes it.
- **2.5 `mock.global.patch` doesn't validate `state`** — `patch('fs')` crashes
  with a bare "left-hand side expression is null" (`global.uc:97`) instead of
  inject's clear message (`mock.uc:131-132`). No corruption (swap happens
  after), just opaque UX.
- **2.6 Silent no-ops on user mistakes** — unknown state keys dropped by
  `to_layer` (typo `comands:` does nothing); `data:` on a generic proxy-less
  module is stored but never read; a malformed user proxy is swallowed by the
  `proxy_module` catch and silently degrades to the generic proxy.
- **2.7 ubus object-level *function* mocks can't see the method name**
  (`proxy/ubus.uc:36` — `val(args)`), so they can't dispatch per-method.
  Method-level function mocks are fine.
- **2.8 fs handle surface is partial** — mock handles expose
  `read/write/close/error` only; `seek`/`tell`/`flush`/`fileno` crash; `'r+'`
  treated as read-only.
- **2.9 `die(err)` re-throws retag exceptions** — type becomes "Error",
  stacktrace points at mock.uc, not the user's line. Message survives verbatim
  so today's reporters are unaffected; any future stacktrace-printing feature
  will point at the framework.
- **2.10 In-band protocol forgery** — a test printing a fake `SUITE_END` masks
  its own subsequent crash. Accepted trade-off of stdout signaling; noted for
  the record.
- **2.11 `registry.uc` per-instance `stack` vs global-backed `root`** — works
  only because test files reach the DSL through one umbrella import; worth a
  comment or globalizing (same class as the property-host fix).
- **2.12 stdout/stderr merge + block buffering** — a stdout flush boundary can
  split a protocol line with stderr bytes in between (needs >4-8KB output or
  unlucky timing); a SIGKILL'd worker's unflushed buffer loses its most recent
  results. Inherent to the design; document or accept.

---

## 3. Test gaps (why each matters)

- **3.1 Detailed and compact reporters have zero executable coverage.**
  `verify.uc` hardcodes `-r json`; ~230 lines (`detailed.uc`, `compact.uc`,
  `colors.uc`) — where the two most recent fix commits landed and where the
  1.3 crash lives — ship unexecuted. Even a smoke check (runs, exit code
  matches, stderr empty) closes most of the risk.
- **3.2 The sequential (`-j1`) timeout watchdog is never fired.** The timeout
  scenario runs only `-j2`; `sequential.uc:19-21` + the exit-143 mapping are
  the most platform/BusyBox-sensitive lines in the repo. A
  `timeout_seq_test.json` baseline reusing the same fixtures costs one run.
- **3.3 `bundles{}` map claimed verified but isn't.** `meta-test.sh` comment
  says the multi-bundle run exercises it; `verify.uc` never reads `.bundles`
  or `.failures`. Per-bundle aggregation could regress all-green.
- **3.4 CLI surface untested:** `-f` (only covered via config), `-s` (seed
  reproducibility asserted nowhere), `-l`, invalid `-r` rejection, `utest.sh`
  JSON escaping (1.9's failure mode).
- **3.5 Shrink goldens over-specified:** `99_property_test.json` pins
  "Shrink evals: 18/147" — any shrinker tuning breaks two baselines with a
  wall-of-text diff. Locking the shrunk *value* is right; the *eval count*
  over-specifies.
- **3.6 Warning paths unasserted** — "bundle matched no files"
  (`runner.uc:23`), "no shim created" (`manager.uc:87`); two warnings already
  leak into meta output as unasserted byproducts.

---

## 4. Readability / cleanup (all minor)

- 4.1 `dsl.uc`: `describe`/`xdescribe` (:28-46/:92-110) and `it`/`skip`
  (:54-82) are near-verbatim copies — a private `define_group(name, fn,
  skipped)` would halve the file.
- 4.2 Clock idioms ×5: ns-seed expression in `util.uc:49-50`,
  `executor/base.uc:91-92`, `property.uc:355`; ms-delta in
  `reporter/base.uc:46-47/:106`, `worker/runner.uc:147`. Two util helpers.
- 4.3 Magic numbers: `78` dots/line (`compact.uc:26`), `493` mkdir mode
  (`util.uc:75` — 0755 decimal; comment it).
- 4.4 `utest.uc:31-44` hand-maintained 14-combinator re-export list — two-file
  edits, nothing checks the lists match.
- 4.5 `import * as json_repo` (`reporter.uc:3`) dodges the `json()` builtin but
  is the one uncommented gotcha in the codebase.
- 4.6 `dispatch` (`executor/base.uc:6-11`) exported but only used in-file.
- 4.7 The `try/catch → pop → re-die` pattern recurs 6× because ucode has no
  `finally` — the *reason* is never stated anywhere; one comment at the first
  site would do.
- 4.8 Trailing whitespace: `reporter/colors.uc:1-5`, several `dsl.uc` JSDoc
  lines.
- 4.9 No single architecture overview; the protocol spec lives in
  `make_stream`'s header (`executor/base.uc:14-27`) where you find it only if
  you already know to look. (`it()`/hooks also accept non-functions —
  definition-time validation would turn a cryptic runtime ERROR into a clear
  message; `setup`/`teardown` already validate.)
- 4.10 Docs nit: `gen.int` docstring says "uniformly distributed"
  (`generators.uc:41`) while the engine deliberately biases the zero-point
  ~1/8 (`BIAS_DENOM`, property.uc:35). The bias is good design; the doc is
  wrong. Also worth a docs callout: `equals(1)` rejects `1.0` (ucode
  `1 === 1.0` is false) — a trap when mixing `gen.float` with int expectations.
- 4.11 Deep-equality failures carry no structural path —
  `assert.match({user:{age:30}}, {user:{age:31}})` reports only
  "Expected 30 / got 31", no `user.age`. Biggest usability gap in the
  assertion layer for large fixtures.

---

## 5. Architecture verdicts (for the record)

- **uloop was the right call.** Real per-worker timers, SIGCHLD-driven reaping,
  no zombies, and read-whole-file-at-exit buys *suite atomicity* — which is
  what lets the detailed reporter stream live under `-jN` with no buffering.
  No-fallback is sound for the OpenWrt target (`-j1` never touches uloop; `-jN`
  without it dies actionably). The one migration mistake: trusting
  `uloop.run()` to return only on completion (1.1).
- **Performance is fine.** The uloop rewrite removed the poll quantum, file
  churn, and per-worker shell cleanups. Remaining known item (proxy rebuild per
  inject, "3.3b" in the previous review) is cold-path and stays deliberately
  deferred: naive `memoize(build_proxy)` would skip the per-inject calls-map
  pre-seed and reintroduce `spy().calls.X === undefined` under nested injects.
- **Shell quoting is watertight** (`q()` verified textbook POSIX single-quote;
  every interpolation goes through it; `timeout` int-sanitized). The only
  encoder weakness in the chain is 1.9 on the CLI-arg side.
- **Verified strengths worth protecting:** shrinker verified minimal and
  provably terminating (well-founded shortlex order); persistence lifecycle
  exactly right (replay-before-generate, retain-on-replayed-failure,
  delete-on-pass, stale-detect); parallel accounting invariant
  (`finished + active + queue == total`) airtight but for 1.1; single shared
  decode/fatal path means `-j1`/`-jN` cannot drift; per-test mock
  snapshot/restore with the beforeEach re-snapshot optimization.

---

## Suggested order of attack

1. **1.1** parallel post-run check (3 lines; kills the worst silent failure).
2. **1.3** dispatch schema guard (turns runner-crash into captured
   diagnostics) + **3.1** reporter smoke tests.
3. **1.4** regex validation + **1.5** uci strict holes + **1.7** NaN bounds
   (three tiny trust fixes in assertion/mock layers).
4. **1.2/1.2b** gen.int range handling + fix the "uniform" docstring (4.10).
5. **1.6** shrink-candidate error classification.
6. **3.2** sequential-timeout baseline + **3.3** make verify.uc read
   `.bundles`.
7. Policy decision on **2.1/2.2** (destructive-fs sandboxing) — worth a
   deliberate choice, not a drive-by.
8. Cleanup batch: 1.8-1.14, §4 items as convenient.
