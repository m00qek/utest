# CLI and Configuration Reference

---

## CLI flags

Invoke as `utest [options] [<bundle>...]`. Each positional argument is a bundle in the form `[Name:]path`. If `path` does not end in `.uc` it is treated as a directory prefix and the active `pattern` (from config) is appended. When no positional arguments are given, utest scans `test/unit/*_test.uc`.

| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `-h` | boolean | — | Print usage and exit. |
| `-r <fmt>` | string | `detailed` | Output format. Accepted values: `detailed`, `compact`, `json`. |
| `-f <regex>` | string | — | Run only tests whose full name matches the regex. |
| `-c <path>` | string | `utest.config.uc` | Path to the configuration file. Fatal if the path is given explicitly but not found. When the default path is absent, utest starts normally with no mocks declared. |
| `-l <path>` | string | — | Prepend a directory to the module search path. Repeatable. |
| `-j <n>` | integer | — | Number of parallel workers. Overrides `jobs` in the configuration file. |
| `-s <seed>` | integer | — | Fix the random seed. Controls both test-file shuffle order and the default seed for all property tests. Use to reproduce a CI failure locally. |

---

## Configuration file

`utest.config.uc` is a ucode file evaluated at startup. It must return a plain object (table). CLI flags override matching configuration keys.

| Key | Type | Description |
| :--- | :--- | :--- |
| `mocks` | object | Map of module names to mock declarations. See [The `mocks` key](#the-mocks-key). |
| `reporter` | string | Default reporter format (`detailed`, `compact`, `json`). |
| `jobs` | integer | Default number of parallel workers. |
| `filter` | string | Default test-name filter regex. |
| `pattern` | string | Default file glob pattern. |
| `color` | boolean | Set to `false` to disable colour output. |
| `timeout` | integer | Default worker timeout in seconds. |
| `lib_paths` | array of strings | Additional directories to append to the module search path. Relative paths are resolved against the directory containing the configuration file, not the working directory. |

---

## The `mocks` key

The `mocks` object tells utest which modules to intercept and how.

**Null form** — generate a shim that routes calls through the mock engine. The built-in proxy for the module is used if one exists; otherwise a generic passthrough proxy is generated.

```js
mocks: {
    'ubus': null,
    'uci':  null
}
```

**Proxy form** — same as the null form, but load a custom proxy factory from the given path instead of the built-in one.

```js
mocks: {
    'mymodule': { proxy: 'test/mocks/mymodule_proxy.uc' }
}
```

A module that is not listed in `mocks` is never intercepted; `import * as mod from 'mymodule'` always returns the real module.

---

## Example configuration file

```js
return {
    reporter:  'compact',
    jobs:      4,
    timeout:   30,
    color:     true,
    filter:    null,
    pattern:   '*_test.uc',
    lib_paths: ['lib'],
    mocks: {
        'fs':      null,
        'ubus':    null,
        'uci':     null,
        'uloop':   null,
        'uclient': null
    }
};
```
