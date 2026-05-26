# How to inspect calls with spy()

Use `spy()` to read the call history of a proxy object and assert which functions were called, with which arguments, and in what order.

---

## Import spy

`spy` is exported from `'utest'`:

```js
import { describe, it, assert, mock, spy, contains, any } from 'utest';
```

---

## Read call records from a proxy

Pass any proxy returned by `mock.inject()` or `mock.global.patch()` to `spy()`. It returns an object with a `calls` map — one key per method, each holding an array of argument arrays:

```js
describe('call recording', () => {
    it('records arguments in order', () => {
        mock.inject('fs', { data: { '/a': 'x', '/b': 'y' } }, (m_fs) => {
            m_fs.readfile('/a');
            m_fs.readfile('/b');
            assert.match([ ['/a'], ['/b'] ], spy(m_fs).calls.readfile);
        });
    });
});
```

---

## Verify that a method was not called

Check that the array for the method is empty:

```js
mock.inject('fs', {}, (m_fs) => {
    // no calls made
    assert.match([], spy(m_fs).calls.readfile);
});
```

---

## Verify multiple methods independently

Each method has its own entry in `calls`. Use `contains` to check only the methods you care about without specifying every method:

```js
mock.inject('fs', { data: {} }, (m_fs) => {
    m_fs.writefile('/out', 'hello');
    m_fs.access('/out', 'r');
    assert.match(contains({
        writefile: [ ['/out', 'hello'] ],
        access:    [ ['/out', 'r'] ]
    }), spy(m_fs).calls);
});
```

---

## Use any() to ignore specific arguments

When you care that a function was called but not what the exact arguments were:

```js
mock.inject('uloop', {}, (m_uloop) => {
    m_uloop.timer(100, () => {});
    m_uloop.timer(200, () => {});
    // verify timers were registered — ignore callback functions
    assert.match([
        [ 100, any() ],
        [ 200, any() ]
    ], spy(m_uloop).calls.timer);
});
```

---

## Spy on nested objects (cursors, connections)

For proxies that return inner objects (`uci.cursor()`, `ubus.connect()`, `uclient.new()`), call `spy()` on the inner object:

```js
mock.inject('uci', {
    data: { network: { wan: { '.type': 'interface', proto: 'dhcp' } } }
}, (m_uci) => {
    let cursor = m_uci.cursor();
    cursor.get('network', 'wan', 'proto');
    cursor.set('network', 'wan', 'proto', 'static');
    assert.match(contains({
        get: [ ['network', 'wan', 'proto'] ],
        set: [ ['network', 'wan', 'proto', 'static'] ]
    }), spy(cursor).calls);
});
```

Each `cursor()` call returns an independent object with its own call log:

```js
mock.inject('uci', { data: {} }, (m_uci) => {
    let c1 = m_uci.cursor();
    let c2 = m_uci.cursor();
    c1.get('net', 'sec', 'opt');
    assert.match([ ['net', 'sec', 'opt'] ], spy(c1).calls.get);
    assert.match([], spy(c2).calls.get);
});
```

---

## Verify calls made through global.patch()

`spy()` works on proxies from `mock.global.patch()` just as with `mock.inject()`:

```js
// import at top of file
import * as fs from 'fs';

const m_fs = mock.global.patch('fs', { data: { '/g': 'global' } });
fs.readfile('/g');
assert.match([ ['/g'] ], spy(m_fs).calls.readfile);
mock.global.unpatch('fs');
```

---

## Call records reset between inject() scopes

A new `mock.inject()` call starts with empty call records — it does not inherit calls from a previous inject on the same module:

```js
mock.inject('fs', { data: { '/a': 'x' } }, (m_fs) => {
    m_fs.readfile('/a');
    assert.match([ ['/a'] ], spy(m_fs).calls.readfile);
});

mock.inject('fs', { data: { '/a': 'x' } }, (m_fs) => {
    // fresh scope — no calls yet
    assert.match([], spy(m_fs).calls.readfile);
});
```

---

## Next steps

- Use combinators inside spy assertions: [How-to: Use combinators with assert.match()](combinators.md)
- Understand how proxies work: [About the mocking architecture](../explanation/concepts.md)
- See the full spy API: [Reference: Mock API — spy()](../reference/mock-api.md#call-inspection)
