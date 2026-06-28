/**
 * Mock engine: state registry, layer stack, proxy construction, and snapshot/restore.
 *
 * @module utest.mock.engine
 */

if (!global.__utest_registries) global.__utest_registries = {};
const registries = global.__utest_registries;

function deep_clone(obj) {
	if (type(obj) === 'array') {
		let r = [];
		for (let v in obj) push(r, deep_clone(v));
		return r;
	}
	if (type(obj) === 'object') {
		let r = {};
		for (let k, v in obj) r[k] = deep_clone(v);
		return r;
	}
	// scalars (string, int, bool, null) and functions are immutable — share the reference
	return obj;
}

// Returns the channel list declared by the proxy for `name`, or null if no
// proxy module exists.  Always includes 'data'; extra channels come from the
// proxy factory's `channels` array.
function get_proxy_channels(name) {
	let m = null;
	try { m = require('utest.mock.proxy.' + name); } catch(e) {}
	if (!m) return null;
	const channels = ['data'];
	if (type(m.channels) === 'array') {
		for (let ch in m.channels)
			if (ch !== 'data') push(channels, ch);
	}
	return channels;
}

function guard_mock_target(op, name, proxy_channels, real) {
	if (proxy_channels === null && real === null)
		die(sprintf("[utest] %s: '%s' is not a configured proxy — no proxy module found at utest.mock.proxy.%s", op, name, name));
}

function get_registry(name) {
	if (!registries[name]) {
		registries[name] = {
			name: name,
			channels: ['data'],
			layers: [],
			global: { data: {}, fns: {}, strict: false, proxy: null, calls: {} }
		};
	}
	return registries[name];
}

// Adds any channels that are not yet tracked to the registry's channel list
// and ensures their slot exists on the global state object.
function ensure_channels(reg, channels) {
	for (let ch in channels) {
		if (!exists(reg.global, ch)) reg.global[ch] = {};
		let found = false;
		for (let existing in reg.channels)
			if (existing === ch) { found = true; break; }
		if (!found) push(reg.channels, ch);
	}
}

function to_layer(state, channels) {
	let layer = {
		fns:    state.behavior ? { ...state.behavior } : {},
		strict: state.strict   ? true : false,
		calls:  {}
	};
	for (let ch in channels)
		layer[ch] = state[ch] ? deep_clone(state[ch]) : {};
	return layer;
}

function reset_layers() {
	for (let name, reg in registries) {
		reg.layers = [];
	}
}

// Saved originals for mock.global.patch_builtin(); keyed by built-in name.
if (!global.__utest_builtin_overrides) global.__utest_builtin_overrides = {};
const builtin_overrides = global.__utest_builtin_overrides;

function _channel_get(name, channel, key) {
	const reg = get_registry(name);
	for (let i = length(reg.layers) - 1; i >= 0; i--) {
		if (reg.layers[i][channel] && exists(reg.layers[i][channel], key))
			return reg.layers[i][channel][key];
	}
	if (reg.global[channel] && exists(reg.global[channel], key))
		return reg.global[channel][key];
	return null;
}

function _channel_set(name, channel, key, val) {
	const reg = get_registry(name);
	const layers = reg.layers;
	const target = length(layers) > 0 ? layers[length(layers) - 1] : reg.global;
	if (!target[channel]) target[channel] = {};
	target[channel][key] = val;
}

function _channel_all_keys(name, channel) {
	const reg = get_registry(name);
	let keys_map = {};
	for (let i = length(reg.layers) - 1; i >= 0; i--)
		if (reg.layers[i][channel])
			for (let k, v in reg.layers[i][channel]) keys_map[k] = true;
	if (reg.global[channel])
		for (let k, v in reg.global[channel]) keys_map[k] = true;
	return keys(keys_map);
}

