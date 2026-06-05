# Reference

Authoritative descriptions of every public interface in utest. Each page documents a distinct layer of the framework.

---

| Page | Description |
| :--- | :--- |
| [Glossary](glossary.md) | Definitions of every term used in this documentation: test, suite, bundle, mock, shim, proxy, layer, behavior override, strict mode, worker, coordinator. |
| [CLI and Configuration](cli.md) | Command-line flags, `utest.config.uc` format, and all recognised configuration keys including the `mocks` declaration. |
| [DSL](dsl.md) | All suite-structure and hook functions importable from `'utest'`: `describe`, `it`, `skip`, `xit`, `xdescribe`, `beforeEach`, `afterEach`, `setup`, and `teardown`. |
| [Assertions](assertions.md) | Every assertion on the `assert` object, plus the combinator factories (`equals`, `contains`, `truthy`, `falsy`, `not`, `pred`, `regex`, `any`, `any_order`, `starts_with`, `ends_with`, `has_length`, `between`, `is_type`). All imported from `'utest'`. |
| [Mock API](mock-api.md) | The `mock` object and `spy()` function from `'utest'`: scoped injection, global patch/unpatch, snapshot, restore, and call inspection. |
| [Proxy Data Models](proxy-data-models.md) | The `data` key format accepted by each built-in proxy: `fs`, `uci`, `ubus`, `uloop`, and `uclient`. |
