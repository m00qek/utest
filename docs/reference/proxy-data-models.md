# Proxy Data Models Reference

This page documents the `data` key format for each built-in proxy. The same structure is used in both `mock.inject` and `mock.global.patch`.

The `behavior` field (function overrides) and `strict` flag apply uniformly to all proxies and are documented in [Mock API — State object](mock-api.md#state-object).

---

## fs

*See also: [How-to: Mock the filesystem](../how-to/mock-fs.md)*

**Declare in config:**

```js
mocks: { 'fs': null }
```

**`data` format:**

| Key | Type | Meaning |
| :--- | :--- | :--- |
| filesystem path (string) | string | File content returned by `readfile`, used by `stat`, `access`, `lsdir`, `glob`. |
| filesystem path (string) | `null` | File is explicitly absent; `readfile` returns `null`, `access` returns `null`. |

`writefile` stores the written content under the path key. `unlink` sets the path to `null`. `rename` moves content from one key to another. `mkdir` and `chmod` are no-ops that return `true`. `error` returns `null` by default. `lsdir` and `glob` merge virtual paths with real filesystem entries (unless `strict` is set, in which case only virtual paths are used).

`stat` on a virtual path returns `{ size: <byte length>, mtime: 0, type: 'regular' }`.

**`behavior` overrides:** `readfile`, `writefile`, `access`, `stat`, `rename`, `unlink`, `mkdir`, `chmod`, `error`, `lsdir`, `glob`.

```js
mock.inject('fs', {
    data: {
        '/etc/banner':          'OpenWrt',
        '/tmp/config.txt':      'mode=prod',
        '/tmp/dir/a.txt':       'alpha',
        '/tmp/dir/b.txt':       'beta',
        '/tmp/deleted.txt':     null
    },
    strict: false
}, (m_fs) => {
    m_fs.readfile('/etc/banner');           // → 'OpenWrt'
    m_fs.access('/tmp/config.txt');         // → true
    m_fs.access('/tmp/deleted.txt');        // → null (absent)
    m_fs.stat('/tmp/config.txt');           // → { size: 9, mtime: 0, type: 'regular' }
    m_fs.lsdir('/tmp/dir');                 // → ['a.txt', 'b.txt']
    m_fs.glob('/tmp/dir/*.txt');            // → ['/tmp/dir/a.txt', '/tmp/dir/b.txt']
    m_fs.writefile('/tmp/new.txt', 'hi');   // stores content, returns 2
    m_fs.rename('/tmp/config.txt', '/tmp/cfg2.txt');
    m_fs.unlink('/tmp/dir/a.txt');
    m_fs.mkdir('/tmp/newdir', 0o755);       // → true (no-op)
    m_fs.chmod('/tmp/cfg2.txt', 0o644);     // → true (no-op)
    m_fs.error();                           // → null
});
```

---

## uci

*See also: [How-to: Mock UCI configuration](../how-to/mock-uci.md)*

**Declare in config:**

```js
mocks: { 'uci': null }
```

**`data` format:**

| Key | Type | Meaning |
| :--- | :--- | :--- |
| package name (string) | object | Map of section names to section objects. |

Each section object has the form `{ '.type': '<uci-type>', <option>: <value>, ... }`. The `.type` field is required for `foreach` filtering. All option values are plain strings or arrays of strings, matching the real UCI data model.

`cursor()` returns a cursor object with `get`, `get_all`, `foreach`, `set`, `delete`, `commit`, and `save`. `commit` and `save` are no-ops returning `true`. `set` writes immediately and is readable in the same cursor. `delete` with three arguments removes a single option; with two arguments removes the entire section.

In strict mode, `get` on an unmocked package dies with a `strict mock:` error.

**`behavior` overrides:** `cursor`, `get`, `get_all`, `foreach`, `set`, `delete`, `commit`, `save`.

```js
mock.inject('uci', {
    data: {
        'network': {
            'loopback': { '.type': 'interface', 'ifname': 'lo', 'proto': 'static' },
            'wan':      { '.type': 'interface', 'ifname': 'eth0', 'proto': 'dhcp'  }
        }
    }
}, (m_uci) => {
    let c = m_uci.cursor();

    c.get('network', 'wan', 'proto');           // → 'dhcp'
    c.get('network', 'missing', 'opt');         // → null
    c.get_all('network', 'loopback');           // → { '.type': 'interface', ifname: 'lo', proto: 'static' }

    let ifaces = [];
    c.foreach('network', 'interface', (s) => push(ifaces, s['.name']));
    // → ifaces == ['loopback', 'wan']

    c.set('network', 'wan', 'proto', 'static');
    c.get('network', 'wan', 'proto');           // → 'static'

    c.delete('network', 'wan', 'proto');        // removes option
    c.delete('network', 'loopback');            // removes section
    c.commit('network');                        // → true (no-op)
});
```

---

## ubus

*See also: [How-to: Mock ubus calls](../how-to/mock-ubus.md)*

**Declare in config:**

```js
mocks: { 'ubus': null }
```

**`data` format:**

| Key | Type | Meaning |
| :--- | :--- | :--- |
| `'object:method'` (string) | object or function | Response for a specific object/method pair. |
| `'object'` (string) | object or function | Fallback response for any method on the given object when no `'object:method'` key matches. |

When the value is a plain object, `call` returns it directly. When the value is a function, `call` invokes it with the `args` parameter and returns the result, enabling dynamic responses.

Lookup order: `'object:method'` key first; `'object'` key second; `null` in non-strict mode; fatal error in strict mode.

**`behavior` overrides:** `connect`, `call`.

```js
mock.inject('ubus', {
    data: {
        // Static response for a specific method
        'system:board': { model: 'Test Router', hostname: 'OpenWrt' },

        // Dynamic response — args passed from call site
        'network:status': (args) => ({ up: args.interface == 'wan' }),

        // Fallback for any method on 'service'
        'service': { running: true }
    }
}, (m_ubus) => {
    let conn = m_ubus.connect();
    conn.call('system', 'board', {});               // → { model: 'Test Router', hostname: 'OpenWrt' }
    conn.call('network', 'status', { interface: 'wan' });  // → { up: true }
    conn.call('network', 'status', { interface: 'lan' });  // → { up: false }
    conn.call('service', 'list', {});               // → { running: true }  (fallback)
});
```

---

## uloop

*See also: [How-to: Mock the event loop](../how-to/mock-uloop.md)*

**Declare in config:**

```js
mocks: { 'uloop': null }
```

**`data` format:**

The uloop proxy manages its own internal queue under the key `'__pending__'`. Test writers do not interact with `data` keys directly.

`timer(ms, cb)` enqueues `cb` (the `ms` value is recorded but not used for ordering). `run()` drains the queue synchronously, firing all callbacks in registration order. `run()` clears the queue before firing, so callbacks registered during a `run()` call are not fired in the same pass. A second `run()` with an empty queue is a silent no-op. `init()` and `end()` are no-ops by default.

**`behavior` overrides:** `init`, `timer`, `run`, `end`.

```js
mock.inject('uloop', {}, (m_uloop) => {
    let log = [];

    m_uloop.init();
    m_uloop.timer(3000, () => push(log, 'first'));
    m_uloop.timer(1000, () => {
        push(log, 'second');
        m_uloop.end();
    });

    m_uloop.run();          // → log == ['first', 'second']
    m_uloop.run();          // queue empty; no-op
});
```

To replace the entire dispatch mechanism:

```js
mock.inject('uloop', {
    behavior: { run: () => { /* custom dispatch */ } }
}, (m_uloop) => {
    m_uloop.timer(100, () => {});
    m_uloop.run();   // calls custom run
});
```

---

## uclient

*See also: [How-to: Mock HTTP requests with uclient](../how-to/mock-uclient.md)*

**Declare in config:**

```js
mocks: { 'uclient': null }
```

**`data` format:**

| Key | Type | Meaning |
| :--- | :--- | :--- |
| request URL (string) | object | Response descriptor for that URL. |

Response descriptor fields:

| Field | Type | Meaning |
| :--- | :--- | :--- |
| `status` | integer | HTTP status code returned by `status().status`. |
| `headers` | object | Header map returned by `get_headers()`. |
| `body` | string \| null | Body returned by `read()`. `null` suppresses the `data_read` callback entirely. |
| `error` | string | When present, fires the `error` callback with this code instead of `header_done`/`data_read`/`data_eof`. |

`uclient.new(url, auth, callbacks)` returns a connection object. Calling `request(method, opts)` fires callbacks synchronously in this order for a successful response: `header_done`, `data_read` (only when `body` is non-null), `data_eof`. For an error response only `error` is fired. `read()` returns the body string on the first call and `null` on all subsequent calls. `ssl_init` and `connect` return `true` by default.

In strict mode, `request` on an unmocked URL dies with a `strict mock:` error. In non-strict mode it returns `false` and fires no callbacks.

**`behavior` overrides:** `new`, `ssl_init`, `set_timeout`, `connect`, `request`, `get_headers`, `status`, `read`, `disconnect`.

```js
const url = 'https://api.example.com/v1/data';

mock.inject('uclient', {
    data: {
        // Successful response with body
        [url]: { status: 200, headers: { 'content-type': 'application/json' }, body: '{"ok":true}' },

        // No-content response — data_read is NOT fired
        'https://api.example.com/v1/ping': { status: 204, headers: {}, body: null },

        // Transport error — only error callback fires
        'https://api.example.com/v1/fail': { error: 'connection_refused' }
    }
}, (m_uclient) => {
    let body = null;
    let status = null;

    let u = m_uclient.new(url, null, {
        header_done: (conn) => { status = conn.status().status; },
        data_read:   (conn) => { body = conn.read(); },
        data_eof:    () => {}
    });
    u.ssl_init({ verify: true });
    u.set_timeout(5000);
    u.connect();
    u.request('GET', {});
    // status == 200, body == '{"ok":true}'
    u.disconnect();
});
```
