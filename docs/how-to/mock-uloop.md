# How to mock the event loop

Declare `uloop: null` in your `utest.config.uc` `mocks` table. See [How-to: Mock a module with mock.inject()](mock-inject.md) for the setup steps.

---

## Queue callbacks with timer()

`timer(ms, callback)` registers a callback in the proxy's internal queue. The millisecond value is accepted but has no timing effect — callbacks fire when `run()` is called, not after a delay:

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

## run() fires all queued callbacks in registration order

`run()` drains the queue synchronously. Multiple timers fire in the order they were registered, regardless of their millisecond values:

```js
mock.inject('uloop', {}, (m_uloop) => {
    let order = [];
    m_uloop.timer(3000, () => push(order, 'a'));
    m_uloop.timer(1000, () => push(order, 'b'));
    m_uloop.run();
    assert.match(['a', 'b'], order);
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
