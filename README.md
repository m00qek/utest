# utest

A modern, non-invasive testing framework for [ucode](https://github.com/jow-/ucode), OpenWrt's scripting language.

```js
import { describe, it } from 'utest';
import { assert } from 'utest.assert';

describe("add()", () => {
    it("returns the sum of two numbers", () => {
        assert.eq(add(2, 3), 5);
    });
});
```

```
[test/unit/add_test.uc] add_test.uc
  [PASS] returns the sum of two numbers
Summary:
  Suites: 1
  Total:  1
  Passed: 1
  Failed: 0
  Errors: 0
  Time:   4 ms
  Seed:   ...
```

---

## Features

- **Jasmine-style DSL** — `describe`, `it`, `beforeEach`, `afterEach`, `setup`, `teardown`
- **9 assertions** — `eq`, `ne`, `ok`, `notOk`, `match`, `notMatch`, `throws`, `notThrows`, `contains`
- **Built-in mock proxies** — `fs`, `uci`, `ubus`, `uloop`, `uclient`
- **Non-invasive** — no changes to the code under test; shims are generated at startup
- **Parallel execution** — run test files concurrently with `--jobs=N`
- **Multiple reporters** — `detailed`, `compact`, `json`

---

## Installation

**On OpenWrt** (from the package feed):

```bash
opkg install ucode-utest
```

**For development** (requires Docker and GNU make):

```bash
git clone https://github.com/m00qek/utest
cd utest
make -f dev.mk test ARGS="--help"
```

`make -f dev.mk test` runs tests inside the official OpenWrt Docker image. No SDK or cross-compiler needed on the host.

---

## Quick start

1. Create `test/unit/example_test.uc`:

```js
import { describe, it } from 'utest';
import { assert } from 'utest.assert';

describe("example", () => {
    it("passes", () => {
        assert.eq(1 + 1, 2);
    });
});
```

2. Run it:

```bash
make -f dev.mk test
```

3. To mock a module, declare it in `utest.config.uc` and use `mock.inject()` in your test:

```js
// utest.config.uc
return { mocks: { 'fs': null } };
```

```js
import { describe, it } from 'utest';
import { assert } from 'utest.assert';
import { mock } from 'utest';

describe("read_config()", () => {
    it("returns file content", () => {
        mock.inject('fs', { data: { '/etc/config': 'hello' } }, (fs) => {
            assert.eq(fs.readfile('/etc/config'), 'hello');
        });
    });
});
```

---

## Documentation

Full documentation lives at **[m00qek.github.io/utest](https://m00qek.github.io/utest/)**.

| Section | Contents |
| :--- | :--- |
| [Tutorials](https://m00qek.github.io/utest/tutorials/) | Step-by-step guides for new users |
| [How-to Guides](https://m00qek.github.io/utest/how-to/) | Task-oriented recipes (CI, mocking, filtering, …) |
| [Reference](https://m00qek.github.io/utest/reference/) | CLI flags, DSL, assertion and mock API |
| [Explanation](https://m00qek.github.io/utest/explanation/) | Design decisions and architecture |

---

## License

MIT — see [LICENSE](LICENSE).
