# How to run utest in CI

Integrate utest into a CI pipeline so that every push is validated automatically and failures are surfaced immediately.

---

## Run the suite

Invoke utest with the directory containing your test files:

```bash
utest test/unit
```

The exit code reflects the result: `0` means all tests passed, non-zero means at least one test failed, errored, or the runner encountered a fatal problem. This is the signal CI systems use to mark a build as passed or failed.

---

## Use JSON output for machine-readable results

Pass `-r json` to emit a structured JSON object instead of human-readable text. This is useful when a CI system needs to parse results or store them as artefacts:

```bash
utest -r json test/unit
```

---

## Run tests in parallel

Set `jobs` in `utest.config.uc` (or pass `-j <n>` on the command line) to run multiple test files concurrently. Each file runs in its own subprocess:

```js
// utest.config.uc
return { jobs: 4 };
```

```bash
utest -j 4 test/unit
```

Parallel execution (`jobs > 1`) requires the ucode `uloop` module — the official OpenWrt rootfs images below ship it. If `uloop` is unavailable, run with `-j 1` (the default), which never loads it.

---

## GitHub Actions example

CI hosts run standard Linux, not OpenWrt. Use the official OpenWrt rootfs image to provide the right execution environment, and install utest inside it as described in [How-to: Install utest](install.md). The `install` entries below are those steps, written for a container:

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        include:
          - openwrt: '24.10.6'
            install: |
              mkdir -p /var/lock
              wget -qO /etc/opkg/keys/a2288d4745630a38 "$FEED/24.10/feed.pub"
              echo "src/gz ucode.dev $FEED/24.10" >> /etc/opkg/customfeeds.conf
              opkg update && opkg install ucode-utest
          - openwrt: '25.12.3'
            install: |
              wget -qO /etc/apk/keys/packages.ucode.dev.pem "$FEED/25.12/feed.pub.pem"
              echo "$FEED/25.12" >> /etc/apk/repositories.d/customfeeds.list
              apk update && apk add ucode-utest
    steps:
      - uses: actions/checkout@v4

      - name: Run tests (OpenWrt ${{ matrix.openwrt }})
        env:
          OPENWRT: ${{ matrix.openwrt }}
          INSTALL: ${{ matrix.install }}
          FEED: https://m00qek.github.io/packages.ucode.dev
        run: |
          VERSION=$(echo "$OPENWRT" | sed 's/\.[^.]*$//')
          docker run --rm \
            -e INSTALL -e FEED \
            -v "${{ github.workspace }}:/app" \
            -w /app \
            "openwrt/rootfs:x86-64-openwrt-${VERSION}" \
            sh -c 'set -e; eval "$INSTALL"; utest test/unit'
```

The install script runs inside the container, so `$FEED` is expanded there, not on the runner. The `mkdir -p /var/lock` line is the [container-only addition for 24.10](install.md#install-in-an-openwrt-container).

Docker is available on GitHub-hosted `ubuntu-latest` runners without any additional setup.

---

## Generic shell CI example

For CI systems that execute arbitrary shell scripts (Jenkins, Buildkite, GitLab CI, etc.):

```bash
#!/bin/sh
set -e
utest test/unit
```

`set -e` causes the script to exit immediately when `utest` returns non-zero, which propagates the failure to the CI system.

---

## Next steps

- Filter which tests run without touching source: [How-to: Filter tests by name](filter-tests.md)
- Skip tests that are not ready: [How-to: Skip tests temporarily](skip-tests.md)
- See all CLI flags: [Reference: CLI](../reference/cli.md)
