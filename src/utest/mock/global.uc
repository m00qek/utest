/**
 * Persistent global patching: mock.global.patch / unpatch / patch_builtin / unpatch_builtin.
 *
 * @module utest.mock.global
 */

import * as engine from 'utest.mock.engine';

/**
 * Installs persistent global state for one module and returns a proxy. When
 * the shim for that module is active, all calls made through the real imported
 * binding (`import * as mod from 'name'`) or via `require('name')` route
 * through the same mock engine, making the state visible to production code
 * under test.
 *
 * `mock.global.patch` is atomic: if `build_proxy` throws (e.g. a custom proxy
 * factory fails), the registry is rolled back to its previous state.
 *
 * Global state is independent of scoped layers. `mock.inject` layers shadow
 * global state but do not erase it; the global state becomes visible again
 * when all layers are popped.
 *
 * Always pair with `mock.global.unpatch()` or use `mock.snapshot()` /
 * `mock.restore()` to guarantee cleanup.
 *
 * @param {string} name - Module name.
 * @param {dict<any>} state - State object; same shape as `mock.inject()` state.
 * @param {dict<any>} [state.data] - Key→value mock data.
 * @param {dict<function>} [state.behavior] - Function overrides.
 * @param {boolean} [state.strict=false] - Strict mode flag.
 * @param {dict<string>} [state.commands] - Pre-seeded popen outputs (fs only).
 * @returns {any} The configured proxy.
 *
 * @example
 * const m_fs = mock.global.patch('fs', { data: { '/etc/myapp.conf': 'debug=0' } });
 * assert.match('debug=0', m_fs.readfile('/etc/myapp.conf'));
 * mock.global.unpatch('fs');
 */
export function patch(name, state) {
	const proxy_channels = engine.get_proxy_channels(name);
	const real = engine.get_real(name);
	engine.guard_mock_target('mock.global.patch', name, proxy_channels, real);
	const channels = proxy_channels || ['data'];
	const reg = engine.get_registry(name);
	engine.ensure_channels(reg, channels);
	// Build the new global atomically: save the old state so we can roll back
	// if build_proxy fails (e.g. a custom proxy factory throws).
	const prev_global = reg.global;
	let new_global = {
		fns:    state.behavior ? { ...state.behavior } : {},
		strict: state.strict   ? true : false,
		calls:  {},
		proxy:  null
	};
	for (let ch in reg.channels)
		new_global[ch] = prev_global[ch] ?? {};
	for (let ch in channels)
		new_global[ch] = state[ch] ? engine.deep_clone(state[ch]) : {};
	reg.global = new_global;
	let err, had_err = false;
	let proxy;
	try {
		proxy = engine.build_proxy(name, real);
	} catch(e) {
		err = e; had_err = true;
	}
	if (had_err) {
		reg.global = prev_global;
		die(err);
	}
	new_global.proxy = proxy;
	return proxy;
};

/**
 * Removes all global state for the named module and clears the stored proxy.
 * Scoped layers from `mock.inject()` are unaffected.
 *
 * @param {string} name - Module name to unpatch.
 */
export function unpatch(name) {
	const reg = engine.get_registry(name);
	let new_global = { fns: {}, strict: false, proxy: null, calls: {} };
	for (let ch in reg.channels) new_global[ch] = {};
	reg.global = new_global;
};

/**
 * Installs a persistent replacement for a built-in global. Unlike
 * `mock.inject_builtin()`, there is no callback and no automatic cleanup —
 * call `mock.global.unpatch_builtin()` to restore the original.
 *
 * If `mock.inject_builtin()` is called while a `patch_builtin` is active, it
 * layers on top correctly: the inner call saves the patched function and
 * restores it on exit, leaving the persistent patch in place.
 *
 * @param {string} name - Built-in name (e.g. `'warn'`, `'system'`, `'print'`).
 * @param {any} fn - Replacement installed in `global[name]` until unpatch_builtin.
 */
export function patch_builtin(name, fn) {
	engine.builtin_overrides[name] = global[name];
	global[name] = fn;
};

/**
 * Restores `global[name]` to the value saved by the most recent
 * `mock.global.patch_builtin(name)` call. No-op if `patch_builtin` was never
 * called for this name.
 *
 * @param {string} name - Built-in name to restore.
 */
export function unpatch_builtin(name) {
	if (exists(engine.builtin_overrides, name)) {
		global[name] = engine.builtin_overrides[name];
		delete engine.builtin_overrides[name];
	}
};
