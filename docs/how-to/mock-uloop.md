# How to mock the event loop

Replace `uloop`'s event loop with a synchronous queue so timer-driven code is testable without real waits.

---

## Declare the module in the config file

Add `uloop` to the `mocks` table in the config file:

```js
return {
    mocks: {
        uloop: null
    }
};
```

`uloop` is not present on the OpenWrt rootfs that utest uses when running tests. The framework detects this and generates a shim automatically from the built-in proxy's `api` list (`init`, `timer`, `run`, `end`), so the module can still be imported and mocked.

---

## Queue callbacks with timer()

`timer(ms, callback)` registers a callback in the proxy's internal queue. The millisecond value is accepted but has no timing effect — callbacks fire when `run()` is called, not after a delay:

```js
import { describe, it, mock } from 'utest';
import { assert } from 'utest.assert';
import * as uloop from 'uloop';

describe('uloop mock', () => {
    it('run() fires registered timer callbacks synchronously', () => {
        mock.inject('uloop', {}, (m_uloop) => {
            let fired = false;
            m_uloop.timer(1000, () => { fired = true; });
            assert.notOk(fired);
            m_uloop.run();
            assert.ok(fired);
        });
    });
});
```

---

## run() fires all queued callbacks in registration order

`run()` drains the queue synchronously. Multiple timers fire in the order they were registered, regardless of their millisecond values:

```js
mock.inject('uloop', {}, (m_uloop) => {
    let order = [];
    m_uloop.timer(3000, () => push(order, 'a'));
    m_uloop.timer(1000, () => push(order, 'b'));
    m_uloop.run();
    assert.eq(order, ['a', 'b']);
});
```

After `run()` empties the queue, a second `run()` call does nothing:

```js
mock.inject('uloop', {}, (m_uloop) => {
    let count = 0;
    m_uloop.timer(100, () => count++);
    m_uloop.run();
    m_uloop.run();
    assert.eq(count, 1);
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
    assert.ok(done);
});
```

---

## Model the io.sleep() pattern without blocking

Code that initialises uloop, schedules a timer, and then calls `run()` to sleep for a duration is testable without any real delay:

```js
mock.inject('uloop', {}, (m_uloop) => {
    let ended = false;
    m_uloop.init();
    m_uloop.timer(5000, () => { m_uloop.end(); ended = true; });
    m_uloop.run();
    assert.ok(ended, 'sleep returned without blocking');
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
    assert.ok(run_called);
});
```

---

## Next steps

- Intercept calls through the imported `uloop` binding: [How-to: Patch global state with mock.global.patch()](mock-global-patch.md)
- Mock outgoing HTTP requests: [How-to: Mock HTTP requests with uclient](mock-uclient.md)
- Write a proxy for a module that is absent from rootfs: [How-to: Write a custom proxy](custom-proxy.md)
