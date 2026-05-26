# How to run the regression suite

The regression suite compares the `json` reporter output of every example test
file against a stored baseline. A mismatch means a behaviour changed.

---

## Run all regressions

```bash
make -f dev.mk meta-test
```

The script runs inside the official OpenWrt 24.10 Docker image so results reflect
the target environment. It finds every `*_test.uc` file under `examples/`,
resolves the matching baseline under `test/json/`, and reports pass or fail. Any
example without a baseline is printed as `[SKIP]` and does not cause failure.

Output on success:

```
Verification Started

  [PASS] examples/unit/01_assertions_test.uc
  [PASS] examples/unit/02_lifecycle_test.uc
  ...

SUCCESS: All features verified.
```

Output on failure:

```
FAILURE: Regressions found in: examples/unit/05_diagnostics_test.uc
```

---

## Regenerate an existing baseline

When you intentionally change behaviour, update the stored baseline after
confirming the new output is correct:

```bash
make -f dev.mk test ARGS="-r json examples/unit/01_assertions_test.uc" \
    > test/json/unit/01_assertions_test.json
```

For tests that require a config file (mock shims), pass `-c`:

```bash
make -f dev.mk test ARGS="-r json -c examples/unit/11_mocking_fs_config.uc examples/unit/11_mocking_fs_test.uc" \
    > test/json/unit/11_mocking_fs_test.json
```

The meta-test script detects a companion config file automatically by looking for
`examples/<prefix>_config.uc` alongside each `<prefix>_test.uc`. `make -f dev.mk test`
does not do this automatically, so you must pass `-c` explicitly
when regenerating by hand.

---

## Add a baseline for a new example file

1. Write the example test file in `examples/unit/` (or `examples/integration/`).
2. If the test needs mocks, write the companion config file.
3. Run the test once to confirm it passes with the detailed reporter:

```bash
make -f dev.mk test ARGS="examples/unit/15_mymod_test.uc"
```

4. Capture the json output as the baseline:

```bash
make -f dev.mk test ARGS="-r json -c examples/unit/18_mymod_config.uc examples/unit/18_mymod_test.uc" \
    > test/json/unit/18_mymod_test.json
```

5. Run the full suite to confirm the new baseline is picked up:

```bash
make -f dev.mk meta-test
```

---

## How the runner resolves config files

`scripts/meta-test.sh` strips the `_test.uc` suffix from the example path and checks
for `<prefix>_config.uc`. For example:

| Test file | Config file checked |
|---|---|
| `examples/unit/11_mocking_fs_test.uc` | `examples/unit/11_mocking_fs_config.uc` |
| `examples/unit/14_uloop_test.uc` | `examples/unit/14_uloop_config.uc` |
| `examples/unit/01_assertions_test.uc` | *(none — file absent, no `-c` passed)* |

The bundle test (`08_bundles_test.uc`) is a special case: `scripts/meta-test.sh` passes a
`MyBundle:` prefix to exercise named-bundle parsing.

---

## Next steps

- Run `make -f dev.mk meta-test` after every non-trivial change to catch regressions
  early.
- Keep baselines committed alongside the example files so CI can detect
  regressions automatically.
