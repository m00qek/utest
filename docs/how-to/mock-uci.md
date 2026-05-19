# How to mock UCI configuration

Replace UCI reads and writes with an in-memory configuration tree so your tests run without a real UCI database.

---

## Declare the module in the config file

Add `uci` to the `mocks` table in the config file:

```js
return {
    mocks: {
        uci: null
    }
};
```

---

## Seed the data structure

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
```

Pass this to `mock.inject()`:

```js
mock.inject('uci', { data: uci_data }, (m_uci) => {
    let c = m_uci.cursor();
    // ...
});
```

---

## get

`get(pkg, section, option)` returns the option value, or `null` if the package, section, or option is absent:

```js
mock.inject('uci', { data: uci_data }, (m_uci) => {
    let c = m_uci.cursor();
    assert.eq(c.get('luci-sso', 'default', 'enabled'), '1');
    assert.eq(c.get('luci-sso', 'default', 'missing_opt'), null);
    assert.eq(c.get('no-pkg', 'sec', 'opt'), null);
});
```

---

## get_all

`get_all(pkg, section)` returns the full section object including `.type`, or `null` if the section does not exist:

```js
mock.inject('uci', { data: uci_data }, (m_uci) => {
    let c = m_uci.cursor();
    let sec = c.get_all('luci-sso', 'default');
    assert.eq(sec['.type'], 'oidc');
    assert.eq(sec.client_id, 'my-client');
    assert.eq(c.get_all('luci-sso', 'no-sec'), null);
});
```

---

## foreach with type filter

`foreach(pkg, type, callback)` iterates sections whose `.type` matches the given string, in insertion order. The callback receives each section with `.name` injected:

```js
mock.inject('uci', { data: uci_data }, (m_uci) => {
    let names = [];
    m_uci.cursor().foreach('luci-sso', 'role', (s) => push(names, s['.name']));
    assert.eq(names, ['admin_role']);
});
```

---

## set

`set(pkg, section, option, value)` writes a value and makes it immediately readable via `get()`. The change is confined to the mock layer and does not touch the real UCI database:

```js
mock.inject('uci', { data: {
    'luci-sso': { 'default': { '.type': 'oidc', 'enabled': '0' } }
}}, (m_uci) => {
    let c = m_uci.cursor();
    c.set('luci-sso', 'default', 'enabled', '1');
    assert.eq(c.get('luci-sso', 'default', 'enabled'), '1');
});
```

---

## delete — option vs section

Pass three arguments to delete a single option; pass two to delete the entire section:

```js
// Delete one option
mock.inject('uci', { data: {
    'luci-sso': { 'default': { '.type': 'oidc', 'enabled': '1', 'scope': 'openid' } }
}}, (m_uci) => {
    let c = m_uci.cursor();
    c.delete('luci-sso', 'default', 'scope');
    assert.eq(c.get('luci-sso', 'default', 'scope'), null);
    assert.eq(c.get('luci-sso', 'default', 'enabled'), '1');
});

// Delete an entire section
mock.inject('uci', { data: uci_data }, (m_uci) => {
    let c = m_uci.cursor();
    c.delete('luci-sso', 'admin_role');
    let names = [];
    c.foreach('luci-sso', 'role', (s) => push(names, s['.name']));
    assert.eq(names, []);
});
```

---

## commit

`commit()` is a no-op that returns `true`. Call it in tests that exercise code paths which persist configuration:

```js
mock.inject('uci', { data: uci_data }, (m_uci) => {
    assert.ok(m_uci.cursor().commit('luci-sso'));
});
```

---

## Next steps

- Fail loudly when code reads an unmocked package: [How-to: Use strict mode](strict-mode.md)
- Intercept calls through the imported `uci` binding: [How-to: Patch global state with mock.global.patch()](mock-global-patch.md)
- Mock ubus calls: [How-to: Mock ubus](mock-ubus.md)
