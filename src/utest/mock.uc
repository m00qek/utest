/**
 * Public mock API: inject, patch, snapshot, and spy utilities.
 *
 * @module utest.mock
 */

import * as engine  from 'utest.mock.engine';
import * as _global from 'utest.mock.global';

/**
 * Clears all active `mock.inject()` layers across every registered module.
 * Global state installed by `mock.global.patch()` is left untouched.
 *
 * Use `mock.restore(snap)` when you need to reset both layers and global state
 * to a prior checkpoint.
 */
export function reset() {
	engine.reset_layers();
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
	for (let name, reg in engine.registries) {
		let s = {
			channels: [...reg.channels],
			fns:      { ...reg.global.fns },
			strict:   reg.global.strict,
			proxy:    reg.global.proxy
			// calls intentionally omitted — restore() always resets them to {}
		};
		for (let ch in reg.channels)
			s[ch] = engine.deep_clone(reg.global[ch] ?? {});
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
	engine.reset_layers();
	for (let name, saved in snap) {
		const reg = engine.get_registry(name);
		reg.channels = [...saved.channels];
		// Deep-clone channel data so successive restores from the same snapshot
		// each get an independent copy; set_channel() mutations cannot corrupt snap.
		let new_global = {
			fns:    { ...saved.fns },
			strict: saved.strict,
			proxy:  saved.proxy,
			calls:  {}
		};
		for (let ch in saved.channels)
			new_global[ch] = engine.deep_clone(saved[ch] ?? {});
		reg.global = new_global;
	}
	for (let name in engine.registries) {
		if (!exists(snap, name)) {
			// Module registered after the snapshot was taken: clear its state but
			// keep its channel list intact.  blank_global() preserves the registry's
			// channel list (hardcoding ['data'] would drop extra channels like fs's
			// 'commands', so a later snapshot() would capture an incomplete manifest).
			const reg = engine.registries[name];
			reg.global = engine.blank_global(reg);
		}
	}
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
	if (type(state) !== 'object' || state === null)
		die(sprintf("mock.inject: state for '%s' must be a non-null object", name));
	const proxy_channels = engine.get_proxy_channels(name);
	const real = engine.get_real(name);
	engine.guard_mock_target('mock.inject', name, proxy_channels, real);
	const channels = proxy_channels || ['data'];
	engine.validate_state('mock.inject', name, state, channels);
	const reg = engine.get_registry(name);
	engine.ensure_channels(reg, channels);
	push(reg.layers, engine.to_layer(state, channels));
	let err, had_err = false;
	let result;
	try {
		let proxy = engine.build_proxy(name, real);
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
		const proxy_channels = engine.get_proxy_channels(name);
		const real = engine.get_real(name);
		engine.guard_mock_target('mock.inject_all', name, proxy_channels, real);
		if (type(states[name]) !== 'object' || states[name] === null)
			die(sprintf("mock.inject_all: state for '%s' must be a non-null object", name));
		reals[name] = real;
		channels_map[name] = proxy_channels || ['data'];
		engine.validate_state('mock.inject_all', name, states[name], channels_map[name]);
	}

	// Push one layer per proxy, tracking count so cleanup covers only what was pushed.
	let pushed = 0;
	let err, had_err = false;
	let result;
	try {
		for (let name in names) {
			const reg = engine.get_registry(name);
			engine.ensure_channels(reg, channels_map[name]);
			push(reg.layers, engine.to_layer(states[name], channels_map[name]));
			pushed++;
		}
		const deps = {};
		for (let name in names)
			deps[name] = engine.build_proxy(name, reals[name]);
		result = cb(deps);
	} catch (e) {
		err = e; had_err = true;
	}

	// Pop in reverse order, limited to what was successfully pushed.
	for (let i = pushed - 1; i >= 0; i--)
		pop(engine.get_registry(names[i]).layers);

	if (had_err) die(err);
	return result;
};

// Re-export so mock.inject_builtin() stays at the top-level namespace.
export const inject_builtin = _global.inject_builtin;

// The worker runner reads this to call snapshot()/restore() around each test
// without importing this module directly (decoupled so unmocked test files
// never trigger the engine). Must run before `export const global` shadows
// the built-in `global` identifier below.
if (!global.__utest_mock_instance)
	global.__utest_mock_instance = { snapshot, restore, reset };

export const global = _global;
