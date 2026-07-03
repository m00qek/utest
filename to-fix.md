# Open items — after the clear-path batch on the 2026-07-03 (ff86ebc) review

The second full review (four-reviewer panel at `ff86ebc`; full report in git
history at commit `32509c5`) is mostly landed. This file now tracks only what
remains open. **Suite health:** `make meta-test` fully green — 451 PASS / 0 FAIL.

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
- **2.10** generator name threaded into `gen.alphanumeric`/`gen.ascii` errors.
- **3.2** -j2 rendering-contiguity smoke. **3.3** `failures[]` compared in
  verify.uc. **3.5** SKIP/IGNORE smoke tokens.
- **4.2** proxy_base label; **4.3** both false comments; **4.4** path-asymmetry
  note; **4.5** compact dedup + wrap-width comment; **4.6** registry header.

---

## Still open

### 1.15 NIT — unbounded recursion on consecutive synchronous spawn failures
- `parallel.uc` spawn-fail → `advance()` → `pump()` → `spawn()` nests one frame
  per consecutive failure (only under fd/EMFILE exhaustion). An iterative retry
  in `pump` removes it. Deferred: delicate hot-path control flow, low payoff.

### Design / robustness concerns (need a decision, not a clear path)
- **2.1** Misspelled state keys silently dropped (`inject('fs', { behaviour })`
  yields an empty mock). A die-on-unknown-key would catch a class of quiet test
  bugs — but could break lenient usage. **Recommended, needs a policy call.**
- **2.6** `assert.throws` accepts *any* throw with no pattern, including a nested
  assertion failure or a property sentinel. Rejecting `kind === 'fail'`/sentinel
  throws changes established semantics. **Needs a decision.**
- **2.2** fs `glob` `**` gives globstar semantics; real fs.glob is glob(3).
- **2.3** `deep_clone` has no cycle detection — cyclic mock data stack-overflows.
- **2.4** A proxy leaked out of its inject callback loses the seal after pop.
- **2.5** uloop mock queue lives at `data['__pending__']`; a user mocking that
  key collides. A dedicated channel would isolate it.
- **2.7** `assert.throws` with a combinator pattern prints the serialized
  combinator object instead of its message.
- **2.8** `equals(NaN)` unsatisfiable with an identical-lines message.
- **2.9** `path_str` ambiguity: key `"a.b"` renders like nested a→b.
- **2.11** Correlated per-case seeds without a persist_id.
- **2.12** The failure "Seed:" line won't reproduce the *shrunk* value.
- **2.13** manager.uc shim generation interpolates the module name into
  single-quoted literals — a name containing `'` breaks the shim.

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
