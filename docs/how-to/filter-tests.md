# How to filter tests by name

Run a targeted subset of tests by passing a regex to `--filter`, without modifying any source files.

---

## Pass a regex with --filter

The `--filter` flag accepts a regular expression. utest matches it against each test's full path string, which has the form:

```
Suite Name > Nested Suite > test name
```

Only tests whose path string matches the regex are executed. Everything else is marked `IGNORE` and skipped without failure.

```bash
make -f dev.mk test ARGS="--filter 'Authentication'"
```

This runs every test whose path contains the word `Authentication`, regardless of nesting level.

---

## Run all tests in one describe block

Given a suite structured like this:

```js
describe("User Management", () => {
    describe("Registration", () => {
        it("creates a new user", () => { ... });
        it("prevents duplicate emails", () => { ... });
    });

    describe("Permissions", () => {
        it("allows admins to delete users", () => { ... });
    });
});
```

To run only the `Registration` tests:

```bash
make -f dev.mk test ARGS="--filter 'Registration'"
```

To run only the single test about admins:

```bash
make -f dev.mk test ARGS="--filter 'allows admins'"
```

To run everything under `User Management` (all nested suites):

```bash
make -f dev.mk test ARGS="--filter 'User Management'"
```

---

## Match a keyword across multiple suites

The regex is not anchored, so a keyword matches anywhere in the path. To run every test that mentions `timeout` across the entire test run:

```bash
make -f dev.mk test ARGS="--filter 'timeout'"
```

Use anchors and special characters when you need precision. To match only the top-level suite named exactly `FS Mocking` and nothing else:

```bash
make -f dev.mk test ARGS="--filter '^FS Mocking >'"
```

---

## Understand IGNORE in the output

Tests that do not match the filter are reported as `[IGNORE]`. They are not counted as failures, passes, or skips — they simply do not contribute to the summary counts:

```
  [PASS] creates a new user
  [PASS] prevents duplicate emails
  [IGNORE] allows admins to delete users
Summary:
  Total:  2
  Passed: 2
  Failed: 0
```

This makes `--filter` safe to use in any environment, including CI, without affecting the exit code for unrelated tests.

---

## Combine --filter with other flags

`--filter` composes freely with `--jobs`, `--reporter`, and bundle paths:

```bash
make -f dev.mk test ARGS="--filter 'Registration' --reporter=json --jobs=4 test/unit"
```

---

## Next steps

- Skip specific tests permanently in source: [How-to: Skip tests temporarily](skip-tests.md)
- Run the full suite in CI: [How-to: Run utest in CI](ci.md)
- See all CLI flags: [Reference: CLI](../reference/cli.md)