const internal_obj = {
	get_channel:          _channel_get,
	set_channel:          _channel_set,
	get_all_channel_keys: _channel_all_keys,

	get_fn: function(name, fn_name) {
		const reg = get_registry(name);
		for (let i = length(reg.layers) - 1; i >= 0; i--) {
			if (exists(reg.layers[i].fns, fn_name)) return reg.layers[i].fns[fn_name];
		}
		if (exists(reg.global.fns, fn_name)) return reg.global.fns[fn_name];
		return null;
	},

	is_active: function(name) {
		const reg = get_registry(name);
		if (length(reg.layers) > 0 || reg.global.proxy !== null || length(keys(reg.global.fns)) > 0)
			return true;
		for (let ch in reg.channels)
			if (length(keys(reg.global[ch])) > 0) return true;
		return false;
	},

	record_call: function(name, fn_name, args) {
		const reg = get_registry(name);
		const target = length(reg.layers) > 0 ? reg.layers[length(reg.layers) - 1] : reg.global;
		if (!target.calls[fn_name]) target.calls[fn_name] = [];
		push(target.calls[fn_name], args);
	},

	get_calls: function(name) {
		const reg = get_registry(name);
		const target = length(reg.layers) > 0 ? reg.layers[length(reg.layers) - 1] : reg.global;
		return target.calls;
	},

	get_proxy_global: function(name) {
		return get_registry(name).global.proxy || null;
	},

	is_strict: function(name) {
		const reg = get_registry(name);
		if (reg.global.strict) return true;
		for (let i = 0; i < length(reg.layers); i++)
			if (reg.layers[i].strict) return true;
		return false;
	}
};

if (!global.__utest_internal_instance) global.__utest_internal_instance = internal_obj;

// When a shim is in -L, require(name) finds the shim's ES-module .uc and fails
// (program mode forbids import/export). Try real_<name> first (the symlink to
// the actual module created by manager.uc), then fall back to require(name).
function get_real(name) {
	try { return require('real_' + name); } catch(e) {}
	try { return require(name); }           catch(e) {}
	warn(sprintf("[utest] warning: could not load module '%s'; non-overridden calls on its proxy will fail\n", name));
	return null;
}

function build_proxy(name, real) {
	const proxy_base = require('utest.mock.proxy_base');
	const ctx = proxy_base.context(name, real);

	// Module-specific proxy factory (e.g. utest/mock/proxy/fs.uc)
	let factory;
	let m = null;
	try {
		m = require('utest.mock.proxy.' + name);
		factory = m ? m.create : null;
	} catch(e) {
		factory = null;
	}
	if (factory) {
		const proxy = factory(name, real, ctx);
		// Pre-initialize calls for declared API methods so spy(proxy).calls.X is
		// always [] and never undefined, even before the first call is made.
		if (m && type(m.api) === 'array') {
			const calls = internal_obj.get_calls(name);
			for (let fn_name in m.api)
				if (!calls[fn_name]) calls[fn_name] = [];
		}
		return proxy;
	}

	// Generic proxy: behavior overrides, passthrough to real otherwise
	return ctx.base();
}

/**
 * @example
 * mock.inject('fs', { data: { '/etc/config': 'hello' } }, (fs) => {
 *     assert.match('hello', fs.readfile('/etc/config'));
 * });
 */
