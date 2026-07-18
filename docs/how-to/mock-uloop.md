# How to mock the event loop

Declare `uloop: null` in your `utest.config.uc` `mocks` table. See [How-to: Mock a module with mock.inject()](mock-inject.md) for the setup steps.

---

## Queue callbacks with timer()

`timer(ms, callback)` registers a callback and returns a handle (see [Cancel or re-arm a timer](#cancel-or-re-arm-a-timer)). No wall-clock time passes — callbacks fire when `run()` is called, not after a real delay — but `ms` is the callback's *deadline* and determines firing order:

```js
import { describe, it, mock, assert, truthy, falsy } from 'utest';
import * as uloop from 'uloop';

describe('uloop mock', () => {
    it('run() fires registered timer callbacks synchronously', () => {
        mock.inject('uloop', {}, (m_uloop) => {
            let fired = false;
            m_uloop.timer(1000, () => { fired = true; });
            assert.match(falsy(), fired);
            m_uloop.run();
            assert.match(truthy(), fired);
        });
    });
});
```

---

## run() fires queued callbacks in deadline order

`run()` drains the queue synchronously, firing callbacks in ascending `ms` (deadline) order — like the real uloop, and regardless of registration order. Timers with the same `ms` fire in registration order:

```js
mock.inject('uloop', {}, (m_uloop) => {
    let order = [];
    m_uloop.timer(3000, () => push(order, 'a'));
    m_uloop.timer(1000, () => push(order, 'b'));
    m_uloop.run();
    assert.match(['b', 'a'], order);   // 1000 ms fires before 3000 ms
});
```

After `run()` empties the queue, a second `run()` call does nothing:

```js
mock.inject('uloop', {}, (m_uloop) => {
    let count = 0;
    m_uloop.timer(100, () => count++);
    m_uloop.run();
    m_uloop.run();
    assert.match(1, count);
});
```

---

## Cancel or re-arm a timer

`timer()` returns a handle that mirrors the real `uloop.timer` resource, so code under test that stores a timer to reschedule or cancel it works under the mock. The handle exposes `remaining()` (the armed deadline, or `-1` once cancelled — the mock has no clock), `cancel()` (a cancelled timer is skipped by `run()`), and `set(ms)` (re-arm, clearing a prior cancel). `cancel()` and `set()` return the handle for chaining:

```js
mock.inject('uloop', {}, (m_uloop) => {
    let fired = [];
    let h = m_uloop.timer(500, () => push(fired, 'x'));
    assert.match(500, h.remaining());

    h.cancel();
    assert.match(-1, h.remaining());
    m_uloop.run();
    assert.match([], fired);            // a cancelled timer never fires
});
```

`set()` re-arms with a new deadline, and `run()` sorts on each timer's *current* `ms`, so a `set()` before `run()` reschedules correctly:

```js
mock.inject('uloop', {}, (m_uloop) => {
    let order = [];
    let a = m_uloop.timer(3000, () => push(order, 'a'));
    m_uloop.timer(1000, () => push(order, 'b'));
    a.set(100);                         // 'a' is now the earliest deadline
    m_uloop.run();
    assert.match(['a', 'b'], order);
});
```

---

## end() is a no-op

`end()` accepts a call and does nothing. Code that calls `uloop.end()` from inside a timer callback to signal loop termination will compile and run cleanly under the mock:

```js
mock.inject('uloop', {}, (m_uloop) => {
    let done = false;
    m_uloop.timer(0, () => { m_uloop.end(); done = true; });
    m_uloop.run();
    assert.match(truthy(), done);
});
```

---

## Model the io.sleep() pattern without blocking

```js
mock.inject('uloop', {}, (m_uloop) => {
    let ended = false;
    m_uloop.init();
    m_uloop.timer(5000, () => { m_uloop.end(); ended = true; });
    m_uloop.run();
    assert.match(truthy(), ended, 'sleep returned without blocking');
});
```

---

## Override run() behavior

If you need to verify that `run()` is called, or prevent it from draining the queue, supply a `behavior.run` function:

```js
let run_called = false;
mock.inject('uloop', {
    behavior: { run: () => { run_called = true; } }
}, (m_uloop) => {
    m_uloop.timer(100, () => {});
    m_uloop.run();
});
assert.match(truthy(), run_called);
```

---

## Next steps

- Intercept calls through the imported `uloop` binding: [How-to: Patch global state with mock.global.patch()](mock-global-patch.md)
- Mock outgoing HTTP requests: [How-to: Mock HTTP requests with uclient](mock-uclient.md)
- Write a proxy for a module that is absent from rootfs: [How-to: Write a custom proxy](custom-proxy.md)
