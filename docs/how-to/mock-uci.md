# How to mock UCI configuration

Replace UCI reads and writes with an in-memory configuration tree so your tests run without a real UCI database.

Declare `uci: null` in your `utest.config.uc` `mocks` table before using any of the patterns below. See [How-to: Mock a module with mock.inject()](mock-inject.md) for the setup steps.

---

## Seed a configuration package

The `data` map uses package names as top-level keys. Each package value is an object of section names, where each section is an object of option keys including the mandatory `.type` key:

```js
const uci_data = {
    'luci-sso': {
        'default': {
            '.type': 'oidc',
            'enabled': '1',
            'issuer_url': 'https://idp.example.com',
            'client_id': 'my-client'
        },
        'admin_role': {
            '.type': 'role',
            'email': ['admin@example.com'],
            'read': ['*'],
            'write': ['*']
        }
    }
};

mock.inject('uci', { data: uci_data }, (m_uci) => {
    let c = m_uci.cursor();
    assert.match('1', c.get('luci-sso', 'default', 'enabled'));
    assert.match(null, c.get('luci-sso', 'default', 'missing_opt'));
    assert.match(null, c.get('no-pkg', 'sec', 'opt'));
});
```

---

## Read an entire section at once

`get_all(pkg, section)` returns the full section object including `.type`, or `null` if the section does not exist:

```js
mock.inject('uci', { data: {
    'luci-sso': {
        'default': { '.type': 'oidc', 'issuer_url': 'https://idp.example.com', 'client_id': 'my-client' }
    }
}}, (m_uci) => {
    let c = m_uci.cursor();
    let sec = c.get_all('luci-sso', 'default');
    assert.match('oidc', sec['.type']);
    assert.match('my-client', sec.client_id);
    assert.match(null, c.get_all('luci-sso', 'no-sec'));
});
```

---

## Iterate sections by type

`foreach(pkg, type, callback)` iterates sections whose `.type` matches the given string, in insertion order. The callback receives each section with `.name` injected:

```js
mock.inject('uci', { data: {
    'luci-sso': {
        'admin_role': { '.type': 'role', 'email': ['admin@example.com'] }
    }
}}, (m_uci) => {
    let names = [];
    m_uci.cursor().foreach('luci-sso', 'role', (s) => push(names, s['.name']));
    assert.match(['admin_role'], names);
});
```

---

## Write options and verify they persist within the mock

`set(pkg, section, option, value)` writes a value and makes it immediately readable via `get()`. The change is confined to the mock layer and does not touch the real UCI database:

```js
mock.inject('uci', { data: {
    'luci-sso': { 'default': { '.type': 'oidc', 'enabled': '0' } }
}}, (m_uci) => {
    let c = m_uci.cursor();
    c.set('luci-sso', 'default', 'enabled', '1');
    assert.match('1', c.get('luci-sso', 'default', 'enabled'));
});
```

---

## Delete an option or an entire section

Pass three arguments to delete a single option; pass two to delete the entire section:

```js
// Delete one option
mock.inject('uci', { data: {
    'luci-sso': { 'default': { '.type': 'oidc', 'enabled': '1', 'scope': 'openid' } }
}}, (m_uci) => {
    let c = m_uci.cursor();
    c.delete('luci-sso', 'default', 'scope');
    assert.match(null, c.get('luci-sso', 'default', 'scope'));
    assert.match('1',  c.get('luci-sso', 'default', 'enabled'));
});

// Delete an entire section
mock.inject('uci', { data: {
    'luci-sso': {
        'admin_role': { '.type': 'role', 'email': ['admin@example.com'] }
    }
}}, (m_uci) => {
    let c = m_uci.cursor();
    c.delete('luci-sso', 'admin_role');
    let names = [];
    c.foreach('luci-sso', 'role', (s) => push(names, s['.name']));
    assert.match([], names);
});
```

---

## Exercise code paths that call commit()

`commit()` is a no-op that returns `true`. Call it in tests that exercise code paths which persist configuration:

```js
mock.inject('uci', {}, (m_uci) => {
    assert.match(true, m_uci.cursor().commit('luci-sso'));
});
```

---

## Next steps

- Fail loudly when code reads an unmocked package: [How-to: Use strict mode](strict-mode.md)
- Intercept calls through the imported `uci` binding: [How-to: Patch global state with mock.global.patch()](mock-global-patch.md)
- See the full `data` key format and behavior override list: [Reference: Proxy Data Models — uci](../reference/proxy-data-models.md#uci)