export const mock = {
	/**
	 * Completely resets all mock state, clearing all registries.
	 */
	reset: function() {
		reset_layers();
	},

	/**
	 * Takes a snapshot of the current mock registries.
	 *
	 * @returns {dict<any>} An opaque snapshot object.
	 */
	snapshot: function() {
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
	},

	/**
	 * Restores mock state from a previously taken snapshot.
	 *
	 * @param {dict<any>} snap - The snapshot object returned by `mock.snapshot()`.
	 */
	restore: function(snap) {
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
	},

	/**
	 * Injects a temporary mock for a built-in global variable during a callback.
	 *
	 * @param {string} name - The name of the built-in (e.g. 'fs', 'print').
	 * @param {any} fn - The mock value to inject.
	 * @param {function(): any} cb - The callback to execute while injected.
	 * @returns {any} The return value of the callback.
	 */
	inject_builtin: function(name, fn, cb) {
		const orig = global[name];
		global[name] = fn;
		let err = null;
		let result;
		try {
			result = cb();
		} catch (e) {
			err = e;
		}
		global[name] = orig;
		if (err !== null) die(err);
		return result;
	},

	/**
	 * Injects a temporary mock state for a module during a callback.
	 *
	 * @example
	 * mock.inject('fs', { data: { '/test.txt': 'hello' } }, (fs) => {
	 *     assert.match('hello', fs.readfile('/test.txt'));
	 * });
	 *
	 * @param {string} name - The name of the module.
	 * @param {dict<any>} state - The mock state configuration.
	 * @param {dict<any>} [state.data] - Declarative state channels (e.g. file contents or UCI trees).
	 * @param {dict<function>} [state.behavior] - Function overrides to execute custom logic.
	 * @param {boolean} [state.strict] - If true, unmocked accesses throw an error.
	 * @param {dict<string>} [state.commands] - Pre-seeded shell command outputs (used by 'fs.popen').
	 * @param {function(any): any} cb - The callback to execute while injected, receiving the proxy.
	 * @returns {any} The return value of the callback.
	 */
	inject: function(name, state, cb) {
		const proxy_channels = get_proxy_channels(name);
		const real = get_real(name);
		guard_mock_target('mock.inject', name, proxy_channels, real);
		const channels = proxy_channels || ['data'];
		const reg = get_registry(name);
		ensure_channels(reg, channels);
		push(reg.layers, to_layer(state, channels));
		let err = null;
		let result;
		try {
			let proxy = build_proxy(name, real);
			result = cb(proxy);
		} catch (e) {
			err = e;
		}
		pop(reg.layers);
		if (err !== null) die(err);
		return result;
	},

	inject_all: function(states, cb) {
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
		let err = null;
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
			err = e;
		}

		// Pop in reverse order, limited to what was successfully pushed.
		for (let i = pushed - 1; i >= 0; i--)
			pop(get_registry(names[i]).layers);

		if (err !== null) die(err);
		return result;
	},

	/**
	 * Global patching utilities.
	 */
	global: {
		/**
		 * Permanently patches a module with mock state.
		 *
		 * @example
		 * const fs = mock.global.patch('fs', { data: { '/test.txt': 'hello' } });
		 *
		 * @param {string} name - The name of the module.
		 * @param {dict<any>} state - The mock state configuration.
		 * @param {dict<any>} [state.data] - Declarative state channels (e.g. file contents or UCI trees).
		 * @param {dict<function>} [state.behavior] - Function overrides to execute custom logic.
		 * @param {boolean} [state.strict] - If true, unmocked accesses throw an error.
		 * @param {dict<string>} [state.commands] - Pre-seeded shell command outputs (used by 'fs.popen').
		 * @returns {any} The configured proxy.
		 */
		patch: function(name, state) {
			const proxy_channels = get_proxy_channels(name);
			const real = get_real(name);
			guard_mock_target('mock.global.patch', name, proxy_channels, real);
			const channels = proxy_channels || ['data'];
			const reg = get_registry(name);
			ensure_channels(reg, channels);
			for (let ch in channels)
				reg.global[ch] = state[ch] ? deep_clone(state[ch]) : {};
			reg.global.fns    = state.behavior ? { ...state.behavior }  : {};
			reg.global.strict = state.strict   ? true : false;
			reg.global.calls  = {};
			const proxy = build_proxy(name, real);
			reg.global.proxy = proxy;
			return proxy;
		},

		/**
		 * Removes a global patch for a module.
		 *
		 * @param {string} name - The name of the module to unpatch.
		 */
		unpatch: function(name) {
			const reg = get_registry(name);
			let new_global = { fns: {}, strict: false, proxy: null, calls: {} };
			for (let ch in reg.channels) new_global[ch] = {};
			reg.global = new_global;
		},

		/**
		 * Permanently patches a built-in global variable.
		 *
		 * @param {string} name - The name of the built-in.
		 * @param {any} fn - The mock value.
		 */
		patch_builtin: function(name, fn) {
			builtin_overrides[name] = global[name];
			global[name] = fn;
		},

		/**
		 * Removes a global patch for a built-in global variable.
		 *
		 * @param {string} name - The name of the built-in to unpatch.
		 */
		unpatch_builtin: function(name) {
			if (exists(builtin_overrides, name)) {
				global[name] = builtin_overrides[name];
				delete builtin_overrides[name];
			}
		}
	}
};

if (!global.__utest_mock_instance) global.__utest_mock_instance = mock;

export const __internal__ = internal_obj;
