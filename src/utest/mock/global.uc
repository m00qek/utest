/**
 * Global and persistent built-in patching: mock.global.* and mock.inject_builtin.
 *
 * @module utest.mock.global
 */

import * as engine from 'utest.mock.engine';

// A pristine global state record for a module: no behavior, non-strict, no
// recorded calls, no proxy, and every declared channel reset to empty.  Used by
// patch() (as the base it overrides) and unpatch() so the "blank global" shape
// is defined in exactly one place.
function blank_global(reg) {
	let g = { fns: {}, strict: false, calls: {}, proxy: null };
	for (let ch in reg.channels) g[ch] = {};
	return g;
}

/**
 * Replaces a built-in global (such as `warn`, `system`, or `print`) for the
 * duration of a callback, then unconditionally restores the original — even
 * when the callback throws.
 *
 * Calls to `inject_builtin` may be nested. The inner call saves whatever
 * `global[name]` holds at the moment of the call (which may itself already be
 * a replacement) and restores it on exit, so inner and outer scopes remain
 * independent.
 *
 * Use `mock.global.patch_builtin()` instead when the replacement must be
 * active outside a callback (e.g. at file scope before any `describe` runs).
 *
 * @param {string} name - Name of the built-in to replace (e.g. `'warn'`, `'system'`).
 * @param {any} fn - Replacement installed in `global[name]` for the duration of `cb`.
 * @param {() => any} cb - Called with no arguments while the replacement is active.
 * @returns {any} The return value of `cb`.
 *
 * @example
 * const captured = [];
 * mock.inject_builtin('warn', (...args) => push(captured, join('', args)), () => {
 *     warn('test message\n');
 * });
 * assert.match(['test message\n'], captured);
 */
export function inject_builtin(name, fn, cb) {
	const orig = global[name];
	global[name] = fn;
	let err, had_err = false;
	let result;
	try {
		result = cb();
	} catch (e) {
		err = e; had_err = true;
	}
	global[name] = orig;
	if (had_err) die(err);
	return result;
};

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
	// patch() installs a complete new state: blank_global() starts every channel
	// empty so a re-patch cannot leak data from a previous patch through a channel
	// the new state omits.  A channel explicitly present but null is also treated
	// as empty below, matching to_layer()'s handling for mock.inject().
	let new_global = blank_global(reg);
	if (state.behavior) new_global.fns = { ...state.behavior };
	if (state.strict)   new_global.strict = true;
	for (let ch in channels)
		new_global[ch] = (exists(state, ch) && state[ch] !== null) ? engine.deep_clone(state[ch]) : {};
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
	reg.global = blank_global(reg);
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
	if (!exists(engine.builtin_overrides, name))
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
