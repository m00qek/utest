# Reference

Authoritative descriptions of every public interface in utest. Each page documents a distinct layer of the framework.

---

| Page | Description |
| :--- | :--- |
| [Glossary](glossary.md) | Definitions of every term used in this documentation: test, suite, bundle, mock, shim, proxy, layer, behavior override, strict mode, worker, coordinator. |
| [CLI and Configuration](cli.md) | Command-line flags, `utest.config.uc` format, and all recognised configuration keys including the `mocks` declaration. |
| [DSL](dsl.md) | All suite-structure and hook functions importable from `'utest'`: `describe`, `it`, `skip`, `xit`, `xdescribe`, `beforeEach`, `afterEach`, `setup`, and `teardown`. |
| [Assertions](assertions.md) | Every assertion on the `assert` object from `'utest.assert'`: `eq`, `ok`, `ne`, `notOk`, `match`, `notMatch`, `throws`, `notThrows`, and `contains`. |
| [Mock API](mock-api.md) | The `mock` object from `'utest'`: scoped injection, global patch/unpatch, snapshot, and restore. |
| [Proxy Data Models](proxy-data-models.md) | The `data` key format accepted by each built-in proxy: `fs`, `uci`, `ubus`, `uloop`, and `uclient`. |
