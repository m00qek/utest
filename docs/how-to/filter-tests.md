# How to filter tests by name

Run a targeted subset of tests by passing a regex to `-f`, without modifying any source files.

---

## Pass a regex with -f

The `-f` flag accepts a regular expression. utest matches it against each test's full path string, which has the form:

```
Suite Name > Nested Suite > test name
```

Only tests whose path string matches the regex are executed. Everything else is marked `IGNORE` and skipped without failure.

```bash
utest -f 'Authentication'
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
utest -f 'Registration'
```

To run only the single test about admins:

```bash
utest -f 'allows admins'
```

To run everything under `User Management` (all nested suites):

```bash
utest -f 'User Management'
```

---

## Match a keyword across multiple suites

The regex is not anchored, so a keyword matches anywhere in the path. To run every test that mentions `timeout` across the entire test run:

```bash
utest -f 'timeout'
```

Use anchors and special characters when you need precision. To match only the top-level suite named exactly `FS Mocking` and nothing else:

```bash
utest -f '^FS Mocking >'
```

---

## Understand IGNORE in the output

Tests that do not match the filter are reported as `[IGNORE]`. They are counted in `Total` and shown on their own `Ignored` line, but never as passes, failures, or errors — so they never affect the exit code:

```
  [PASS] creates a new user
  [PASS] prevents duplicate emails
  [IGNORE] allows admins to delete users
Summary:
  Total:   3
  Passed:  2
  Failed:  0
  Errors:  0
  Ignored: 1
```

This makes `-f` safe to use in any environment, including CI: filtered-out tests are recorded as ignored, not failed, so the exit code reflects only the tests that actually ran.

---

## Combine -f with other flags

`-f` composes freely with `-r` and bundle paths:

```bash
utest -f 'Registration' -r json test/unit
```

---

## Next steps

- Skip specific tests permanently in source: [How-to: Skip tests temporarily](skip-tests.md)
- Run the full suite in CI: [How-to: Run utest in CI](ci.md)
- See all CLI flags: [Reference: CLI](../reference/cli.md)
