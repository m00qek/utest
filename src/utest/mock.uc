/**
 * Public mock API: inject, patch, snapshot, and spy utilities.
 *
 * @module utest.mock
 */

import { _engine } from 'utest.mock.engine';

const registries       = _engine.registries;
const builtin_overrides = _engine.builtin_overrides;
const deep_clone       = _engine.deep_clone;
const reset_layers     = _engine.reset_layers;
const get_registry     = _engine.get_registry;
const get_proxy_channels = _engine.get_proxy_channels;
const get_real         = _engine.get_real;
const guard_mock_target = _engine.guard_mock_target;
const ensure_channels  = _engine.ensure_channels;
const to_layer         = _engine.to_layer;
const build_proxy      = _engine.build_proxy;

/**
 * Clears all active `mock.inject()` layers across every registered module.
 * Global state installed by `mock.global.patch()` is left untouched.
 *
 * Use `mock.restore(snap)` when you need to reset both layers and global state
 * to a prior checkpoint.
 */
export function reset() {
	reset_layers();
};

/**
 * Captures the current global mock state of every registered module as an
 * opaque snapshot object. The snapshot does not include transient layers from
 * `mock.inject()` — those are already guaranteed to be cleaned up when their
 * own callback exits.
 *
 * The returned value can be passed to `mock.restore()` any number of times.
 * Each restore deep-clones the channel data so successive restores from the
 * same snapshot each get an independent copy.
 *
 * @returns {dict<any>} Opaque snapshot; pass to `mock.restore()`.
 *
 * @example
 * const snap = mock.snapshot();
 * mock.global.patch('fs', { data: { '/tmp/x': 'hello' } });
 * // ... test code ...
 * mock.restore(snap);   // global patch is gone
 */
export function snapshot() {
	let snap = {};
	for (let name, reg in registries) {
		let s = {
			fns:    { ...reg.global.fns },
			strict: reg.global.strict,
			proxy:  reg.global.proxy
			// calls intentionally omitted — restore() always resets them to {}
		};
		for (let ch in reg.channels)
			s[ch] = deep_clone(reg.global[ch] ?? {});
		snap[name] = s;
	}
	return snap;
};

/**
 * Restores global mock state to exactly what it was when `snap` was taken.
 * All active `mock.inject()` layers are cleared. Modules that existed at
 * snapshot time are reset to their saved state; modules registered after the
 * snapshot was taken are cleared entirely.
 *
 * Safe to call multiple times with the same snapshot — each call produces an
 * independent copy of the saved data.
 *
 * @param {dict<any>} snap - Snapshot previously returned by `mock.snapshot()`.
 *
 * @example
 * const snap = mock.snapshot();
 * mock.global.patch('uci', { data: { myapp: { cfg: { x: '1' } } } });
 * mock.restore(snap);   // uci patch gone, layers cleared
 */
export function restore(snap) {
	reset_layers();
	for (let name, saved in snap) {
		const reg = get_registry(name);
		// Deep-clone channel data so successive restores from the same snapshot
		// each get an independent copy; set_channel() mutations cannot corrupt snap.
		let new_global = {
			fns:    { ...saved.fns },
			strict: saved.strict,
			proxy:  saved.proxy,
			calls:  {}
		};
		for (let ch in reg.channels)
			new_global[ch] = deep_clone(saved[ch] ?? {});
		reg.global = new_global;
	}
	for (let name in keys(registries)) {
		if (!exists(snap, name)) {
			const reg = registries[name];
			let new_global = { fns: {}, strict: false, proxy: null, calls: {} };
			for (let ch in reg.channels) new_global[ch] = {};
			reg.global = new_global;
		}
	}
};

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
 * Pushes a transient state layer for one module, calls `cb(proxy)`, then pops
 * the layer — unconditionally, even when `cb` throws.
 *
 * The real imported binding (`import * as mod from 'name'`) is never affected;
 * only the proxy passed to the callback routes through the mock state. Use
 * `mock.global.patch()` when the real binding itself must be intercepted.
 *
 * Calls to `mock.inject` may be nested. Inner layers shadow outer layers for
 * matching keys and fall through to outer layers for keys they do not define.
 *
 * @param {string} name - Module name as it appears in `import` statements.
 * @param {dict<any>} state - State applied for the duration of `cb`.
 * @param {dict<any>} [state.data] - Key→value mock data; key semantics are proxy-specific.
 * @param {dict<function>} [state.behavior] - Function overrides; a matching entry
 *   completely replaces the proxy's built-in handling for that function.
 * @param {boolean} [state.strict=false] - When `true`, any call to an unmocked key
 *   dies with a `strict mock:` error instead of falling through to the real module.
 * @param {dict<string>} [state.commands] - Pre-seeded `popen` outputs (fs proxy only).
 * @param {(proxy: any) => any} cb - Receives the proxy for the duration of the call.
 * @returns {any} The return value of `cb`.
 *
 * @example
 * const content = mock.inject('fs', {
 *     data:   { '/etc/config': 'enabled=1' },
 *     strict: true
 * }, (m_fs) => m_fs.readfile('/etc/config'));
 * assert.match('enabled=1', content);
 */
