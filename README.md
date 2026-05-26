# utest

A modern, non-invasive testing framework for [ucode](https://github.com/jow-/ucode), OpenWrt's scripting language.

```js
import { describe, it, assert } from 'utest';

describe("add()", () => {
    it("returns the sum of two numbers", () => {
        assert.match(5, add(2, 3));
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
- **Assertions** — `assert.match(expected, actual)` with composable combinators: `equals`, `contains`, `truthy`, `falsy`, `not`, `pred`, `regex`, `any`, `any_order`
- **Built-in mock proxies** — `fs`, `uci`, `ubus`, `uloop`, `uclient`
- **Non-invasive** — no changes to the code under test; shims are generated at startup
- **Parallel execution** — run test files concurrently with `--jobs=N`
- **Multiple reporters** — `detailed`, `compact`, `json`

---

## Installation

**On OpenWrt** (from the package feed):

```bash
# OpenWrt ≤ 24.10
opkg install ucode-utest

# OpenWrt ≥ 25.12
apk add ucode-utest
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
import { describe, it, assert } from 'utest';

describe("example", () => {
    it("passes", () => {
        assert.match(2, 1 + 1);
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
import { describe, it, assert, mock } from 'utest';

describe("read_config()", () => {
    it("returns file content", () => {
        mock.inject('fs', { data: { '/etc/config': 'hello' } }, (fs) => {
            assert.match('hello', fs.readfile('/etc/config'));
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
