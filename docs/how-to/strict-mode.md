# How to use strict mode

Add `strict: true` to the state object so the mock dies immediately when code calls a function or accesses data that was not explicitly seeded.

---

## Add strict: true to the state

Pass `strict: true` alongside `data` and/or `behavior`:

```js
import { describe, it, mock } from 'utest';
import { assert } from 'utest.assert';

describe('strict mode', () => {
    it('dies on an unmocked ubus call', () => {
        assert.throws(() => {
            mock.inject('ubus', { strict: true, data: {} }, (m_ubus) => {
                m_ubus.connect().call('unmocked', 'method', {});
            });
        }, /strict mock/);
    });
});
```

The error message matches the pattern `strict mock` and identifies the module and function or key that was accessed.

For why strict mode exists and the trade-offs involved, see [About strict mode](../explanation/strict-mode.md).

---

## Use with assert.throws to verify call gating

Wrap the code under test in a thunk and pass it to `assert.throws()`. Provide a pattern that matches the strict mock error so unrelated errors are not silently swallowed:

```js
// uci: dies when code reads a package that was not seeded
assert.throws(() => {
    mock.inject('uci', { strict: true, data: {} }, (m_uci) => {
        m_uci.cursor().get('no-pkg', 'sec', 'opt');
    });
}, /strict mock/);

// uclient: dies when code requests an unmocked URL
assert.throws(() => {
    mock.inject('uclient', { strict: true, data: {} }, (m_uclient) => {
        let u = m_uclient.new('http://example.com/x', null, {});
        u.request('GET', {});
    });
}, /strict mock/);
```

---

## Start without strict mode, then add it

When you are unsure which keys your code accesses, run once without strict mode to let the code exercise freely and observe the behaviour. Then enable strict mode and seed only the keys you confirmed it needs:

```js
// First pass — no strict, learn what the code reads
mock.inject('uci', {
    data: { 'network': { 'lan': { '.type': 'interface', 'ipaddr': '192.168.1.1' } } }
}, (m_uci) => {
    const result = get_lan_summary(m_uci.cursor());
    // If get_lan_summary also reads 'proto', it silently gets null here.
});

// Second pass — strict, declare the full set
mock.inject('uci', {
    strict: true,
    data: { 'network': { 'lan': { '.type': 'interface', 'ipaddr': '192.168.1.1', 'proto': 'static' } } }
}, (m_uci) => {
    const result = get_lan_summary(m_uci.cursor());
    assert.eq(result.ip, '192.168.1.1');
    // Any key beyond what is seeded will now die() with: strict mock: 'uci.get' is not mocked
});
```

The data map then doubles as a specification of what the code is expected to access.

---

## Combine strict with partial data

Seed the data you expect to be accessed and let strict mode catch anything unexpected. This verifies that the code under test does not make calls beyond what the test intends:

```js
mock.inject('ubus', {
    strict: true,
    data: { 'system:board': { model: 'Test Router' } }
}, (m_ubus) => {
    let conn = m_ubus.connect();
    // This call is allowed — the key is seeded:
    assert.eq(conn.call('system', 'board', {}).model, 'Test Router');

    // Any call to an unseeded object/method would die here.
});
```

---

## Strict mode and lsdir / glob

For `fs`, strict mode suppresses the real filesystem when listing directories or matching globs. Only virtual entries appear in `lsdir()` and `glob()` results.

---

## Next steps

- Seed data and behaviour for the mock: [How-to: Mock a module with mock.inject()](mock-inject.md)
- Apply strict mode globally across a patch: [How-to: Patch global state with mock.global.patch()](mock-global-patch.md)
- Write a proxy that enforces its own invariants: [How-to: Write a custom proxy](custom-proxy.md)
