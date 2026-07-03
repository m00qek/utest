# Full-project review — 2026-07-03 @ `ff86ebc` (second pass)

Four-reviewer panel (mock subsystem, runner/execution, property/DSL,
quality+tests). Two reviewers verified findings against the vendored ucode
interpreter source/build (`lang/`); the three highest-impact claims were
additionally re-verified live before landing here. This supersedes the previous
review at `3dab30e` (see git history) — all of that review's items were fixed,
declined-with-rationale, or accepted-by-design, and **every fix was re-verified
sound by this pass** (zero regressions; reviewers noted the fixes read
designed-in, and the codebase got *simpler* through the fix cycle).

**Suite health at review time:** `make meta-test` fully green — 379 PASS /
0 FAIL, exit 0, 18s warm (docker `openwrt/rootfs:x86-64-25.12.4`), incl. all 6
reporter smoke tests.

**Grades:** mock subsystem **B+** (was A-) · runner/executor/uloop **B-** (was
B+) · property/DSL/combinators **A-** (was B+) · readability **A-** (unchanged,
firmer) · test quality **A-** (was B+) · **Overall B+** (unchanged headline,
composition shifted).

**Theme of this pass:** four of the five new majors are *incomplete
generalizations of previous fixes* — the instance was fixed, not the class:
is_event checked that `path` exists but not its element shape (1.3); the
interrupt FATAL made the exit honest but didn't stop the run (1.1); gen.float
got NaN validation but gen.int next door didn't (1.7); the fs seal taught
rename to consult reality but not unlink, and left lsdir/glob outside strict
(2.1/1.5). Plus one genuinely new discovery (empty env) whose root cause was a
wrong spike conclusion recorded during the uloop migration.

---

## 1. Correctness defects (ranked; verification noted)

