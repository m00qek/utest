# Proxy Data Models Reference

This page documents the state channels for each built-in proxy. The same structure is used in both `mock.inject` and `mock.global.patch`.

The `behavior` field (function overrides) and `strict` flag apply uniformly to all proxies and are documented in [Mock API — State object](mock-api.md#state-object).

---

## fs

*See also: [How-to: Mock the filesystem](../how-to/mock-fs.md)*

**Declare in config:**

```js
mocks: { 'fs': null }
```

**`data` channel:**

Filesystem paths are the keys. `lsdir`, `glob`, `access`, `stat`, `readfile`,
`open`, `writefile`, `rename`, and `unlink` all operate in this channel.

| Key | Type | Meaning |
| :--- | :--- | :--- |
| filesystem path (string) | string | File content returned by `readfile`, `open`, `stat`, `access`, `lsdir`, `glob`. |
| filesystem path (string) | `null` | File is explicitly absent; `readfile` and `open` return `null`, `access` returns `null`. |

`writefile` stores the written content under the path key. `unlink` sets the path to `null`. `rename` moves content from one key to another. `mkdir` and `chmod` are no-ops that return `true`. `error` returns `null` by default. `lsdir` and `glob` merge virtual paths with real filesystem entries (unless `strict` is set, in which case only virtual paths are used).

`stat` on a virtual path returns `{ size: <byte length>, mtime: 0, type: 'file' }` (the `type` uses the real `fs` vocabulary — `'file'`, not `'regular'`).

`readfile(path, size)` reads at most `size` bytes from the start of the content, matching real `fs.readfile`; called with no `size` it returns the whole value.

`open(path, mode)` uses the path as a data key. In read mode (`'r'`), a seeded path returns a handle supporting `read('all')`, `read('line')`, and `read(n)`; an unmocked path returns `null` in non-strict mode or dies in strict mode. In write mode (`'w'`) and append mode (`'a'`), a writable handle is always returned; content is stored back into the data channel when `close()` is called. `error()` on any handle always returns `null`. Every handle also exposes `seek(off)`, `tell()`, and `flush()` (read advances the position sequentially; a write handle's `tell()` reports bytes written) so a SUT that repositions a handle does not crash. Random-access writes (`r+`/`w+`) are not modeled — a write handle appends and flushes its buffer on `close()`.

**Read-side operations:** `lstat`, `readlink`, `realpath`, and `opendir` are modeled against the same data channel (they are not passed through to the real fs). `lstat` equals `stat` (the mock has no symlinks); `readlink` returns `null` for any known path; `realpath` canonicalizes `.`/`..`/redundant slashes and confirms the path exists (else `null`); `opendir` serves the merged listing through a cursor handle with `read()` (next entry, `null` past the end), `tell()`, `seek()`, `close()`, and `error()`.

**Sealed operations:** the six filesystem-mutating ops the mock does not model — `rmdir`, `symlink`, `chown`, `chdir`, `mkdtemp`, `mkstemp` — **die** under an active mock (both strict and non-strict) rather than falling through to the real filesystem, unless you supply a `behavior:` override for them. This prevents a destructive call from escaping the sandbox onto the host.

**`commands` channel:**

Command strings are the keys. Only `popen` uses this channel.

| Key | Type | Meaning |
| :--- | :--- | :--- |
| command string (string) | string | Output returned by `popen` in read mode; stores written content on `close()` in write mode. |

`popen(cmd, mode)` looks up the command string in the `commands` channel. Read mode returns a handle over the seeded output; write mode stores the written content under the command string key on `close()`. In strict mode, an unmocked command dies with a `strict mock:` error.

Keeping commands in a separate channel ensures that command strings are invisible to `lsdir`, `glob`, `access`, and `stat`.

**`glob` wildcard syntax:**

The mock matches real `glob(3)`. All wildcards operate within a single path
component (they do not cross `/`):

| Wildcard | Matches |
| :--- | :--- |
| `*` | Any sequence of characters within one path component |
| `?` | Any single character within one path component |
| `[abc]`, `[a-z]` | Any one character in the set or range |
| `[!abc]`, `[^abc]` | Any one character *not* in the set or range |

`**` is **not** a globstar: between two slashes it matches a single path
component, exactly like `*`. Name each directory level explicitly to reach
nested files — `/etc/*/*.cfg` matches `/etc/init/a.cfg` (one level deep) but
not `/etc/init/sub/b.cfg` (two levels deep).

**`behavior` overrides:** `readfile`, `writefile`, `open`, `popen`, `access`, `stat`, `lstat`, `readlink`, `realpath`, `opendir`, `rename`, `unlink`, `mkdir`, `chmod`, `error`, `lsdir`, `glob`, and the sealed ops (`rmdir`, `symlink`, `chown`, `chdir`, `mkdtemp`, `mkstemp`) — supplying a `behavior` for a sealed op is how you make it do something instead of dying.

```js
mock.inject('fs', {
    data: {
        '/etc/banner':          'OpenWrt',
        '/tmp/config.txt':      'mode=prod',
        '/tmp/dir/a.txt':       'alpha',
        '/tmp/dir/b.txt':       'beta',
        '/tmp/deleted.txt':     null,
    },
    commands: {
        'uname -r':             '6.1.0\n'
    },
    strict: false
}, (m_fs) => {
    m_fs.readfile('/etc/banner');           // → 'OpenWrt'
    m_fs.access('/tmp/config.txt');         // → true
    m_fs.access('/tmp/deleted.txt');        // → null (absent)
    m_fs.stat('/tmp/config.txt');           // → { size: 9, mtime: 0, type: 'file' }
    m_fs.lsdir('/tmp/dir');                 // → ['a.txt', 'b.txt']
    m_fs.glob('/tmp/dir/*.txt');            // → ['/tmp/dir/a.txt', '/tmp/dir/b.txt']
    m_fs.writefile('/tmp/new.txt', 'hi');   // stores content, returns 2
    m_fs.rename('/tmp/config.txt', '/tmp/cfg2.txt');
    m_fs.unlink('/tmp/dir/a.txt');
    m_fs.mkdir('/tmp/newdir', 0o755);       // → true (no-op)
    m_fs.chmod('/tmp/cfg2.txt', 0o644);     // → true (no-op)
    m_fs.error();                           // → null

    let f = m_fs.open('/tmp/dir/b.txt', 'r');
    f.read('all');                          // → 'beta'
    f.close();

    let p = m_fs.popen('uname -r', 'r');
    p.read('line');                         // → '6.1.0\n'
    p.close();
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

`cursor()` returns a cursor object with `load`, `get`, `get_all`, `foreach`, `set`, `delete`, `commit`, and `save`. `commit`, `save`, and `load` return `true` by default. Under **strict** mode `load` returns `false` for a package that has no seeded config (matching real UCI, which loads only configured packages) while still returning `true` for a seeded one; the actual strict enforcement happens on the subsequent `get`/`get_all`/`foreach`/`delete`. `set` writes immediately and is readable in the same cursor. `delete` with three arguments removes a single option; with two arguments removes the entire section; it returns `null` when the target package, section, or option does not exist (matching real UCI, where a real removal returns `true`).

Reads return **deep copies**, not live references into the mock store: mutating the object returned by `get`, `get_all`, or `foreach` does not change the seeded data (real UCI returns fresh objects too, so code that mutates a read result cannot corrupt the fixture).

`get_all(pkg, section)` returns the full section object with `.name` set to the section name and `.type` set from the data, or `null` if the section does not exist — matching real UCI behaviour.

In strict mode, `get` on an unmocked package dies with a `strict mock:` error.

**`behavior` overrides:** `cursor`, `load`, `get`, `get_all`, `foreach`, `set`, `delete`, `commit`, `save`.

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

    c.load('network');                          // → true (no-op)
    c.get('network', 'wan', 'proto');           // → 'dhcp'
    c.get('network', 'missing', 'opt');         // → null
    c.get_all('network', 'loopback');           // → { '.name': 'loopback', '.type': 'interface', ifname: 'lo', proto: 'static' }

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

The connection object returned by `connect()` also exposes `disconnect()`. `disconnect()` is a no-op by default; the call is recorded and readable via `spy(conn).calls.disconnect`.

**`behavior` overrides:** `connect`, `call`, `disconnect`.

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
    conn.disconnect();                              // no-op
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

The uloop proxy manages its own timer queue in a dedicated `timers` channel. Test writers do not interact with channel keys directly.

`timer(ms, cb)` enqueues `cb` and returns a handle. `run()` drains the queue synchronously, firing callbacks in ascending `ms` (deadline) order — matching the real uloop — with ties broken by registration order. No wall-clock time passes; `ms` only orders the callbacks. `run()` clears the queue before firing, so callbacks registered during a `run()` call are not fired in the same pass. A second `run()` with an empty queue is a silent no-op. `init()` and `end()` are no-ops by default.

The handle mirrors the real `uloop.timer` resource: `remaining()` returns the armed deadline (or `-1` once cancelled — the mock has no clock), `cancel()` marks the timer dead so `run()` skips it, and `set(ms)` re-arms it (clearing a prior cancel). `run()` sorts on each timer's *current* `ms`, so a `set()` before `run()` reschedules correctly. Both mutators return the handle.

**`behavior` overrides:** `init`, `timer`, `run`, `end`.

```js
mock.inject('uloop', {}, (m_uloop) => {
    let log = [];

    m_uloop.init();
    m_uloop.timer(3000, () => push(log, 'later'));
    m_uloop.timer(1000, () => {
        push(log, 'sooner');
        m_uloop.end();
    });

    m_uloop.run();          // → log == ['sooner', 'later']  (1000 ms before 3000 ms)
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
