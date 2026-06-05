# How to add a built-in proxy

## 1. Create the proxy file

Create `src/utest/mock/proxy/<name>.uc`, where `<name>` matches the ucode module
name exactly (e.g. `mymod` for a module imported as `import * as mymod from 'mymod'`).

The file runs in **program mode** (not ES-module mode), so use a bare `return`
instead of `export`:

```js
// src/utest/mock/proxy/mymod.uc
// Loaded via require() in program mode — use return, not export.
return {
    create: function(name, real, ctx) {
        let proxy = ctx.base();   // start from the generic passthrough

        proxy.read = function(key) {
            let f = ctx.get_behavior('read');
            if (f) return f(key);                       // behavior override wins
            let v = ctx.get_data(key);
            if (v != null) return v;                    // mocked data wins
            if (ctx.is_strict())
                die("strict mock: 'mymod.read' called with unmocked key: " + key);
            return real ? real.read(key) : null;        // fall through to real
        };

        proxy.write = function(key, val) {
            let f = ctx.get_behavior('write');
            if (f) return f(key, val);
            if (ctx.is_active()) {
                ctx.set_data(key, val);
                return true;
            }
            return real ? real.write(key, val) : false;
        };

        return proxy;
    }
};
```

The `create(name, real, ctx)` signature is mandatory. `ctx` exposes the mock engine's registry operations for this module; see [Proxy context API reference](../../reference/contributor/proxy-ctx-api.md) for the full method list.

---

## 2. Declare a `channels` list for multiple data namespaces (optional)

If your proxy needs to store data under more than one logical namespace — for
example, when two different operations share a single mock object but must not
see each other's keys — declare extra channel names on the factory object:

```js
return {
    channels: ['commands'],   // extra channels beyond the default 'data'
    create: function(name, real, ctx) {
        // ...
        proxy.run = function(cmd) {
            let out = ctx.get('commands', cmd);   // look up in 'commands', not 'data'
            if (out != null) return out;
            // ...
        };
        return proxy;
    }
};
```

The engine creates a separate slot per channel in every layer, so keys in
`commands` are invisible to operations that enumerate `data` keys (and vice
versa). Callers seed each channel with a matching top-level key in the state
object:

```js
mock.inject('mymod', {
    data:     { mykey: 'value' },
    commands: { 'run foo': 'output' }
}, (m) => { ... });
```

The built-in `fs` proxy declares `channels: ['commands']` so that command
strings passed to `popen` are kept separate from the file-path `data` channel.

---

## 3. Declare an `api` list for absent modules (optional)

If `mymod` is not present on the target rootfs (common for optional packages),
the shim generator cannot introspect its exports. Add an `api` array so that a
stub shim is generated from the list instead:

```js
return {
    api: ['read', 'write', 'close'],   // exported function names
    create: function(name, real, ctx) {
        // ...
    }
};
```

Without `api`, the module is silently skipped when it cannot be found, and tests
that import it will fail at load time.

---

## 4. Write an example test

Add a test file in `examples/unit/` that exercises the new proxy. Follow the
existing numbering convention (`NN_<name>_test.uc`):

```js
// examples/unit/18_mymod_test.uc
import { describe, it, mock, assert } from 'utest';
import * as mymod from 'mymod';

describe('mymod mocking', () => {
    it('returns mocked data for read()', () => {
        mock.inject('mymod', { data: { mykey: 'hello' } }, (m) => {
            assert.match('hello', m.read('mykey'));
        });
    });

    it('records writes when active', () => {
        mock.inject('mymod', {}, (m) => {
            m.write('x', 42);
            assert.match(42, m.read('x'));
        });
    });

    it('patches global state via mock.global.patch()', () => {
        const m = mock.global.patch('mymod', { data: { greeting: 'hi' } });
        assert.match('hi', mymod.read('greeting'));
        mock.global.unpatch('mymod');
    });
});
```

---

## 5. Write a config file

Create a companion config file so the test runner knows to shim `mymod`:

```js
// examples/unit/18_mymod_config.uc
return {
    mocks: {
        mymod: null
    }
};
```

The runner looks for `<NN>_<name>_config.uc` alongside the test file
automatically when `make meta-test` is used.

---

## 6. Regenerate the baseline JSON

Run the example once with the `json` reporter and capture its output as the
regression baseline:

```bash
make test ARGS="-r json -c examples/unit/18_mymod_config.uc examples/unit/18_mymod_test.uc" \
    > test/json/unit/18_mymod_test.json
```

`make test` wraps `src/utest.sh` inside the official OpenWrt Docker image, so
the output reflects the target environment.

---

## Next steps

- Read the [proxy context API reference](../../reference/contributor/proxy-ctx-api.md)
  for the full `ctx` method list.
- Read [About shim generation](../../explanation/shim-generation.md) to understand
  why the config file is required.
- Run the full regression suite with `make meta-test` to confirm nothing is broken.
