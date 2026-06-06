# How to mock a built-in global

Use `mock.inject_builtin()` or `mock.global.patch_builtin()` to intercept built-in globals such as `warn`, `system`, and `print` that are not loadable modules and therefore unreachable via the shim-based mock API.

---

## Capture warn() output for a single test

Use `mock.inject_builtin()` when the interception should be scoped to one test. Pass the name of the built-in, the replacement function, and a callback. The original is restored when the callback returns — or throws:

```js
import { describe, it, assert, mock, contains } from 'utest';

describe('my module', () => {
    it('emits a deprecation warning', () => {
        const captured = [];
        mock.inject_builtin('warn', (...args) => push(captured, join('', args)), () => {
            my_module.deprecated_function();
        });
        assert.match(contains('deprecated'), join('\n', captured));
    });
});
```

The original `warn` function is unconditionally restored when the callback exits. If an assertion inside the callback throws, the restore still happens before the exception propagates.

---

## Suppress warn() output for an entire describe block

Use `mock.global.patch_builtin()` when you want the replacement to persist across multiple tests. Call `mock.global.unpatch_builtin()` in an `afterEach` or at the end of the block:

```js
import { describe, it, afterEach, mock } from 'utest';

describe('noisy module', () => {
    afterEach(() => { mock.global.unpatch_builtin('warn'); });

    it('does not spam stderr', () => {
        mock.global.patch_builtin('warn', () => null);
        noisy_module.run();
        // no assertion about warn output — just suppress it
    });

    it('still works when warn is suppressed', () => {
        mock.global.patch_builtin('warn', () => null);
        assert.match('ok', noisy_module.result());
    });
});
```

Forgetting to call `unpatch_builtin()` leaks the replacement into subsequent tests. Use `afterEach` to ensure cleanup runs even when tests fail.

---

## Intercept system() calls

The same API works for any built-in global. To verify that production code calls `system()` with the right argument:

```js
it('invokes nft with the generated ruleset path', () => {
    const calls = [];
    mock.inject_builtin('system', (cmd) => { push(calls, cmd); return 0; }, () => {
        fw4.apply_ruleset('/tmp/fw4.nft');
    });
    assert.match(1, length(calls));
    assert.match(contains('/tmp/fw4.nft'), calls[0]);
});
```

The replacement receives the same arguments as the real built-in and its return value is used by the caller. Return a sensible value — `system()` returns the exit code, so returning `0` signals success.

---

## Layer inject_builtin on top of patch_builtin

If a persistent patch is already active and you need a tighter scope within one test, `inject_builtin` layers correctly on top of it:

```js
describe('layering', () => {
    afterEach(() => { mock.global.unpatch_builtin('warn'); });

    it('uses a narrower replacement inside the callback', () => {
        const outer = [];
        const inner = [];
        mock.global.patch_builtin('warn', (...a) => push(outer, join('', a)));

        mock.inject_builtin('warn', (...a) => push(inner, join('', a)), () => {
            warn('inside');
        });

        warn('outside');
        // inner captured the call made inside the callback
        assert.match(['inside'], inner);
        // outer captured the call made after the callback returned
        assert.match(['outside'], outer);
    });
});
```

`inject_builtin` saves whatever is currently in `global.warn` at the time of the call — the patched function — and restores it when its callback exits. The persistent patch remains active after `inject_builtin` returns.

---

## Next steps

- Understand why built-ins need a different API: [About mock.inject() vs mock.global.patch()](../explanation/inject-vs-patch.md#built-in-globals)
- See the full API: [Mock API Reference — mock.inject_builtin()](../reference/mock-api.md#mockinject_builtinname-fn-cb)
- Intercept a loadable module instead: [How-to: Patch global state with mock.global.patch()](mock-global-patch.md)
