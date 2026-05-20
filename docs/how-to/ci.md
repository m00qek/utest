# How to run utest in CI

Integrate utest into a CI pipeline so that every push is validated automatically and failures are surfaced immediately.

---

## Prerequisites

utest runs inside the official OpenWrt 24.10 Docker image. The CI host must have Docker available. No OpenWrt SDK or cross-compiler is required on the host itself — Docker provides the entire execution environment.

---

## Run the suite

`make -f dev.mk test` wraps Docker. Run it with no arguments to execute the default test suite:

```bash
make -f dev.mk test
```

The exit code reflects the result: `0` means all tests passed, non-zero means at least one test failed, errored, or the runner encountered a fatal problem. This is the signal CI systems use to mark a build as passed or failed.

---

## Use JSON output for machine-readable results

Pass `--reporter=json` to emit a structured JSON object instead of human-readable text. This is useful when a CI system needs to parse results, store them as artefacts, or feed them into a test dashboard:

```bash
make -f dev.mk test ARGS="--reporter=json"
```

The JSON reporter writes one object to stdout covering every bundle, suite, and individual test result.

---

## Increase parallelism

By default, utest runs one test file at a time. Pass `--jobs=N` to run up to `N` files concurrently. Each file runs in its own subprocess, so this is safe without any additional setup:

```bash
make -f dev.mk test ARGS="--jobs=4"
```

Choose `N` based on the number of available CPU cores on the CI runner. A reasonable default for most hosted runners is `4`.

---

## GitHub Actions example

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run utest
        run: make -f dev.mk test ARGS="--jobs=4"
```

Docker is available on GitHub-hosted `ubuntu-latest` runners without any additional setup step.

---

## Generic shell CI example

For CI systems that execute arbitrary shell scripts (Jenkins, Buildkite, GitLab CI, etc.):

```bash
#!/bin/sh
set -e
make -f dev.mk test ARGS="--jobs=4"
```

`set -e` causes the script to exit immediately when `make` returns non-zero, which propagates the failure to the CI system.

---

## Run the regression suite

For a full regression check that also validates the framework's own internals, use the bundled runner script directly:

```bash
./test/runner.sh
```

This is what the project's own CI pipeline runs on every push.

---

## Next steps

- Filter which tests run without touching source: [How-to: Filter tests by name](filter-tests.md)
- Skip tests that are not ready: [How-to: Skip tests temporarily](skip-tests.md)
- See all CLI flags: [Reference: CLI](../reference/cli.md)
