# How to save and restore mock state

Use `mock.snapshot()` and `mock.restore()` to checkpoint the global mock
registry and roll it back to that checkpoint later. This is useful when a test
or a setup block installs global state that should not outlast a particular
scope.

---

## Save a snapshot and restore it after a test

Take a snapshot before the test body and restore it afterwards. Any
`mock.global.patch()` call made inside the test — including a missed
`unpatch()` — is rolled back automatically:

```js
import { describe, it, assert, mock } from 'utest';
import * as fs from 'fs';

describe('my module', () => {
    it('does not require manual cleanup', () => {
        const snap = mock.snapshot();

        mock.global.patch('fs', { data: { '/etc/myapp.conf': 'debug=0' } });

        assert.match('debug=0', fs.readfile('/etc/myapp.conf'));

        mock.restore(snap);

        assert.match(null, fs.readfile('/etc/myapp.conf'), 'global patch is gone');
    });
});
```

---

## Use beforeEach and afterEach to bracket an entire describe block

Take the snapshot once in `beforeEach` and restore it in `afterEach`. Every
test in the block starts from the same clean baseline and any patch it forgets
to clean up is silently recovered:

```js
import { describe, it, beforeEach, afterEach, assert, mock } from 'utest';
import * as fs from 'fs';

describe('suite with shared baseline', () => {
    let snap;

    beforeEach(() => {
        // Establish a known starting state before each test.
        mock.global.patch('fs', { data: { '/etc/base.conf': 'v=1' } });
        snap = mock.snapshot();
    });

    afterEach(() => {
        mock.restore(snap);
    });

    it('can override the baseline in the test body', () => {
        mock.global.patch('fs', { data: { '/etc/base.conf': 'v=2' } });
        assert.match('v=2', fs.readfile('/etc/base.conf'));
        // afterEach restores to the pre-test snapshot regardless
    });

    it('starts clean even though the previous test patched', () => {
        assert.match('v=1', fs.readfile('/etc/base.conf'), 'previous override is gone');
    });
});
```

---

## What a snapshot captures

`mock.snapshot()` saves the global state of every module that has been
registered with the mock engine at the moment of the call:

| Captured | Not captured |
| :--- | :--- |
| Data from `mock.global.patch()` | Transient layers from `mock.inject()` |
| Behavior overrides from `mock.global.patch()` | |
| The `strict` flag | |
| The proxy object | |

Scoped `mock.inject()` layers are not included in a snapshot because they are
already guaranteed to be popped when their own callback exits. A snapshot taken
inside a `mock.inject()` callback will not capture that layer.

---

## Difference between restore() and reset()

Both functions clear all active `mock.inject()` layers, but they differ in what
they do to global state:

| | `mock.restore(snap)` | `mock.reset()` |
| :--- | :--- | :--- |
| Clears inject() layers | Yes | Yes |
| Resets global.patch() state | Yes — reverts to the snapshot | No — global patches remain active |

Use `restore()` when you want to return to a known checkpoint.  
Use `reset()` only when you want to clear transient layers mid-test without
touching global state — for example, to reset inner injection state without
unpatching a module installed at suite scope.

---

## Restore is always safe to call with the same snapshot twice

Each `mock.restore()` call deep-clones the snapshot's channel data before
writing it into the registry. Calling `restore(snap)` a second time after
modifying state produces exactly the same result as the first call — the
snapshot itself is never mutated:

```js
const snap = mock.snapshot();

mock.global.patch('fs', { data: { '/a': '1' } });
mock.restore(snap);    // state is clean

mock.global.patch('fs', { data: { '/b': '2' } });
mock.restore(snap);    // state is clean again — snap is unchanged
```

---

## Next steps

- Understand why snapshot/restore runs around every test automatically:
  [About the mock engine](../explanation/mock-engine.md#why-snapshotrestore-runs-around-every-test)
- See the full API: [Reference: Mock API — snapshot and restore](../reference/mock-api.md#snapshot-and-restore)
- Understand scoped vs global mocking: [About mock.inject() vs mock.global.patch()](../explanation/inject-vs-patch.md)
