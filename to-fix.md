# Full-Project Review — Findings & Fix Plan

Review of the entire codebase at commit `0d1966e` (2026-07-01), run as a multi-agent
review: 7 finder agents (3 correctness angles, reuse, simplification,
efficiency/uloop, altitude) followed by a verification pass. All 18 correctness
candidates survived verification — 8 reproduced empirically (Docker
`openwrt/rootfs:x86-64-openwrt-24.10` and a local ucode build), 10 confirmed by
verifier agents, several against the real binding source (`uci.c`).

**Overall grade: B** — readability A-, architecture B+, correctness C+,
test quality B-, performance B-.

---

## STATUS (updated after fix pass)

**Fixed & verified (13):** 1.1, 1.2, 1.3, 1.4, 1.5, 1.7, 1.8, 1.9, 1.11, 1.13,
1.15, 1.16, 1.17. All meta-tests pass; 1.1/1.3/1.4 (no prior coverage) were
verified with dedicated end-to-end runs; 1.7/1.8 verified to reach
previously-blind values. The `99_property_test.json` baseline was regenerated
for the two shrinking-demo properties whose RNG-dependent output changed (stats
otherwise unchanged); three regression tests were later added to that suite,
bringing it to 36 tests.

**1.2 (strict mode across layers) — fixed with Option B (three-state strict).**
`to_layer` now stores `strict` as true / false / null(=inherit) instead of
collapsing unset to false, and `is_strict` walks layers top-down honoring the
first explicit value, falling back to global. This fixes "inner inject without
strict inherits an outer strict:true" while preserving the existing, tested
behavior that an explicit inner `strict:false` overrides an outer strict:true
(`11_mocking_fs_test.uc:314`). New regression test added at
`11_mocking_fs_test.uc` for the inherit case (confirmed to fail without the fix).

**Reverted — false positive (1):** 1.14. An explicit test (`examples/unit/
16_combinators_test.uc:71`, "contains() recurses into nested arrays") and the
docstring document recursive-subsequence matching as intentional. The finding
and its verifier both missed this. `contains()` behavior is unchanged.

**Extra sub-fix discovered during 1.3:** `find_real_module` now returns an
absolute path (`fs.realpath`). Relative real-module paths (from the `./*.uc`
search entry) produced broken symlinks once the real-module symlink moved into
a nested `real_<ns>/` directory. Latent bug for any relative-path mocked module,
exposed by the dotted-name test.