### 1.1 MAJOR — parallel workers run with an EMPTY environment *(verified live)*
- `src/utest/runner/executor/parallel.uc:84-87` — `uloop.process("/bin/sh",
  ["-c", cmd], {}, ...)`. The ucode uloop binding builds `envp` from exactly
  the given dict (`lib/uloop.c` ~:1031 `calloc(len+1)` → `execvpe`), so `{}`
  yields `envp = {NULL}`. **The in-code comment claims the opposite** ("Env is
  inherited (PATH etc.) via the empty dict") — that was a wrong Phase-2 spike
  conclusion, masked by BusyBox ash's compiled-in fallback PATH finding
  `/usr/bin/ucode` in the test container.
- Verified live: a worker printing `getenv("PATH")` sees the full PATH under
  `-j1` (popen inherits) and `NULL` under `-j2`.
- Consequences: (a) silent `-j1` vs `-jN` behavioral divergence for any test
  reading env; (b) on hosts where ucode is not on the shell's fallback PATH
  (`/usr/local/bin`, `~/.local/bin`), every `-jN` worker dies with the
  misleading "worker produced no output (possible spawn failure)" while `-j1`
  works.
- **Fix:** pass the parent environment through (build a dict from the parent's
  env, or at minimum `PATH`/`HOME`/`TMPDIR`), and fix the comment. Note the
  meta-test container cannot catch this (fallback PATH works there) — consider
  an env-probe assertion in a fixture.

### 1.2 MAJOR — `is_event()` path *elements* unvalidated → forged line still crashes the whole run *(verified live)*
- `src/utest/runner/executor/base.uc:26` — TEST_RESULT guard checks
  `type(msg.path) === "array" && length(msg.path) > 0` only. The detailed
  reporter reads `msg.path[last].name` (`detailed.uc:27`) and compact reads
  `p.id`/`p.name` per element (`compact.uc:40-46`); member access on a
  non-object element raises an uncaught reference error.
- Verified live: a test printing
  `{"event":"TEST_RESULT","suite":"x","status":"PASS","path":[1]}` aborts the
  entire run (Error 254, stack trace) — the exact class the guard's own comment
  promises to close. In parallel mode the exception inside the exit callback
  ends the uloop and discards all in-flight workers' results.
- **Fix:** require every path element to be an object (with a string `name`),
  or read defensively in the reporters. Consider also requiring a known
  `status` string (see 1.9).

### 1.3 MAJOR — ^C does not stop a multi-bundle run *(source-verified)*
- `parallel.uc:130-144` FATALs the truncated bundle but ignores
  `uloop.run()`'s return value (the signal number); `runner.uc:54-59` proceeds
  to the next bundle, whose `uloop.init()/run()` resets `uloop_cancelled` and
  spawns a fresh worker fleet. libubox traps SIGINT only *inside* `uloop_run()`
  — where the runner spends nearly all its time — so the user needs one ^C per
  remaining bundle. Exit code and summary stay honest (fatals > 0).
- **Fix:** capture `let rv = uloop.run();` and propagate an interrupted flag so
  `runner.uc` breaks the bundle loop (optionally re-raise the signal).

### 1.4 MAJOR — `gen.int` accepts a NaN bound → vacuously green properties *(verified live)*
- `src/utest/generators.uc:62-69` — with `hi = NaN`: `lo > hi` is false,
  `span = NaN`, and both `span <= 0` and `span > (1 << 62)` are false (all NaN
  comparisons are false), so the guards pass; `bits % NaN` is NaN, so **every
  generated value is NaN**. A property like `n => { if (n > 0) check(n); }`
  passes 100 runs with zero signal. Verified: `gen.int(0, math.sqrt(-1.0))`
  accepted, generates NaN.
- Related (same fix): **1.4b MINOR** — double bounds accepted; `gen.int(1.5,
  10)` draws via fmod and can return values *below lo* (verified: produced
  8.5, type double).
- **Fix:** require `type(lo) === 'int' && type(hi) === 'int'` (kills both).

### 1.5 MINOR — fs seal fidelity gaps (follow-through on the 2.1 seal)
- `proxy/fs.uc:186-189` — sealed `unlink` returns `true` unconditionally, even
  for a path that exists nowhere (real unlink returns false; sealed `rename`
  was taught to consult reality at :162-163 — unlink wasn't). SUT branches on
  unlink failure never exercise.
- `proxy/fs.uc:56-59` — append-mode `open` on an unmocked path starts from `''`,
  dropping real file content (inconsistent with rename's overlay-read). Should
  be `existing ?? ctx.real_call('readfile', [path], null) ?? ''`.
- **Fix:** mirror rename's reality-probe in unlink; overlay-read in append.

### 1.6 MINOR — `lsdir`/`glob` are a strict-mode hole
- `proxy/fs.uc:218/:246` — under strict they suppress real results and return
  the virtual view (possibly null) instead of dying like every other read op
  (`readfile`/`access`/`stat`/`open`/`popen` all die). A typo'd
  `lsdir('/etc/confg')` under strict silently returns null.
- Also **1.6b NIT** — `lsdir` returns `null` (not `[]`) when tombstones empty
  an existing real directory; real fs distinguishes empty-dir from ENOENT.

### 1.7 MINOR — uloop mock fires timers in registration order, ignoring `ms`
- `proxy/uloop.uc:30-32` — `timer(100,a); timer(50,b); run()` fires a then b;
  real uloop fires b first. Deadline-dependent SUT logic passes under mock,
  fails on target. **Fix:** stable-sort pending by `ms` before firing. (The
  single-pass `run()` — timers armed during run need another run — is an
  accepted simplification; document it.)

### 1.8 MINOR — uci `get`/`get_all` leak live references into the mock store
- `proxy/uci.uc:44` (`return s[opt];`) and `:58` (shallow spread) — a
  list-typed option is returned by reference; SUT `push()` mutates layer data,
  so later reads in the same test see phantom state. Real uci returns fresh
  values. Snapshots are safe (deep-cloned); only intra-test state corrupts.

### 1.9 MINOR — TEST_RESULT with missing/unknown `status` renders as ERR! but counts as nothing
- `is_event` doesn't check `status`; detailed's else-branch prints `[ERR!]`
  (`detailed.uc:40`) but `STATUS_KEY[msg.status]` is null so only `total`
  increments (`reporter/base.uc:74-79`) — display says error, exit code stays
  green. Forgery/malformed-only; one `status` check in `is_event` closes it.

### 1.10 MINOR — durations use CLOCK_REALTIME
- `clock()` = CLOCK_REALTIME; `clock(true)` = CLOCK_MONOTONIC (lib.c:5209).
  `reporter/base.uc:30,47,104`, `worker/runner.uc:30,146` (via
  `util.elapsed_ms` callers) — an NTP step mid-run yields wrong/negative
  `duration_ms`. One-argument change per site.

### 1.11 MINOR — interrupted-run FATAL inflates the suite count
- `reporter/base.uc:91-94` counts the pseudo-suite `"<parallel run>"` as a new
  suite → "Suites:" off by one per interrupted bundle. Cosmetic.

### 1.12 MINOR — unvalidated config/CLI coercions
- Config `reporter: "compakt"` silently falls to detailed (only the `-r` flag
  is validated, `cli.uc:58`); `-j abc` → `int("abc")` = 0 → silently
  sequential; `-s abc` → seed 0 (`cli.uc:87,94`).

### 1.13 MINOR — `gen.float` returns an *int* for degenerate int-arg ranges
- `generators.uc:116,:130` — `gen.float(3, 3)` returns `3` (type int) while
  `gen.float(3.0, 3.0)` returns a double; `equals(3.0)`/`is_type('double')`
  then fail confusingly in a framework that deliberately rejects `1 == 1.0`.

### 1.14 MINOR — `equals()` on a top-level combinator argument
- `combinators.uc:91-95` — `equals(any())` structurally matches the
  combinator's own `{ match }` shape (fails loudly with `Expected keys
  ["match"]`, never silently passes). The one entry point the guard sweep
  missed; either die like the siblings or unwrap.

### 1.15 NIT — unbounded recursion on consecutive synchronous spawn failures
- `parallel.uc` spawn-fail → `advance()` → `pump()` → `spawn()` nests one frame
  per consecutive failure (plausible only under fd/EMFILE exhaustion — exactly
  when it would fire). Iterative retry in `pump` removes it.

### Carried over, still open (from the previous review; unchanged)
- **shell escaping**: `utest.sh` `json_str` doesn't escape control chars.
- **process-group kill**: timeout kill targets the worker PID only;
  grandchildren survive; sequential read can hang past timeout. Also the
  sequential watchdog comment *still* documents the wrong rationale — what
  `kill $_S` actually buys is preventing a deferred `kill $_P` at a
  possibly-reused PID, not preventing the sleep leak (1.13-prev/D5).
- **dup-file across bundles** corrupts per-suite bookkeeping; **test-dir
  require templates** shadow shim paths. Both contrived.
- **2.3** patch_builtin outside snapshot/restore (documented manual cleanup).

---

## 2. Design / robustness concerns (not bugs)

- **2.1** Misspelled state keys silently dropped: `inject('fs', { behaviour:
  ... })` or `{ files: ... }` yields an empty mock, no diagnostic
  (`engine.uc:100-113`, `global.uc:98-102`). A die-on-unknown-key would catch a
  whole class of quiet test bugs.
- **2.2** fs `glob` `**` translation gives globstar semantics; real fs.glob is
  glob(3) where `**` ≈ `*`. Virtual paths match recursively, merged real
  results don't — mock-passes, target-fails.
- **2.3** `deep_clone` has no cycle detection — cyclic mock data hangs
  snapshot/inject (stack overflow, not a clean die).
- **2.4** A proxy leaked out of its inject callback loses the seal once the
  layer pops (`is_active()` false → writes fall through to real fs). User
  misuse, but the failure mode is the exact thing the seal prevents.
- **2.5** uloop mock's queue lives at `data['__pending__']` — a user mocking
  that key collides; a dedicated channel would isolate it.
- **2.6** `assert.throws` accepts *any* throw with no pattern — including a
  nested assertion failure (`assert.throws(() => assert.match(1,2))` passes,
  verified) and would swallow property sentinels. Consider rejecting
  `kind === 'fail'`/sentinel throws unless a pattern matched them.
- **2.7** `assert.throws` with a combinator pattern prints the serialized
  combinator object instead of its message (`assert.uc:42`).
- **2.8** `equals(NaN)` unsatisfiable with an identical-lines message
  ("Expected NaN / got NaN"); worth a special-cased hint.
- **2.9** `path_str` ambiguity: key `"a.b"` renders like nested a→b;
  numeric-string key `"0"` renders as bare 0. Cosmetic.
- **2.10** `gen.alphanumeric()`/`gen.ascii()` sizing errors say "gen.string:"
  (name not threaded through `with_locked_charset`).
- **2.11** Correlated per-case seeds: every `forall` without a persist_id uses
  `prop_seed ^ 0` and per-case `base + i` into libc srand — weak stream
  independence. `prop()` avoids it via the derived id.
- **2.12** The failure report's "Seed:" line won't reproduce the *shrunk*
  value (only the persisted choices will) — can mislead manual replay.
- **2.13** manager.uc shim generation interpolates the module name into
  single-quoted string literals (`manager.uc:52-53`) — a config-supplied name
  containing `'` produces a broken shim. Config-controlled, low risk.

---

## 3. Test gaps

- **3.1** Nothing catches the empty-env bug (1.1): the meta-test container has
  ucode on the shell fallback PATH. Add an env-probe fixture asserting workers
  see PATH (and a custom var) identically under -j1 and -j2.
- **3.2** The `-j2` rendering-contiguity invariant is untested: detailed
  streams live *because* the executor feeds each worker's output in one
  callback (`detailed.uc:9-12`), but smoke tests run at `-j1`. One `-j2` smoke
  asserting each suite header appears exactly once would pin the invariant the
  buffering-removal relies on.
- **3.3** `failures[]` in the JSON summary is never compared by verify.uc
  (reads stats/results/bundles only) — the list driving human reporters'
  detail blocks could drift from `results` unnoticed.
- **3.4** Parallel-interrupt FATAL branch (1.1-prev fix) has no test
  (needs mid-run signaling; hard, acknowledged).
- **3.5** Smoke tokens don't cover SKIP/IGNORE rendering in either reporter.
- **Carried over:** CLI flags `-f`/`-s`/`-l` untested directly; seed
  reproducibility asserted nowhere; `utest.sh` json_str escaping untested;
  warning paths unasserted (three warnings leak into meta output today as
  unasserted byproducts); 1.6-prev shrink-error fix verified ad-hoc only.

---

## 4. Readability nits (all minor)

- **4.1** `cli.uc:94` seeds from `int(t[1])` (nanoseconds only) while
  `util.uc:47` claims `seed_from_clock` is "shared so every site agrees" —
  make cli.uc use it (or fix the comment).
- **4.2** `proxy_base.uc:27` labels the `get_data`/`set_data` shorthands
  "kept for backward compatibility" — they are the *primary* API of every
  built-in proxy (~30 uses in fs.uc alone). Mislabels the design.
- **4.3** Two comments now assert false things: parallel.uc's "Env is
  inherited via the empty dict" (see 1.1) and sequential.uc's watchdog
  rationale (see carried-over). Comments that misdescribe the code are worse
  than no comments.
- **4.4** equals-vs-contains path asymmetry: `contains_object`,
  `starts_with_array`, `ends_with_array` drop the child's `path`, so
  `contains({user:{age:…}})` failures never say where. (Scoped-out during
  4.11-prev; note it as an inconsistent feature surface.)
- **4.5** compact.uc: `file_failures` init repeated 3×; wrap width `78`
  uncommented.
- **4.6** worker/registry.uc lacks the explanatory header every other
  global-state file has.
- Carried over: 4.6-prev (`dispatch` exported but only used in-file),
  4.9-prev (no single architecture-overview doc).

---

## 5. Architecture verdicts (for the record)

- **uloop reaffirmed** — verified down to the C binding this pass. The
  redirect-to-file transport and per-worker one-shot timers with the `done`
  guard are the right design; PID-reuse is safe (child stays a zombie until
  the callback); `timed_out` flag correctly sidesteps SIGKILL-looks-like-exit-0.
  But uloop made two wrong defaults easy, and both bit: env is exec-style not
  inherit-style (→ 1.1), and libubox swallows SIGINT inside run() (→ 1.3).
  These are properties to code against, not reasons to leave.
- **No-fallback stance reaffirmed**: a second polling implementation would
  double the drift surface `make_stream`/`terminal_fatal` exist to eliminate.
- **ARGV plumbing verified correct** end-to-end against main.c (the `"+"`
  optstring / literal `--` in ARGV[0] make cli.uc and bootstrap.uc both right
  despite looking inconsistent).
- **Verified strengths worth protecting:** shrinker (took a 10-element array
  to `[0, 50]` in 72 evals; termination provable; invalid-candidate handling
  robust against partial generators); persist lifecycle exact; single shared
  decode/diagnosis path; tri-state strict inheritance; snapshot/restore
  deep-clone discipline; exact-143 watchdog match.

---

## Suggested order of attack

1. **1.1** env passthrough in uloop.process + fix the false comment + 3.1
   env-probe fixture (user-facing breakage on non-container hosts).
2. **1.2** validate path elements (+ status, closing 1.9) in `is_event` —
   finishes the job the guard started.
3. **1.3** propagate the interrupt out of the bundle loop.
4. **1.4/1.4b** `gen.int` int-type bound check (kills NaN + double bounds).
5. **1.5/1.6** fs seal follow-through (unlink reality-probe, append
   overlay-read, lsdir/glob strict) + **1.7** uloop mock timer ordering.
6. **1.10** monotonic clock; **1.11/1.12** small validations.
7. **3.2/3.3/3.5** test additions; **4.x** comment-accuracy sweep (4.3 first —
   false comments).
8. Policy items as they come up: 2.1 (die on unknown state keys — recommended),
   2.6 (assert.throws swallowing assertion failures — worth a decision).
