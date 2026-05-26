# How to mock HTTP requests with uclient

Replace outgoing HTTP calls with canned responses so your tests run without a network connection.

Declare `uclient: null` in your `utest.config.uc` `mocks` table. `uclient` is absent from some rootfs variants — declaring it is still enough because the framework generates a stub shim from the known API list. See [How-to: Mock a module with mock.inject()](mock-inject.md) for the general setup steps.

---

## Seed URL-keyed response data

Each key in the `data` map is a full request URL. The value describes the response.

For a successful response, supply `{ status, headers, body }`:

```js
import { describe, it, mock, assert, falsy } from 'utest';

describe('uclient mock', () => {
    it('fires callbacks for a successful response', () => {
        const url = 'http://api.example.com/items';
        mock.inject('uclient', {
            data: { [url]: { status: 200, headers: { 'content-type': 'application/json' }, body: '[]' } }
        }, (m_uclient) => {
            let events = [];
            let u = m_uclient.new(url, null, {
                header_done: () => push(events, 'header_done'),
                data_read:   () => push(events, 'data_read'),
                data_eof:    () => push(events, 'data_eof')
            });
            u.request('GET', {});
            assert.match(['header_done', 'data_read', 'data_eof'], events);
        });
    });
});
```

For an error response, supply `{ error: code }`:

```js
mock.inject('uclient', {
    data: { 'http://api.example.com/broken': { error: 'connection_refused' } }
}, (m_uclient) => {
    let got_error = null;
    let u = m_uclient.new('http://api.example.com/broken', null, {
        error: (conn, code) => { got_error = code; }
    });
    u.request('GET', {});
    assert.match('connection_refused', got_error);
});
```

---

## Callback firing order

When a successful response is found, `request()` fires callbacks in this order:

1. `header_done` — always fired
2. `data_read` — fired only when `body` is not `null`
3. `data_eof` — always fired

All callbacks fire synchronously inside `request()`. No event loop is required.

---

## Read status and headers inside header_done

The connection object passed to each callback exposes `status()` and `get_headers()`. Read them inside `header_done` to inspect the response metadata:

```js
const url = 'http://api.example.com/status';
mock.inject('uclient', {
    data: { [url]: { status: 201, headers: { 'x-custom': 'yes' }, body: '' } }
}, (m_uclient) => {
    let got_status = null;
    let got_headers = null;
    let u = m_uclient.new(url, null, {
        header_done: (conn) => {
            got_status = conn.status().status;
            got_headers = conn.get_headers();
        },
        data_read: () => {},
        data_eof:  () => {}
    });
    u.request('GET', {});
    assert.match(201, got_status);
    assert.match('yes', got_headers['x-custom']);
});
```

---

## read() loop pattern

Inside `data_read`, call `conn.read()` in a loop until it returns `null`. The mock returns the body string on the first call and `null` on all subsequent calls, matching the real uclient read loop:

```js
const url = 'http://api.example.com/body';
mock.inject('uclient', {
    data: { [url]: { status: 200, headers: {}, body: 'hello world' } }
}, (m_uclient) => {
    let chunks = [];
    let u = m_uclient.new(url, null, {
        data_read: (conn) => {
            let chunk;
            while ((chunk = conn.read()) != null) push(chunks, chunk);
        },
        header_done: () => {},
        data_eof:    () => {}
    });
    u.request('GET', {});
    assert.match(['hello world'], chunks);
});
```

---

## null body skips data_read

Set `body: null` to model a response with no body (such as HTTP 204). `data_read` is not called:

```js
const url = 'http://api.example.com/no-content';
mock.inject('uclient', {
    data: { [url]: { status: 204, headers: {}, body: null } }
}, (m_uclient) => {
    let data_read_fired = false;
    let u = m_uclient.new(url, null, {
        header_done: () => {},
        data_read:   () => { data_read_fired = true; },
        data_eof:    () => {}
    });
    u.request('GET', {});
    assert.match(falsy(), data_read_fired);
});
```

---

## Simulate connect() failure with behavior override

Supply `behavior.connect` to make connection setup fail. Code that checks the return value of `connect()` before proceeding can be exercised without triggering any request:

```js
mock.inject('uclient', {
    behavior: { connect: () => false }
}, (m_uclient) => {
    let u = m_uclient.new('http://example.com/', null, {});
    assert.match(false, u.connect());
});
```

---

## Next steps

- Fail loudly when an unmocked URL is requested: [How-to: Use strict mode](strict-mode.md)
- Intercept calls through the imported `uclient` binding: [How-to: Patch global state with mock.global.patch()](mock-global-patch.md)
- Mock the event loop that drives uclient: [How-to: Mock the event loop](mock-uloop.md)
