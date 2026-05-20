# How-to Guides

Practical directions for common tasks. Each guide assumes you already have a working test suite — see the [tutorial](../tutorials/index.md) if you are starting from zero.

---

## Testing

| Guide | Goal |
| :--- | :--- |
| [Skip tests temporarily](skip-tests.md) | Disable a test or block without deleting it |
| [Filter tests by name](filter-tests.md) | Run a subset of tests during development |
| [Run tests in CI](ci.md) | Integrate utest into a CI pipeline |
| [Troubleshoot common problems](troubleshoot.md) | Diagnose and fix frequent failures |

---

## Mocking

| Guide | Goal |
| :--- | :--- |
| [Mock a module with inject()](mock-inject.md) | Scoped mock for code that receives a module as a parameter |
| [Patch global state](mock-global-patch.md) | Replace the module import itself for the duration of a test |
| [Mock the filesystem](mock-fs.md) | Intercept `fs` calls with virtual files |
| [Mock UCI configuration](mock-uci.md) | Provide test UCI packages without touching the real config |
| [Mock ubus calls](mock-ubus.md) | Stub ubus object/method responses |
| [Mock the event loop](mock-uloop.md) | Run timer callbacks synchronously without blocking |
| [Mock HTTP requests](mock-uclient.md) | Return canned responses for outbound HTTP |
| [Use strict mode](strict-mode.md) | Fail loudly on any unmocked call |
| [Write a custom proxy](custom-proxy.md) | Build a proxy for a module with no built-in support |

---

## Contributing

| Guide | Goal |
| :--- | :--- |
| [Add a built-in proxy](contributor/add-proxy.md) | Ship a proxy for a new module inside the framework |
| [Add an assertion](contributor/add-assertion.md) | Extend the `assert` object with a new helper |
| [Add a reporter](contributor/add-reporter.md) | Add a new output format |
| [Run the regression suite](contributor/run-regression.md) | Verify no examples regressed after a change |
