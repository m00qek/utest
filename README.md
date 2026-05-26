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
```

---

## Installation

**OpenWrt ≤ 24.10**:
```bash
opkg install ucode-utest
```

**OpenWrt ≥ 25.12**:
```bash
apk add ucode-utest
```

---

## Documentation

**[m00qek.github.io/utest](https://m00qek.github.io/utest/)**

| | |
| :--- | :--- |
| [Tutorials](https://m00qek.github.io/utest/tutorials/) | Start here — write your first test, mock, and assertion |
| [How-to Guides](https://m00qek.github.io/utest/how-to/) | Recipes for mocking, CI, filtering, custom proxies, and more |
| [Reference](https://m00qek.github.io/utest/reference/) | CLI flags, DSL, assertion and mock API |
| [Explanation](https://m00qek.github.io/utest/explanation/) | Design decisions and architecture |

---

## License

MIT — see [LICENSE](LICENSE).