export function inject(name, state, cb) {
	const proxy_channels = get_proxy_channels(name);
	const real = get_real(name);
	guard_mock_target('mock.inject', name, proxy_channels, real);
	const channels = proxy_channels || ['data'];
	const reg = get_registry(name);
	ensure_channels(reg, channels);
	push(reg.layers, to_layer(state, channels));
	let err, had_err = false;
	let result;
	try {
		let proxy = build_proxy(name, real);
		result = cb(proxy);
	} catch (e) {
		err = e; had_err = true;
	}
	pop(reg.layers);
	if (had_err) die(err);
	return result;
};

/**
 * Like `mock.inject`, but injects several modules atomically in a single call.
 *
 * All targets are validated before any layer is pushed: if one module is not
 * listed in `mocks`, the call dies immediately and no state is modified. Layers
 * are pushed in key-iteration order and popped in reverse when `cb` returns or
 * throws.
 *
 * @param {dict<dict<any>>} states - Map of module names to state objects. Each
 *   value has the same shape as the `state` argument to `mock.inject()`:
 *   optional `data`, `behavior`, `strict`, and channel fields.
 * @param {(deps: dict<any>) => any} cb - Receives a map of proxies keyed by
 *   module name, matching the keys of `states`.
 * @returns {any} The return value of `cb`.
 *
 * @example
 * const result = mock.inject_all({
 *     uci:  { data: { myapp: { cfg: { enabled: '1' } } } },
 *     ubus: { data: { 'myapp:reload': { ok: true } } }
 * }, ({ uci: m_uci, ubus: m_ubus }) => {
 *     return apply_config(m_uci, m_ubus);
 * });
 * assert.match(true, result.ok);
 */
export function inject_all(states, cb) {
	const names = keys(states);

	// Validate all targets before touching any registry state.
	const reals = {};
	const channels_map = {};
	for (let name in names) {
		const proxy_channels = get_proxy_channels(name);
		const real = get_real(name);
		guard_mock_target('mock.inject_all', name, proxy_channels, real);
		if (type(states[name]) !== 'object' || states[name] === null)
			die(sprintf("mock.inject_all: state for '%s' must be a non-null object", name));
		reals[name] = real;
		channels_map[name] = proxy_channels || ['data'];
	}

	// Push one layer per proxy, tracking count so cleanup covers only what was pushed.
	let pushed = 0;
	let err, had_err = false;
	let result;
	try {
		for (let name in names) {
			const reg = get_registry(name);
			ensure_channels(reg, channels_map[name]);
			push(reg.layers, to_layer(states[name], channels_map[name]));
			pushed++;
		}
		const deps = {};
		for (let name in names)
			deps[name] = build_proxy(name, reals[name]);
		result = cb(deps);
	} catch (e) {
		err = e; had_err = true;
	}

	// Pop in reverse order, limited to what was successfully pushed.
	for (let i = pushed - 1; i >= 0; i--)
		pop(get_registry(names[i]).layers);

	if (had_err) die(err);
	return result;
};

// ── mock.global.* ────────────────────────────────────────────────────────────
// Assembled into mock.global by utest.uc so the public API remains unchanged.

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
	const proxy_channels = get_proxy_channels(name);
	const real = get_real(name);
	guard_mock_target('mock.global.patch', name, proxy_channels, real);
	const channels = proxy_channels || ['data'];
	const reg = get_registry(name);
	ensure_channels(reg, channels);
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
		new_global[ch] = state[ch] ? deep_clone(state[ch]) : {};
	reg.global = new_global;
	let err, had_err = false;
	let proxy;
	try {
		proxy = build_proxy(name, real);
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
	const reg = get_registry(name);
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
	builtin_overrides[name] = global[name];
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
	if (exists(builtin_overrides, name)) {
		global[name] = builtin_overrides[name];
		delete builtin_overrides[name];
	}
};

// The worker runner reads this global to call snapshot()/restore() around each
// test without importing this module directly (it must stay decoupled so tests
// that do not use mocking never trigger the engine at all).
if (!global.__utest_mock_instance)
	global.__utest_mock_instance = { snapshot, restore, reset };
