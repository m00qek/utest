# Writing your first mock

In this tutorial, we will configure utest to intercept `fs` calls and write tests that read from virtual files instead of the real filesystem. By the end you will have a working `utest.config.uc` and know how `mock.inject()` works.

---

## What we will build

A config file `utest.config.uc` that declares `fs` as a mockable module, and a test file `test/unit/files_test.uc` with two tests: one that reads from a seeded virtual file, and one that confirms that unseeded paths return `null`.

---

## Prerequisites

- Completed [Writing your first test suite](first-test.md). You should be comfortable with `describe`, `it`, and `assert`.
- Docker running.

---

## Step 1 — Create the config file

Mocking a module requires a config file that declares which modules should be interceptable. Create `utest.config.uc` at the project root:

```js
return {
    mocks: {
        'fs': null
    }
};
```

For why a config file is required and what a shim is, see [About shim generation](../../explanation/shim-generation.md).

---

## Step 2 — Create the test file

Create `test/unit/files_test.uc`:

```js
import { describe, it, mock } from 'utest';
import { assert } from 'utest.assert';

describe("virtual filesystem", () => {
    it("reads a seeded file", () => {
        mock.inject('fs', {
            data: {
                '/etc/hostname': 'myrouter\n',
                '/etc/banner':   'Welcome to OpenWrt\n'
            }
        }, (m_fs) => {
            assert.eq(m_fs.readfile('/etc/hostname'), 'myrouter\n');
            assert.eq(m_fs.readfile('/etc/banner'),   'Welcome to OpenWrt\n');
        });
    });

    it("returns null for an unseeded path", () => {
        mock.inject('fs', { data: { '/etc/hostname': 'myrouter\n' } }, (m_fs) => {
            assert.eq(m_fs.readfile('/tmp/absent.txt'), null);
        });
    });
});
```

`mock.inject()` takes three arguments: the module name, a state object containing `data`, and a callback that receives the proxy. Inside the callback, `m_fs.readfile()` returns the seeded string rather than touching the real filesystem.

---

## Step 3 — Run the tests

```bash
make -f dev.mk test ARGS="test/unit/files_test.uc"
```

You should see:

```
[test/unit/files_test.uc] test/unit/files_test.uc
  [PASS] reads a seeded file
  [PASS] returns null for an unseeded path
Summary:
  Suites: 1
  Total:  2
  Passed: 2
  Failed: 0
  Errors: 0
  Time:   5 ms
  Seed:   ...
```

Both tests pass. The mock is active only inside each callback; once the callback returns, the real `fs` module is unaffected.

---

## Step 4 — Confirm the mock layer is removed after the callback

Add a third test that captures the proxy and then calls it outside the callback:

```js
    it("proxy returns null once the callback exits", () => {
        let proxy = null;

        mock.inject('fs', { data: { '/etc/hostname': 'mocked' } }, (m_fs) => {
            proxy = m_fs;
            assert.eq(m_fs.readfile('/etc/hostname'), 'mocked');
        });

        // The layer has been popped — no mock data is active any more.
        assert.eq(proxy.readfile('/etc/hostname'), null);
    });
```

Run again and confirm all three tests pass.

---

## What we just built

- A `utest.config.uc` that declares `fs` as a mockable module.
- A test using `mock.inject()` to seed two virtual files.
- Confirmation that unseeded paths return `null` in non-strict mode.
- Confirmation that the mock layer is removed automatically after the callback.

---

## Next steps

- Mock the filesystem in detail (writefile, lsdir, glob, strict mode): [How-to: Mock the filesystem](../../how-to/mock-fs.md)
- Intercept calls through a real `import * as fs from 'fs'` binding: [How-to: Patch global state](../../how-to/mock-global-patch.md)
- Understand why two mock mechanisms exist: [About mock.inject() vs mock.global.patch()](../../explanation/inject-vs-patch.md)
- Make unmocked paths fail immediately: [How-to: Use strict mode](../../how-to/strict-mode.md)
