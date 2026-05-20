# How to troubleshoot common problems

Practical fixes for the most frequent issues encountered when running or configuring utest.

---

## Tests are not found

**Symptom**: utest reports `0 total` and exits 0, even though test files exist.

**Cause**: utest scans `test/unit/<pattern>` by default, where `<pattern>` is `*_test.uc`. Files outside that directory or with a different naming suffix are not discovered.

**Fix**: Pass the file or directory explicitly:

```bash
make -f dev.mk test ARGS="test/my_suite_test.uc"
make -f dev.mk test ARGS="test/integration/"
```

Or change the pattern in `utest.config.uc`:

```js
return { pattern: '*_spec.uc' };
```

Or pass it on the command line:

```bash
make -f dev.mk test ARGS="--pattern='*_spec.uc'"
```

---

## A module import is not being intercepted

**Symptom**: Inside a test, `import * as fs from 'fs'` returns the real filesystem module even though a mock is set up with `mock.inject()` or `mock.global.patch()`.

**Cause**: The module was not listed in the `mocks` key of `utest.config.uc`. utest only intercepts modules that are declared there; all other imports resolve to the real module unchanged.

**Fix**: Add the module to your config file:

```js
// utest.config.uc
return {
    mocks: {
        'fs': null
    }
};
```

`null` uses the built-in proxy. To use a custom proxy instead, pass a `{ proxy: 'path/to/proxy.uc' }` object. See [Reference: CLI and Configuration](../reference/cli.md) for the full syntax.

---

## A worker times out

**Symptom**: The runner prints `worker timed out after 60s` for one or more test files, and those files are marked as fatal errors.

**Cause**: A test file took longer than the configured timeout. This can happen when code under test calls a blocking operation (a real network request, a sleep, a tight loop) that the test did not mock out.

**Fix**: Identify the blocking call and mock it. For example, if `uloop` timers are blocking, use the `uloop` proxy:

```js
// utest.config.uc
return { mocks: { 'uloop': null } };
```

If the test genuinely needs more time (e.g. a slow integration fixture), raise the timeout:

```bash
make -f dev.mk test ARGS="--timeout=120"
```

Or set it in `utest.config.uc`:

```js
return { timeout: 120 };
```

---

## Tests pass locally but fail in CI

**Symptom**: All tests pass when run with `make -f dev.mk test` on a developer machine, but the same commit fails in the CI pipeline.

**Possible causes and fixes**:

**Non-deterministic test ordering**: By default, utest shuffles test files. A random seed is printed in the summary. Reproduce the CI failure locally by passing the same seed:

```bash
make -f dev.mk test ARGS="--seed=1234567890"
```

**Parallel race condition**: Tests that share mutable global state can interfere when run concurrently. Set `--jobs=1` to confirm the failure is order-dependent:

```bash
make -f dev.mk test ARGS="--jobs=1"
```

If the failure disappears, the tests share state that needs to be isolated per test (use `beforeEach`/`afterEach` to set up and tear down).

**Missing mock declaration**: The CI environment may have a different real module available (or none at all). Ensure all required modules are declared in `mocks` so the test never reaches the real implementation.

---

## `assert.eq` reports a mismatch but the values look identical

**Symptom**: A failing test prints both the actual and expected values, and they appear to be the same string or number.

**Cause**: The values differ in type. ucode distinguishes `"5"` (string) from `5` (integer). `assert.eq` uses structural equality, so type mismatches fail even when the printed representations look the same.

**Fix**: Check the types explicitly. `type()` returns the type name as a string:

```js
assert.eq(type(actual), "int");
assert.eq(actual, 5);
```

Alternatively, use `assert.ok` with an explicit comparison that coerces as intended.

---

## `could not create pipes directory` error

**Symptom**: The runner exits immediately with `[utest] error: could not create pipes directory: /tmp/utest-XXXXX/pipes`.

**Cause**: The temporary run directory could not be created, usually because `/tmp` is full, read-only, or the process lacks write permission.

**Fix**: Check available space and permissions:

```bash
df -h /tmp
ls -ld /tmp
```

On OpenWrt, `/tmp` is a `tmpfs` mount sized to half of available RAM. If it is full, clear space or increase the `tmpfs` size in your system configuration.

---

## No color in the output

**Symptom**: The `detailed` reporter output contains no ANSI color codes, making pass/fail lines hard to distinguish at a glance.

**Cause**: Color is disabled either automatically (when stdout is not a TTY, e.g. in CI or when piped to a file) or explicitly via `--no-color`.

**Fix**: If you are viewing output directly in a terminal and still see no color, check that your `utest.config.uc` does not set `color: false`. To force color on unconditionally (e.g. in CI systems that support it), there is no current override flag — remove the `color: false` line from the config or omit `--no-color`.

---

## An unrecognised option error

**Symptom**: `utest: unrecognised option: --foo`

**Cause**: The flag does not exist or is misspelled.

**Fix**: Run `utest --help` to see every supported flag, or consult [Reference: CLI and Configuration](../reference/cli.md).

---

## Next steps

- See all available flags: [Reference: CLI and Configuration](../reference/cli.md)
- Understand test isolation: [Explanation: About test isolation](../explanation/test-isolation.md)
- Set up CI: [How-to: Run tests in CI](ci.md)
