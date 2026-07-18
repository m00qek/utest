# Docs review (2026-07-18) — findings and fix plan

Diátaxis review of `./docs` at the head of `fix/review-correctness-batch`,
after all three review-fix waves (~130 commits since v1.4.0) landed. Every
"confirmed" item below was verified by **executing the doc's own example**
against the live framework in the meta-test container — not just by reading.

**Verdict:** structure, persona modeling, and mermaid usage are textbook and
must be preserved. Content is a snapshot of the framework at ~`0d1966e`
(2026-07-01), before the fix waves. Eight documented claims are now false;
one tutorial errors mid-walkthrough. Treat the fix batch below as a release
blocker alongside the PKG_VERSION bump.

## Progress log (updated as fixed)

- **LANDED** `-l` flag bug (found during the pass): relative `-l` never
  resolved on the worker; cli.uc now makes it absolute against cwd, with a new
  meta-test block. Tutorials' `utest -l src` now works. (commit `cbef856`)
- **LANDED** D0 (export-function `;`). (commit `9c2365a`)
- **LANDED** first-test tutorial: `math`→`calc` builtin-name collision (a
  builtin `math` shadowed the reader's module — separate from D0/`-l`), real
  reporter output, shuffle note. (commit `935413b`)
- **LANDED** first-property-test: `math`→`calc`, real property-failure output
  (per-case seed note, `Saved to:` line), fixed "100 cases pass" claims. (`f6eda8e`)
- **LANDED** first-combinators: bare `rand()` (not a builtin) → content-derived
  id; ordering narrative. (`4145ca9`)
- **LANDED** D1 + D0b (first-mock: stale-proxy guard, absent-file test, output). (`9eca300`)
- Remaining: D2–D14 (how-tos, explanation, reference, nits) per the plan below.

**What is explicitly fine (do not churn):** the four-quadrant layout and
mkdocs nav; the user/contributor split in all four sections; tutorial form
(first-person plural, visible results, links out); how-to form (goal-named,
conditional imperatives); reference austerity; explanation boundedness;
diagram placement (explanation + structural reference only, correct types).

---

## D0 CONFIRMED (found during the fix pass) — `export function` snippets do not compile

On the pinned image (`openwrt/rootfs:x86-64-25.12.4`) an
`export function foo() { ... }` declaration **must** be terminated with `;`
(`};`) or the module fails to compile: `Syntax error: Expecting ';'` at the
closing brace. Plain (non-`export`) `function` declarations do NOT need it;
`export const x = <expr>` does (it is an assignment). The framework's own
source always writes `export function ... };`, but every tutorial and how-to
source snippet omits the `;`, so a reader who copies `src/math.uc` from
`first-test.md` hits a compile error on the very first `utest` run. Affects
14 `export function` occurrences across first-test, first-mock, first-property-test
(×3), first-combinators (×2), first-patch, add-assertion, add-reporter (1 of 2),
inject-vs-patch (×2), mock-global-patch. **Fix:** add the trailing `;`. This
is the true worst item — it blocks the getting-started path entirely — and is
fixed first, as its own mechanical commit.

## D0b CONFIRMED (found during the fix pass) — first-mock test 2 is environment-dependent

`first-mock.md`'s second test seeds `data: {}` and asserts `get_banner(m_fs)`
returns `null`. In non-strict mode the fs proxy falls through to the REAL
filesystem for an unseeded path, and `/etc/banner` exists on every OpenWrt
system (and in the container), so the call returns the real banner and the
test FAILS. **Fix:** seed the path explicitly absent (`{ '/etc/banner': null }`)
and reword to "returns null when the banner file is absent" — robust
everywhere and teaches the documented `null = absent` convention. Folded into
the D1 commit.

---

## D1 CONFIRMED — first-mock tutorial Step 4 errors (worst item)

`tutorials/user/first-mock.md` Step 4 teaches that a proxy leaked out of
`mock.inject()` "returns null for unseeded paths" and has the reader assert
`assert.match(null, get_banner(saved))`. The 2.4 stale-proxy guard now makes
any use of a leaked proxy **die**: `[utest] mock: the 'fs' proxy was used
outside its scope — its inject()/patch() has already ended`. The tutorial
crashes at step 4 — a tutorial must be perfectly reliable.

**Fix:** rewrite Step 4 as "Confirm the mock is bounded to the callback" by
demonstrating the guard as a *feature*: leak the proxy, then
`assert.throws(() => get_banner(saved), /used outside its scope/)`. Update
the step's prose and the "What we just built" bullet ("the proxy dies if
used after its scope" instead of "returns null").

## D2 CONFIRMED — mock-global-patch.md stale-proxy section

`how-to/mock-global-patch.md` "Observe state clearing after unpatch" claims
calls on the proxy after `unpatch()` return `null`. They die (same guard).

**Fix:** retitle the section "A proxy is dead after unpatch" and show the
`assert.throws(..., /used outside its scope/)` pattern; note this is
deliberate (a stale proxy silently hitting the real module used to defeat
the mock's isolation).

## D3 CONFIRMED — uloop timer semantics inverted; handle undocumented

`how-to/mock-uloop.md` and `reference/proxy-data-models.md` (uloop section)
teach that `run()` fires callbacks in registration order "regardless of their
millisecond values". Timers now fire **by deadline**, tie-broken on
registration order (1.7): `timer(3000,a); timer(1000,b); run()` yields
`['b','a']`, not the documented `['a','b']` — the data-models example's
expected output is wrong too. Also missing everywhere: `timer()` now returns
a handle with `remaining()` / `cancel()` / `set(ms)` (R3.15), and the queue
lives in its own `timers` channel, not a `'__pending__'` data key (2.5).

**Fix:** rewrite both uloop sections around deadline ordering (update every
example's expected output); add a "Cancel or re-arm a timer" how-to section
covering the handle; in proxy-data-models replace the `__pending__` note with
the `timers` channel and document the handle's three methods and the
single-pass `run()` semantics (a callback re-arming a timer needs another
`run()`).

## D4 CONFIRMED — glob wildcard table says the opposite of reality

`reference/proxy-data-models.md` fs glob table: "`**` — any sequence
including path separators" and "Character classes ([abc], [0-9]) are not
supported". Both inverted by 2.2/2.2b: the mock now matches real glob(3),
where `**` behaves like `*` (single level) and character classes ARE
supported (`[abc]`, ranges, `[!..]`/`[^..]` negation, literal leading `]`).
`how-to/mock-fs.md`'s "** matches across directory boundaries" example now
returns 1 file, not the documented 2.

**Fix:** correct the wildcard table (`*`, `?`, `[..]` classes with negation;
explicitly note `**` is NOT globstar, matching real glob(3)); delete or
rewrite the mock-fs `**` example as a character-class example; drop the
"classes not supported" line.

## D5 CONFIRMED — stat().type vocabulary

Docs say `stat()` returns `type: 'regular'` (`proxy-data-models.md` table +
example, `mock-fs.md` example asserting `'regular'`). R3.6 changed it to the
real fs vocabulary: `'file'`.

**Fix:** s/'regular'/'file'/ in both files (three occurrences).

## D6 CONFIRMED — strict-mode failure classification

`explanation/strict-mode.md` (twice) and `reference/glossary.md` claim a
strict-mode `die()` is reported as `FAIL`. It is reported as **ERROR**
(a raw die is not an assertion envelope; verified: `ERR!` in the detailed
reporter). The sample message format also drifted (real: `strict mock: uci
package 'no-pkg' is not mocked`, per-proxy wording varies).

**Fix:** change both to ERROR; present the message as a pattern
(`strict mock: ...` prefix) rather than one exact string.

## D7 CONFIRMED — troubleshoot.md: nonexistent seed config key + dead error

`how-to/troubleshoot.md` tells the reader to fix the shuffle seed with
`return { seed: 1234567890 }` in `utest.config.uc`. **No `seed` config key
exists** — `cli.uc:121` reads only the `-s` flag; the config key is silently
ignored (verified). Same page: the "could not create pipes directory" entry
references the deleted polling executor; the current message is "could not
create worker output directory" and the run dir layout is `workers/out.N`.

**Fix:** replace the config-key advice with `utest -s <seed> ...`; update the
pipes entry's symptom string and explanation (or fold it into a generic
"run directory not writable" entry). Consider a new entry for "worker died:
parallel execution requires uloop" (see D12).

## D8 CONFIRMED — filter-tests.md: IGNORE does count into totals

Claims ignored tests "do not contribute to the summary counts" with a sample
summary showing `Total: 2`. Reality: `stats.total` includes ignored tests
(verified: 10 ignored → `total: 10, ignored: 10`; the detailed reporter also
prints an `Ignored:` line).

**Fix:** correct the prose and the sample summary block (`Total: 3`,
`Ignored: 1` for the example shown). The "safe for CI / doesn't affect exit
code" claim is still true — keep it.

---

## D9 — worker-coordinator.md documents the deleted polling executor

The entire "Why the parallel executor polls at a fixed 50 ms interval"
section, the polling flowchart (`poll temp files`, `done sentinel`), and the
"Sequential vs parallel" description predate the uloop rewrite (`510c30e`).
Also wrong on the same page: timeout enforcement described as parallel-only
(the sequential shell watchdog exists: SIGTERM/exit-143), SIGKILL described
as the only kill signal, and `$run_dir/pipes/` naming.

**Fix (largest single rewrite):** replace the polling section with the real
design: uloop-driven lifecycle (`uloop.process` + per-worker `uloop.timer`
timeout), stdout redirected to a per-worker file read once at exit — which
is what guarantees per-suite event contiguity; no polling loop exists. Add
the deliberate signal split (SIGKILL -jN keyed on the timed_out flag vs
SIGTERM/143 -j1 keyed on exit code — mirror the cross-referenced comments in
the two executors) and the process-group kill (`setsid` + negative-pid, so
grandchildren die too). Note -jN hard-requires the uloop module (no polling
fallback; -j1 keeps it a soft dependency). Redraw the flowchart to the
event-driven shape.

## D10 — message-protocol.md: decoder and ordering claims stale

Three claims predate the fix waves: (a) "Lines that cannot be parsed as JSON
are silently discarded" — they are echoed to stderr and captured as
diagnostics for the terminal FATAL, and well-typed-but-malformed events are
rejected by `is_event` validation (1.2/1.9) and treated as diagnostics too;
(b) "events from different suites may be interleaved; reporters must
demultiplex" — a worker's whole output is now fed to the decoder in one
callback, so one suite's events always arrive contiguously (that invariant
is pinned by the parallel-contiguity meta-test); (c) the synthesized timeout
FATAL is described as parallel-only — both executors synthesize it via the
shared `terminal_fatal`.

**Fix:** rewrite the intro paragraph around `make_stream` (classify → 
dispatch or capture); replace the interleaving warning with the contiguity
guarantee; add the `aggregate: true` FATAL field (the `<parallel run>`
interrupt pseudo-suite, which reporters must not count as a suite); fix (c).

## D11 — run-regression.md: missing-baseline policy inverted

"Any example without a baseline is printed as [SKIP] and does not cause
failure" — inverted by R3.8: only `envprobe/`, `multi/`, `timeout/` may skip
(verified in dedicated blocks); any OTHER missing baseline **fails** the
suite. The page also presents meta-test as baseline-diffing only; it now
also runs reporter smokes, CLI-error checks, env-probe, parallel-contiguity,
process-group-kill, json-str-escaping, and dup-file-across-bundles blocks.

**Fix:** correct the SKIP claim; add a short "beyond baselines" paragraph
listing the dedicated check families (one line each, link to the script).

## D12 — reference gaps: features shipped since the docs were written

Missing entirely; add to the pages named:

- **`assert.fail(msg)`** (R3.20) → `reference/assertions.md`, after
  `assert.throws` (FAIL-classified, catchable by `assert.throws` with a
  matching pattern).
- **`is_combinator(v)`** public umbrella export (R3.20) → assertions.md
  combinator section intro.
- **`mock.reset()`** → `reference/mock-api.md`. It is *referenced* by
  snapshot-restore.md and troubleshoot.md but defined nowhere. Include the
  caveat that reset() mid-inject drops the sandbox for the rest of the
  callback (accepted design limitation from the second review).
- **Stale-proxy guard as a feature** → mock-api.md (inject/patch/spy
  sections): any use of a proxy after its scope dies with "used outside its
  scope"; spy() on a stale proxy dies too (R3.16). This replaces the two
  contradicting passages (D1/D2).
- **fs destructive-op seal** (R3.2) → proxy-data-models.md fs section:
  `rmdir`/`symlink`/`chown`/`chdir`/`mkdtemp`/`mkstemp` die under an active
  mock (both modes) unless a `behavior:` override is supplied — safety
  semantics users must know.
- **fs read-side family** (R3.6) → same section: `lstat` (== stat),
  `readlink` (null for known paths), `realpath` (normalizes `.`/`..`,
  confirms existence), `opendir` (cursor handle: read/tell/seek/close).
- **fs handle `seek`/`tell`/`flush`** and **`readfile(path, size)`** honoring
  size (NIT sweep) → proxy-data-models.md + a line in mock-fs.md's open()
  section. Keep the documented boundaries honest: `w`/`r+` random-access
  writes unmodeled (append-on-close), mkdir leaves no stat-able trace.
- **`-j > 1` requires the uloop module** → `reference/cli.md` (-j row) and
  `how-to/ci.md` (parallel section); the error is actionable but the
  constraint should be discoverable first. ci.md should also mention the
  `-j` flag alongside the `jobs` config key.
- **Default timeout 60s** → cli.md config table (`timeout` row).
- **uci fidelity notes** → proxy-data-models.md uci section: reads return
  deep copies, not live references (1.8); `delete()` returns null for a
  missing entry (real-uci behavior); `load()` returns false for an unmocked
  package under strict (not documented "always true").

## D13 — contributor reference drift

- **`proxy-ctx-api.md`** is missing the methods every built-in proxy
  actually uses: `ctx.record_call(name, args)` (spy integration — a
  contributor following the current doc builds a proxy invisible to
  `spy()`), `ctx.real_call(name, args, fallback)`, `ctx.has(channel, key)` /
  `ctx.has_data(key)` (which also falsifies the doc's "explicitly-stored
  null is indistinguishable from not found — use a sentinel" note), and
  `ctx.clone(v)` (deep-clone for returning fresh values like real modules
  do). Document each with the same table format; fix the null note.
- **`reporter-api.md`**: `stats.total` says "excluding ignored" — it
  includes them (same fact as D8). Note the `aggregate` FATAL flag and that
  `render_suite_end` receives per-(bundle,file) stats.
- **`source-layout.md`**: parallel.uc row still says "polls output files";
  fs proxy row lacks the read-side family and seal; examples/ table is
  missing `envprobe/`, `multi/`, `timeout/`, `loadfail/`, `requireshadow/`;
  util.uc row lacks `mono_clock`/`seed_from_clock`. Mechanical row updates.

## D14 — consistency nits (small, do in one commit)

- `mock-uci.md` and `mock-ubus.md` teach `conn.__utest__.calls.X` /
  `c.__utest__.calls.X` direct access; `spy.md` (correctly) teaches
  `spy(cursor).calls.X`. Standardize on `spy()` — `__utest__` is internal
  and bypasses the liveness guard. Also fix `proxy-data-models.md`'s ubus
  `conn.__utest__.calls.disconnect` mention.
- `mock-inject.md` opens with "Declare the module in the config file" as a
  required step; `first-mock.md` correctly shows DI-style `inject()` works
  with no config. State when the declaration is actually required (shim
  generation: intercepting the imported binding / `require()`, global.patch,
  real-module fallthrough for absent modules) vs. not (proxy passed
  directly to the code under test).
- `test-isolation.md` "What isolation does not cover" should name
  `patch_builtin`/`unpatch_builtin`: builtin patches live outside the
  snapshot/restore cycle — a forgotten unpatch_builtin leaks into every
  later test in the worker (the one accepted hole; cross-link
  mock-builtin.md's pairing warning).
- `explanation/index.md` blurb "Why two reporters exist" reads oddly now
  that there are three formats — reword to "why the worker/coordinator
  reporter split exists" (which is what the page actually explains).
- `shim-generation.md` search-order list: append lib_paths and the
  test-file's own directory (lowest tier, same as project root — the
  require-shadowing fix) for completeness.

---

## Execution plan

Order chosen so user-facing lies die first; one commit per group, meta-test
green after each; **every corrected example must be re-verified by running
it** (this review found all eight confirmed items that way):

1. **Batch 1 — confirmed-wrong user docs (D1–D8).** Tutorials + how-tos +
   the glossary/strict-mode classification. Highest harm, fully mechanical.
2. **Batch 2 — architecture pages (D9–D11).** worker-coordinator rewrite,
   message-protocol corrections, run-regression policy. Redraw the one dead
   flowchart.
3. **Batch 3 — reference gaps (D12–D13).** New API entries + contributor
   reference completion.
4. **Batch 4 — consistency nits (D14).**

Verification per batch: run each changed example verbatim in the meta-test
container (detailed reporter, correct `-c`); `make meta-test` stays green
(docs don't affect it, but batches 1–3 may add example fixtures if any doc
example is worth pinning); `mkdocs build` (via docs/Makefile) to catch nav
or anchor breakage — anchors referenced by other pages (e.g.
`#combinator-factories`, `#the-mocks-key`, `#call-inspection`) must survive
retitling.

Out of scope, deliberately: restructuring the nav, adding new doc types, or
documenting internals that the fix waves did not change.
