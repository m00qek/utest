# How to mock ubus calls

Replace ubus IPC calls with canned responses so your tests run without a running ubus daemon.

Declare `ubus: null` in your `utest.config.uc` `mocks` table before using any of the patterns below. See [How-to: Mock a module with mock.inject()](mock-inject.md) for the setup steps.

---

## Seed data with the object:method key format

Each key in the `data` map uses `'object:method'` format. The value is returned as the result of `conn.call(object, method, args)`:

```js
import { describe, it, mock, assert, truthy, falsy } from 'utest';

describe('ubus mock', () => {
    it('returns mocked data for object:method key', () => {
        mock.inject('ubus', {
            data: { 'system:board': { model: 'Test Router', hostname: 'OpenWrt' } }
        }, (m_ubus) => {
            let conn = m_ubus.connect();
            assert.match({ model: 'Test Router', hostname: 'OpenWrt' }, conn.call('system', 'board', {}));
        });
    });
});
```

---

## Object-only fallback

Use a bare object name (without `:method`) as a catch-all for any method on that object. The object-only key is tried when no `object:method` key matches:

```js
mock.inject('ubus', {
    data: { 'network': { up: true } }
}, (m_ubus) => {
    let conn = m_ubus.connect();
    assert.match(truthy(), conn.call('network', 'status', {}).up);
    assert.match(truthy(), conn.call('network', 'get_status', {}).up);
});
```

---

## Static vs function values for dynamic responses

Set the value to a plain object for a static response, or to a function for a dynamic one. The function receives the `args` passed to `call()` and must return the response:

```js
mock.inject('ubus', {
    data: { 'network:status': (args) => ({ up: args.interface == 'wan' }) }
}, (m_ubus) => {
    let conn = m_ubus.connect();
    assert.match(truthy(), conn.call('network', 'status', { interface: 'wan' }).up);
    assert.match(falsy(), conn.call('network', 'status', { interface: 'lan' }).up);
});
```

---

## Unmocked calls in non-strict mode

In non-strict mode, calling an unmocked object/method returns `null`:

```js
mock.inject('ubus', { data: {} }, (m_ubus) => {
    assert.match(null, m_ubus.connect().call('unmocked', 'method', {}));
});
```

---

## Override call behavior entirely

Supply a `behavior.call` function to intercept all `call()` invocations regardless of their arguments:

```js
mock.inject('ubus', {
    behavior: { call: (obj, method, args) => ({ routed: obj + '.' + method }) }
}, (m_ubus) => {
    assert.match('system.board', m_ubus.connect().call('system', 'board', {}).routed);
});
```

---

## Next steps

- Fail loudly on unmocked calls: [How-to: Use strict mode](strict-mode.md)
- Intercept calls through the imported `ubus` binding: [How-to: Patch global state with mock.global.patch()](mock-global-patch.md)
- Mock UCI configuration: [How-to: Mock UCI](mock-uci.md)