**1.6 (parallel done-file race) — downgraded to latent, hardened anyway.**
Direct end-to-end testing could NOT reproduce the false FATAL: with `run_dir`
pinned and a worker forced to time out, the cleanup `rm` reliably beats the
killed wrapper's `touch`, so no stale done-file survives into the next bundle
(the finder's "188/200" was an isolated microbenchmark of the kill-then-rm
pattern, not utest's actual timing). Fixed defensively regardless: the
per-worker id counter is now module-level (monotonic across bundles) so pipe
filenames are unique run-wide and the collision class is structurally
impossible — correct even if a cleanup ever fails. Not a confirmed active bug;
no permanent meta-test (triggering it is timing-dependent).

**1.10 (uloop timers re-firing across layers) — fixed with Option 1.**
Root cause was a channel asymmetry: `_channel_get` falls through all layers to
global, but `_channel_set` writes only the current scope. The uloop proxy's
read-modify-write on `__pending__` therefore consumed an outer/global timer
while clearing only its own layer, re-firing it after the layer popped
(reproduced deterministically: 2 fires vs 1). Added a non-fall-through
`get_local_channel` primitive (symmetric with `set_channel`) exposed as
`ctx.get_local_data`; uloop's timer/run now read the current scope only, so the
queue is strictly layer-scoped — matching the already-tested contract that inner
timers don't leak outward (`14_uloop_test.uc:76`). New regression test added;
confirmed to fail (2 vs 1) without the fix. All existing uloop tests stay green.

**1.12 (detailed reporter interleaving under -j) — fixed with Option A.**
Under `-j>1` the parallel executor dispatches events from concurrent suites
interleaved, and the detailed reporter's global header-dedup printed a suite's
results under whichever header was emitted last (reproduced: "A" tests shown
under the "B" header). Fix: the detailed reporter now buffers each suite's
rendered lines and flushes the whole block on `SUITE_END` (and any un-ended
suites — timeouts/fatals — at summary), gated on a `parallel` flag threaded
through `create_reporter`. `-j1` keeps live line-by-line streaming (byte
identical output); `-j>1` prints clean, correctly-attributed per-suite blocks.
Verified manually (grouped under `-j2`, unchanged under `-j1`); the detailed
reporter has no golden-baseline coverage (baselines use `-r json`), and its
interleaved layout is timing-dependent, so no deterministic meta-test was added.

**§1 correctness is fully resolved** — every bug in section 1 is fixed,
hardened (1.6), or reverted as a false positive (1.14). **The rest of this
document is NOT done.** Remaining work, by section:

- **§2 cleanup (2.1–2.8):** the mechanical / clear-path items are **DONE**:
  **2.1** (worker-stream decoder unified into `make_stream(reporter)` in
  executor/base.uc, fed by both executors; `worker_arg()` sprintf shared too —
  option A: capture policy unified, with parallel's `capture_tail()` folding in a
  crashed worker's unterminated tail so its FATAL diagnostic matches `-j1`
  byte-for-byte; verified end-to-end under both `-j1` and `-j2`),
  **2.2** (single `blank_global()` in the engine, called from get_registry,
  patch/unpatch, and restore's post-snapshot reset — kills the drift that
  shipped bug b01a71d), **2.3** (13 positional args → single run-context object
  built once in runner.uc, defaults applied at construction), **2.4** (compact
  reporter renders fatals as first-class `FATAL` and surfaces bundle-less fatals
  in the summary), **2.5** (dedup reporter stats via `STATUS_KEY` map + loop,
  shared `theme()`, json summary reuses base context), **2.7** (single
  `fail_envelope()` builder + a `parse_thrown()` returning `{ kind, message }`, so
  assert and the property engine share one build and one parse; `caught_msg`/
  `utest_kind` removed — the `type === 'Error'` gate was **kept**, since every
  utest envelope is thrown via `die(<string>)`, making this behavior-preserving
  rather than the gate-drop originally feared), and the clean parts of
  **2.8** (`dir_prefix()` helper dedups three fs-proxy copies; `resolve_rel()`
  hoisted and reused in cli.uc; dead `all_keys` accessor removed; combinators now
  built through a `comb()` factory instead of 20 copies of the `proto({ match },
  Combinator)` boilerplate), and **2.6** (property engine given an explicit
  `property.configure({ test_file, prop_seed })` seam called by the worker
  bootstrap, replacing its reads off the runner's shared `root` object; the
  config record is held on `global.__utest_property_host` because the worker
  loads the module twice — the improvement is ownership, not eliminating global
  state: property no longer depends on `runner.worker.registry` for its config.
  Only the legit `stack` (DSL group tree) import remains; standalone defaults are
  now documented; persistence path/hash + replay verified identical to before).
  Still OPEN (deliberately, not mechanical): two sub-items
  of 2.8 (`format_path` reuse — not actually clean; fs-preamble wrapper —
  partly-intentional divergence).
- **§3 performance (1–6):** the low/medium-risk batch is **DONE** — **3.2**
  (`fs.unlink` ×3 instead of `system("rm -f")` per parallel worker), **3.3a**
  (memoized `proxy_module()` lookup incl. null miss, shared by
  `get_proxy_channels`/`build_proxy` — kills the per-inject disk scan for
  proxy-less modules), **3.4** (`gen.string` builds via array+`join`, charset
  length hoisted — the O(n²) hot path; the non-hot indent-pad in property.uc left
  as-is), **3.5** (filter verdict computed once, stashed on `test.included`), and
  **3.6** (hook-less tests reuse `mock_snap` instead of a fresh full-state
  snapshot — the biggest steady win since most tests have no `beforeEach`).
  **3.1** (worker-read latency/churn) is now **subsumed by §4** — the uloop
  rewrite removed the poll loop entirely, so the persistent-fh half-measure is
  moot. Still OPEN (deliberately): **3.3b** (cache the built proxy per name/real —
  needs nested-layer scrutiny). All non-blocking.
- **§4 uloop migration:** IN PROGRESS. Decision: **uloop-only, no polling
  fallback** — the parallel executor will require uloop. Spikes confirmed uloop
  is present in `openwrt/rootfs:x86-64-25.12.4` (absent from the old 24.10 image),
  the full suite passes there. **Phase 1 DONE** (bump the test image to 25.12.4,
  `--tmpfs /tmp:mode=1777` for the run dir, host-uid mapping in meta-test).
  **Phase 2 DONE** (commit: event-driven parallel executor on uloop). The
  implemented design differs from the original sketch: `uloop.process` gives the
  pid + real exit code but **cannot** capture stdout (child inherits stdio), and
  reading a pipe via `uloop.handle` fights ucode's stdio buffering — so each
  worker redirects to a **regular file** read once, whole, in its exit callback
  (per-worker results at completion; fine, and it removes cross-worker
  interleaving), with a `uloop.timer` + `system("kill")` for timeout. This
  removed the poll quantum, the file churn, the done-file (so **1.6** is
  structurally impossible — no done file), the pid-file, the clock math
  (**1.13**), and added crash-vs-timeout distinction. uloop-only, no fallback:
  `require('uloop')` is lazy in `run()`, so sequential (-j1) still needs no uloop;
  -jN without it dies with an actionable message. Phase 3 (drop old polling) is
  subsumed — the rewrite replaced it. Verified end to end: full meta-test (incl.
  -j2), timeout kill, crash/no-output capture, multi-bundle, queue draining.
  Note the pre-existing `utest`-CLI-vs-`verify.uc` shim discrepancy surfaced
  during Phase 1 (the global.patch interception test passes under the meta-test
  harness but not the shipped CLI, on 24.10 too) — logged, out of scope for §4.
- **§5 test gaps:** partly done — added 5.2 (hostile output), 5.3 (strict
  layering), 5.5 (RNG distribution), and part of 5.1 (uci/uclient fidelity; no
  ubus). **5.7 is done** — `make test` now defaults to `examples/unit` instead
  of the nonexistent `test/unit/*_test.uc`. Still open: 5.1 (ubus fidelity),
  5.4 (dotted-mock meta-test — see note below), 5.6 (a timeout+multibundle test
  for 1.6).

Note: the per-bug write-ups in §1 below are the ORIGINAL findings (their "Fix:"
lines are proposals, not status); the STATUS block above is authoritative for
what shipped.

**Regression tests added (verified to fail without their fix):**
`25_scalar_output_test` (1.1), `26_sibling_require_test` (1.4),
`27_mock_fidelity_test` (1.5/1.11 uci, 1.9 uclient), plus three cases in
`99_property_test`: gen.frequency negative weight (1.17) and two RNG-reachability
regressions (1.7/1.8). Each was confirmed to fail against the stashed pre-fix
source.

**No permanent test for 1.3 (dotted mock):** an end-to-end meta-test can't
independently guard it — require-based mocking works via the worker's registry
override regardless of the shim path, and `.uc` program-mode modules can't be
consumed via `import` (the only path that depends on the shim). 1.3 is verified
by an ad-hoc e2e run (dotted shim tree + interception) but is not enshrined in
`make meta-test`.

---

## 1. Correctness bugs (confirmed, ranked by severity)

### 1.1 Scalar-JSON worker output crashes the entire runner
- `src/utest/runner/executor/sequential.uc:40` and `src/utest/runner/executor/parallel.uc:35`
- Only `json(line)` is inside the try/catch; `msg.event` is dereferenced outside
  it. A test that prints `42`, `true`, `null`, or a quoted string produces a
  line that parses as scalar JSON, and `msg.event` on a non-object throws
  "left-hand side expression is not an array or object" (reproduced in Docker).
  The runner aborts mid-run: no summary, remaining suites skipped, and in the
  parallel case active workers are orphaned.
- **Fix:** after parsing, guard with `if (type(msg) !== "object") { treat as
  diagnostic passthrough; continue; }` — or move the `msg.event` accesses inside
  the try. Do it once in a shared decoder (see 2.1) so both executors get it.

### 1.2 Nested inject silently disables strict mode
- `src/utest/mock/engine.uc:170` (`is_strict`), `engine.uc:72` (`to_layer`), `mock.uc:141`
- Data/behavior lookups fall through all layers to global, but `is_strict()`
  reads only the topmost layer, and `to_layer()` hard-sets `strict: false` when
  unset. `mock.global.patch('fs', { strict: true })` followed by a plain
  `mock.inject('fs', {...}, cb)` lets unmocked calls pass through to the REAL
  module inside `cb` — the isolation the outer strict requested is defeated.
- **Fix:** make strictness layered like everything else: `is_strict()` should
  scan layers top-down and fall back to global, treating "unset" as "inherit"
  (store `strict: null` when the caller didn't specify, instead of coercing to
  false). An explicit `strict: false` on an inner layer may still override —
  decide and document the semantics either way.

### 1.3 Dotted module names produce unreachable shims
- `src/utest/mock/manager.uc:6` (`find_real_module`), `:38` (shim write), `:69`/`:92` (symlinks)
- Filenames embed dotted module names literally (`myapp.util.uc`), but ucode's
  `require('myapp.util')` resolves `myapp/util.uc` (dots map to path
  separators — verified empirically). Mocking any namespaced module silently
  has no effect: the shim is never loaded, the real module is.
- **Fix:** translate dots to `/` everywhere a module name becomes a path:
  `replace(name, ".", "/")` in `find_real_module`'s glob substitution, plus
  `mkdir_p` the intermediate dirs before writing `shims/myapp/util.uc` and the
  `real_*`/user-proxy symlinks. Add a meta-test with a dotted mock.

### 1.4 Test-dir require path entry is a silent no-op
- `src/utest/runner/worker/bootstrap.uc:40`
- `unshift(REQUIRE_SEARCH_PATH, real_dir)` pushes a bare directory. ucode's
  resolver substitutes the module name into the `*` of each entry; an entry
  without `*` never matches (verified: bare-dir entry → "No module named ...").
  Tests can't `require()` helper files placed next to them, despite this line
  existing to support exactly that.
- **Fix:** push glob templates: `real_dir + "/*.uc"` (and, if intended,
  `real_dir + "/*.so"`). Add an example test that requires a sibling helper.

### 1.5 uci mock: `foreach(pkg, null, cb)` matches no sections
- `src/utest/mock/proxy/uci.uc:62`
- `sec['.type'] !== type_name` with `type_name === null` skips every section.
  Real uci (`uc_uci_foreach` in `uci.c`) explicitly permits null and visits ALL
  sections. Code that enumerates a package sees it empty under the mock.
- **Fix:** `if (type_name !== null && sec['.type'] !== type_name) continue;`

### 1.6 Parallel done-file race misreports the next bundle's worker
- `src/utest/runner/executor/parallel.uc:97` (also `:126`, `:54`, `:17`)
- On timeout the parent `kill -9`s only the ucode pid and `rm -f`s the done
  file, but the wrapper subshell's `wait; touch done.N` runs after the kill and
  recreates it (reproduced: 188/200 races). `pipes_dir` is shared across
  bundles and `worker_id_counter` resets per bundle, so the next bundle's
  worker id N finds a pre-existing `done.N` and is instantly reported FATAL
  "worker produced no output" while healthy; its real results are discarded.
- **Fix (layered):** (a) make ids collision-proof — keep a run-global counter
  or embed the bundle name/`getpid()` in the pipe filenames; (b) kill the whole
  wrapper process group (launch via `setsid`/record the subshell pid) or have
  the wrapper skip `touch` when killed; (c) simplest robust variant: delete the
  done file *before* spawning its worker id, or verify `pid_file` matches
  before trusting `done_file`. The uloop migration (section 4) removes the
  done-file mechanism entirely and is the cleanest fix.

### 1.7 Property RNG: multiples of 8 unreachable when 8 divides the bound
- `src/utest/property.uc:22`
- The 1-in-8 zero-bias decision and the value are derived from the SAME draw:
  `r % bound === 8` implies `r % 8 === 0`, which forces the draw to 0.
  Reproduced: `gen.int(0, 15)` never generates 8 in 100k samples;
  `gen.elements` over 16 items never picks the 9th. Properties are blind to
  part of their stated domain.
- **Fix:** use two independent `math.rand()` calls — one for the bias decision,
  one for the value. Costs one extra rand per draw; record both in the
  shrink-replay tape or derive the bias from high bits and the value from
  `% bound` of a fresh draw.

### 1.8 Property RNG: spans wider than 2^31 silently truncated
- `src/utest/property.uc:21`
- `math.rand() % bound` with rand() capped at 2^31-1 means draws never exceed
  2^31-1. Reproduced: `gen.int(-2^31, 2^31-1)` produced zero negative values
  in 20k samples; `gen.int(0, 2^40)` never exceeds 2147483647.
- **Fix:** compose two rand() calls for wide bounds
  (`(rand() << 31) | rand()`, then reduce), or explicitly `die()` on spans
  > 2^31 until wide draws are supported. Also note the general modulo bias —
  acceptable for a test generator, but worth a comment.

### 1.9 uclient mock: URL mocked to null trips strict mode
- `src/utest/mock/proxy/uclient.uc:45`
- Uses `get_data(url) === null` instead of `has_data(url)`, so an explicit
  `data: { 'http://x': null }` (simulating an unreachable endpoint) dies
  "not mocked" under strict mode. The ubus proxy's comment
  (`ubus.uc:19-22`) documents avoiding exactly this.
- **Fix:** mirror ubus: `if (!ctx.has_data(url)) { strict check / real
  fallback } else { response = ctx.get_data(url); ... }`.

### 1.10 uloop mock: timers stored in outer layers re-fire after pop
- `src/utest/mock/proxy/uloop.uc:18` (root cause in `engine.uc:90-107`)
- `_channel_get` reads through layers to global; `_channel_set` writes only to
  the top layer. `run()` inside an inject fires globally-registered timers but
  writes the cleared `__pending__` list into the inject layer; when the layer
  pops, the global list still holds the timers and a later `run()` fires them
  again.
- **Fix:** consumption must happen where the data lives. Either give the
  engine a `_channel_update(name, key, fn)` that writes back to the layer that
  owned the value, or have the uloop proxy explicitly clear `__pending__` at
  every layer (new engine helper `set_data_all_layers`). Same audit applies to
  any proxy that read-modify-writes layered state.

### 1.11 uci mock: 2-arg `cursor.get(pkg, sec)` returns null instead of section type
- `src/utest/mock/proxy/uci.uc:34`
- `s[opt]` with `opt === null` returns null (ucode stringifies the key). Real
  uci returns the section type (`uc_uci_get_any` → `ptr.s->type`). Existence
  checks like `if (cursor.get('net','lan'))` take the wrong branch.
- **Fix:** `if (opt == null) return s['.type'];`

### 1.12 Detailed reporter misattributes interleaved parallel output
- `src/utest/runner/reporter/detailed.uc:13`
- `reported_suites` dedup makes `render_suite_start` a no-op once printed, so
  with `-j>1` a late result from suite A prints under suite B's header.
- **Fix:** with `-j>1`, buffer per-suite output and flush on SUITE_END (order
  results by suite), or re-print an abbreviated suite header when the current
  suite changes. Alternatively document that `-j` implies the compact reporter
  and switch defaults.

### 1.13 Worker timeout uses realtime clock, not monotonic
- `src/utest/runner/executor/parallel.uc:63`, `:73`, `:135`
- `clock()` is CLOCK_REALTIME (`clock(true)` is monotonic — verified in ucode's
  `lib.c`). A forward NTP step mass-kills healthy workers as "timed out"; a
  backward step means a hung worker never times out.
- **Fix:** use `clock(true)` for all elapsed-time math here (and audit
  duration reporting in `reporter/base.uc` / `worker/runner.uc` for the same).

### 1.14 `contains()` matches nested arrays as subsequences (false pass)
- `src/utest/combinators.uc:142`
- `contains_array` recursively wraps nested arrays in `contains_array` (and
  objects in `contains_object`), so `contains([[1,2]])` matches `[[1,99,2]]` —
  inner arrays are matched as subsequences instead of values. Inconsistent
  with `starts_with`/`ends_with`/`any_order`, which wrap nested elements in
  `equals()`.
- **Fix:** wrap nested elements in `equals()` like the sibling combinators;
  subsequence semantics apply only at the top level (which is all the docs
  promise).

### 1.15 verify.uc dies instead of reporting parse/baseline failures
- `test/verify.uc:58` and `:65`
- ucode's `json()` dies on unparseable input (and on null), so the
  `if (!actual_json)` guard is dead code: malformed utest output or a missing
  baseline file crashes the harness with a raw stack trace instead of a
  `[FAIL]` diagnostic.
- **Fix:** wrap both `json()` calls in try/catch and route to the existing
  failure messages; check `readfile()` for null before parsing.

### 1.16 `mkdir_p` treats a mid-path `//` as filesystem root
- `src/utest/util.uc:51`
- `if (!length(part)) { cur = "/"; continue; }` fires for ANY empty component,
  so `mkdir_p("a//b")` resets to `/` and attempts `mkdir("/b")`. A persist_dir
  containing `//` silently disables property-failure persistence.
- **Fix:** only treat the FIRST component as the root marker (`if (i == 0 &&
  !length(part))`); skip subsequent empty components without resetting `cur`.

### 1.17 `gen.frequency` accepts negative weights
- `src/utest/generators.uc:373-381`
- Only the SUM of weights is validated positive; an individual negative weight
  is accepted, its alternative becomes unreachable (`pick < p[0]` never true
  for negative), and `pick -= p[0]` inflates pick, skewing later alternatives.
- **Fix:** validate each weight `>= 0` (die with a clear message), keep the
  positive-sum check.

---

## 2. Structural / cleanup (verified by finders; apply opportunistically)

### 2.1 Duplicated worker-stream decoder — already drifting ⭐ do first
- `sequential.uc:33-44` vs `parallel.uc:23-41` (drain)
- The JSON-line state machine (parse, non-JSON passthrough, SUITE_END/FATAL
  flags, dispatch) is duplicated and has drifted: sequential collects non-JSON
  lines into `captured` for diagnostics; parallel only `warn()`s them and
  hardcodes `captured: ""` on the timeout path. The identical `worker_arg`
  sprintf is duplicated too (`sequential.uc:10` vs `parallel.uc:51`).
- **Fix:** move a `make_worker_stream(reporter)` decoder into
  `executor/base.uc` next to `dispatch()`/`terminal_fatal()`, owning per-worker
  state and one capture policy; both executors feed it lines. Fold the 1.1
  scalar-JSON guard into it.

### 2.2 Blank module-state shape declared in four places
- `engine.uc:51` (get_registry), `mock/global.uc:13` (blank_global — whose
  comment claims it's the single source), `mock.uc:79-86` and `:96-97`
  (restore/snapshot rebuild).
- Git history shows this drift already shipped bugs (commit b01a71d).
- **Fix:** export `blank_global()` from the engine and call it everywhere the
  pristine shape is needed.

### 2.3 13 positional args threaded through five signatures
- `runner.uc:41` → `executor.uc` → `executor/base.uc` → `parallel.uc:7` /
  `sequential.uc:6`; defaults like `timeout || 60` re-applied per layer.
- **Fix:** build one run-context object in `runner.uc` (files, filter, bundle,
  dirs, seed, timeout, lib_paths, mocks, prop_seed) and pass it down; apply
  defaults once at construction.

### 2.4 Compact reporter drops bundle-less fatals; fatals masquerade as ERRORs
- `src/utest/runner/reporter/compact.uc:129`
- `if (!msg.bundle) return;` silently drops fatals arriving before
  bundle_start — stats say "N fatals" with no detail rendered anywhere. The
  fake `{status:'ERROR', path:[{name:'Fatal Error'}]}` record makes fatals
  indistinguishable from test errors.
- **Fix:** make FATAL a first-class status in a status→symbol/color table used
  by `print_failure_details`, and render bundle-less fatals from the base's
  failures list in `render_summary`.

### 2.5 Reporter stats: five-branch copy-paste and a private reach
- `reporter/base.uc:82`: status→stats mapping is five near-identical branches
  incrementing three stat dicts; `init()` re-declares `empty_stats()` with an
  extra field. **Fix:** a `STATUS_KEY` map plus one loop; `init()` reuses
  `empty_stats()`.
- `reporter/json.uc:7` reaches into `this._bundle_stats` (private by
  convention) and re-assigns `ctx.results` the base already provides.
  **Fix:** base `summary()` includes `bundles:` in the context it builds;
  subclasses become pure render functions.
- `compact.uc:5` and `detailed.uc:5` hand-copy the no-color theme literal with
  every THEME key. **Fix:** `colors.uc` exports `theme(use_color)`.

### 2.6 Property engine hard-coupled to worker runtime
- `src/utest/property.uc:337` imports `root` from the worker registry and reads
  `root.prop_seed` / `root.test_file` mutable globals. Standalone use silently
  persists counterexamples to `./.utest/property` and degrades to wall-clock
  seeding. **Fix:** explicit `configure({ test_file, prop_seed })` entry point
  called by `bootstrap.uc`, with documented standalone defaults.

### 2.7 Failure-envelope wire format built/parsed in two places each
- `property.uc:41` (`caught_msg`/`utest_kind`) re-implements
  `parse_thrown()` from `util.uc:9`; `property.uc:297`/`:411` re-build the
  `__utest__` die-envelope owned by `fail()` in `assert.uc:10`. `parse_thrown`
  unwraps only `e.type === 'Error'` while `utest_kind` parses any message —
  divergence risk turns gen.filter discards into hard ERRORs if the envelope
  changes. **Fix:** one build helper + one parse helper in `util.uc`, used by
  assert and property.

### 2.8 Smaller items
- `dsl.uc:92`: `xdescribe`/`skip` are verbatim copies of `describe`/`it`
  differing in one flag → shared `define_group(name, fn, force_skip)`.
- `combinators.uc:19`: ~20 repeated `proto({match}, Combinator)` wrappers → a
  `comb(match_fn)` factory (generators.uc already has the `gen_from` pattern);
  `equals_array`/`starts_with_array`/`ends_with_array` share one
  `match_slice(matchers, actual, offset)` helper.
- `mock/proxy/fs.uc:108/:127/:199`: dir-prefix expression written three ways →
  extract `dir_prefix(path)`; glob's 12 sequential `replace()` calls
  (`:232-243`) → loop over a metachar list.
- `proxy_base.uc:22`: `ctx.all_keys(channel)` is dead code (zero call sites) —
  delete it, or migrate `get_all_data_keys` callers onto it and keep one API.
- `cli.uc:67`: lib_paths loop inlines the body of `resolve_rel()` defined two
  lines below → call the helper.
- `compact.uc:38`: re-implements `format_path()` from `util.uc:23` → reuse it
  and split the last element.
- Every fs proxy method repeats the 3-line `record_call`/`get_behavior`
  preamble → a `ctx.define(name, impl)` wrapper (note: the reuse pass judged
  the divergence partly intentional — each method has custom fallback
  semantics — so design the wrapper to take the fallback as the impl body).

---

## 3. Performance (confirmed waste; none blocking)

1. **Parallel poll churn** — `parallel.uc:101`: every ≤50ms tick re-opens,
   seeks, reads, closes every active worker's out-file plus an `fs.access` per
   done-file (~160 open cycles/sec at -j8), and every result is delayed up to
   the 50ms sleep quantum. *Cheap fix:* open one fh per worker at spawn and
   keep reading from it (drops offset/seek bookkeeping). *Real fix:* uloop
   (section 4).
2. **Shell-based cleanup** — `parallel.uc:97/:126`: `system("rm -f ...")` per
   finished worker = a fork+exec of /bin/sh per test file. Use three
   `fs.unlink()` calls (fs already imported; no quoting needed).
3. **mock.inject rebuild cost** — `engine.uc:28`: every inject re-probes
   `require('utest.mock.proxy.'+name)` (a full REQUIRE_SEARCH_PATH disk scan on
   miss — ucode doesn't cache failed requires) and rebuilds one wrapper closure
   per real-module function. Memoize `get_proxy_channels(name)` including the
   null miss, and cache the built proxy per (name, real) — state is read
   dynamically via `__internal__`, so reuse is safe.
4. **O(n²) string building** — `generators.uc:275`: `out += substr(...)` per
   char with `length(charset)` recomputed per char; quadratic copying ×100 runs
   ×1000 shrink evaluations. Hoist the length, push chars into an array,
   `join('', out)`. Same pattern in `property.uc:268-270` (indent pad loop).
5. **Filter regex evaluated twice per test** — `worker/runner.uc:38/:67`: store
   the match verdict on the test record in the counting pass.
6. **Redundant mock snapshot per hook-less test** — `worker/runner.uc:90`:
   `pre_body_snap` deep-clones all mock state even when `test.beforeEach` is
   empty and it equals `mock_snap`. Use
   `length(test.beforeEach) ? mock.snapshot() : mock_snap` — `restore()`
   deep-clones on read, so reuse is safe.

---

## 4. uloop — recommendation: yes, for the parallel executor only

The parallel executor's design pains are all artifacts of not having an event
loop: three temp files per worker (out/done/pid) to learn "has output /
exited / whom to kill", 50ms sleep-quantized polling with per-tick file churn,
the done-file completion race (bug 1.6), and hand-rolled realtime-clock
timeouts (bug 1.13).

**Plan:**
- Feature-detect at runtime: `try { uloop = require('uloop'); }` — fall back to
  the current polling implementation when absent (uloop needs ucode built
  against libubox; universal on OpenWrt targets, not guaranteed on dev
  machines).
- Spawn workers with `uloop.process('ucode', argv, env, exit_cb)` — exact exit
  status and pid with no pid/done files (also lets the parallel path
  distinguish crash from timeout, which it currently can't; sequential already
  can via exit code 143).
- Read worker stdout via `uloop.handle(fd, cb, ULOOP_READ)` on a pipe/popen
  fd — line-framed JSON drained only when data is ready; no sleeps, no
  reopen/seek, no out-files.
- One `uloop.timer` per worker for the timeout, replacing per-tick clock math.
- Do NOT use `uloop.task()` — it forks the parent VM, so the per-worker `-L`
  shim search paths (`build_l_flags`) wouldn't apply; spawning the ucode binary
  preserves the existing worker isolation model unchanged.
- Leave `sequential.uc` as-is: its blocking popen read plus shell watchdog is
  simple and adequate. The worker/reporter JSON protocol needs no change.

If maintaining two parallel implementations is judged too costly, the non-uloop
middle ground (persistent fh per worker, unlink instead of shell rm, monotonic
clock, collision-proof ids) fixes the bugs but keeps the polling latency.

---

## 5. Test-quality gaps (what let these bugs through)

The meta-test harness (`make meta-test`) is a solid golden-baseline net —
40+ example suites, multi-bundle aggregation, parallel `-j2` with
order-independent comparison — but its blind spots map exactly onto the bug
list. Add:

1. **Mock-vs-real fidelity tests** for uci/uclient/ubus/uloop proxies: assert
   the mock's answer matches the real binding's documented behavior for the
   edge signatures (foreach with null type, 2-arg get, explicit-null mocks).
2. **Hostile worker output**: a meta-test whose test file prints `42`,
   `true`, and garbage — runner must survive and pass diagnostics through.
3. **Strict-mode layering**: strict outer + non-strict inner inject must still
   block real calls (once 1.2 is fixed).
4. **Dotted module mocks** and **test-dir-relative require** (1.3, 1.4).
5. **RNG distribution smoke tests**: coverage of all values in a small range
   (e.g. every value of gen.int(0,15) appears within N draws), wide-range sign
   coverage — cheap and would have caught both 1.7 and 1.8.
6. **Timeout + multi-bundle parallel meta-test** for the done-file race (1.6).
7. Fix `make test` default: it points at `test/unit/*_test.uc`, which doesn't
   exist — point it at the examples or a real default test dir.

---

## Suggested order of attack

1. **1.1** scalar-JSON crash via **2.1** shared decoder (small, removes a
   crash and the worst duplication at once).
2. **1.2** strict layering + **1.9**/**1.10** proxy has_data/write-back fixes
   (mock trust).
3. **1.5**/**1.11** uci fidelity + fidelity tests (5.1).
4. **1.3**/**1.4** module-path bugs + tests.
5. **1.7**/**1.8** property RNG + distribution tests (5.5).
6. **1.6**/**1.13** parallel executor races — ideally as part of the **uloop
   migration (section 4)**, which subsumes both plus perf items 3.1/3.2.
7. Remaining small fixes (1.12, 1.14–1.17) and cleanup (section 2)
   opportunistically alongside the code they touch.
