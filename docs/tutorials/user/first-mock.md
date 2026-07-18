# Writing your first mock

In this tutorial, we will write a source module that accepts `fs` as a parameter, and write tests that pass a mock proxy in place of the real module. By the end you will understand how `mock.inject()` works and why dependency injection makes mocking simpler.

---

## What we will build

A source module `src/banner.uc` that accepts `fs` as a parameter, and a test file `test/unit/banner_test.uc` that uses `mock.inject()` to supply a virtual filesystem. No config file is needed.

---

## Prerequisites

- Completed [Writing your first test suite](first-test.md). You should be comfortable with `describe`, `it`, `assert`, and the `-l` flag.

---

## Step 1 — Create the source module

Write `src/banner.uc`:

```js
export function get_banner(fs) {
    return fs.readfile('/etc/banner');
};
```

`get_banner` receives `fs` as a parameter instead of importing it directly. In production it is called with the real `fs` module; in tests we will pass a mock proxy.

---

## Step 2 — Create the test file

Create `test/unit/banner_test.uc`:

```js
import { describe, it, mock, assert } from 'utest';
import { get_banner } from 'banner';

describe("get_banner()", () => {
    it("returns the seeded banner content", () => {
        mock.inject('fs', {
            data: { '/etc/banner': 'Welcome to OpenWrt\n' }
        }, (m_fs) => {
            assert.match('Welcome to OpenWrt\n', get_banner(m_fs));
        });
    });

    it("returns null when no banner file is seeded", () => {
        mock.inject('fs', { data: {} }, (m_fs) => {
            assert.match(null, get_banner(m_fs));
        });
    });
});
```

`mock.inject('fs', ...)` builds a proxy and passes it as `m_fs` to the callback. We hand that proxy directly to `get_banner`, so the function reads from virtual data instead of the real filesystem. No `utest.config.uc` is needed.

---

## Step 3 — Run the tests

```bash
utest -l src test/unit/banner_test.uc
```

You should see:

```
[test/unit/banner_test.uc] test/unit/banner_test.uc
  [PASS] returns the seeded banner content
  [PASS] returns null when no banner file is seeded
Summary:
  Suites: 1
  Total:  2
  Passed: 2
  Failed: 0
  Errors: 0
  Time:   5 ms
  Seed:   ...
```

---

## Step 4 — Confirm the mock is bounded to the callback

Add a third test that saves the proxy and calls `get_banner` with it after the callback exits:

```js
    it("mock data is gone once the callback exits", () => {
        let saved = null;
        mock.inject('fs', { data: { '/etc/banner': 'test content' } }, (m_fs) => {
            saved = m_fs;
            assert.match('test content', get_banner(m_fs));
        });
        // The mock layer has been removed — the proxy returns null for unseeded paths.
        assert.match(null, get_banner(saved));
    });
```

Run again and confirm all three tests pass.

---

## What we just built

- A source module that accepts `fs` as a parameter so tests control which implementation it receives.
- Tests that use `mock.inject()` to build a proxy and pass it directly to the function under test.
- Confirmation that the mock layer is bounded: once the callback exits, the proxy returns null for any path.
- No `utest.config.uc` required when code receives its dependencies as parameters.

---

## When your code imports `fs` directly

If your module uses `import * as fs from 'fs'` rather than accepting `fs` as a parameter, see [How-to: Mock a module with mock.inject()](../../how-to/mock-inject.md) for that pattern.

---

## Next steps

- Mock the filesystem in detail (writefile, lsdir, glob, strict mode): [How-to: Mock the filesystem](../../how-to/mock-fs.md)
- Intercept calls through a direct `import * as fs from 'fs'` binding: [How-to: Patch global state](../../how-to/mock-global-patch.md)
- Understand why two mock mechanisms exist: [About mock.inject() vs mock.global.patch()](../../explanation/inject-vs-patch.md)
- Make unmocked paths fail immediately: [How-to: Use strict mode](../../how-to/strict-mode.md)
