/**
 * Mock engine: state registry, layer stack, proxy construction, and snapshot/restore.
 *
 * @module utest.mock.engine
 */

if (!global.__utest_registries) global.__utest_registries = {};
export const registries = global.__utest_registries;

export function deep_clone(obj) {
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
};

// Returns the channel list declared by the proxy for `name`, or null if no
// proxy module exists.  Always includes 'data'; extra channels come from the
// proxy factory's `channels` array.
export function get_proxy_channels(name) {
	let m = null;
	try { m = require('utest.mock.proxy.' + name); } catch(e) {}
	if (!m) return null;
	const channels = ['data'];
	if (type(m.channels) === 'array') {
		for (let ch in m.channels)
			if (ch !== 'data') push(channels, ch);
	}
	return channels;
};

export function guard_mock_target(op, name, proxy_channels, real) {
	if (proxy_channels === null && real === null)
		die(sprintf("[utest] %s: '%s' is not a configured proxy — no proxy module found at utest.mock.proxy.%s", op, name, name));
};

export function get_registry(name) {
	if (!registries[name]) {
		registries[name] = {
			name: name,
			channels: ['data'],
			layers: [],
			global: { data: {}, fns: {}, strict: false, proxy: null, calls: {} }
		};
	}
	return registries[name];
};

// Adds any channels that are not yet tracked to the registry's channel list
// and ensures their slot exists on the global state object.
export function ensure_channels(reg, channels) {
	for (let ch in channels) {
		if (!exists(reg.global, ch)) reg.global[ch] = {};
		let found = false;
		for (let existing in reg.channels)
			if (existing === ch) { found = true; break; }
		if (!found) push(reg.channels, ch);
	}
};

export function to_layer(state, channels) {
	let layer = {
		fns:    state.behavior ? { ...state.behavior } : {},
		// Three-state: an explicit bool overrides; unset (null) inherits the
		// strictness of the enclosing layer/global (see is_strict). Collapsing
		// unset to false would let a nested inject silently disable an outer
		// strict boundary.
		strict: type(state.strict) == "bool" ? state.strict : null,
		calls:  {}
	};
	for (let ch in channels)
		layer[ch] = (exists(state, ch) && state[ch] !== null) ? deep_clone(state[ch]) : {};
	return layer;
};

export function reset_layers() {
	for (let name, reg in registries) {
		reg.layers = [];
	}
};

// Saved originals for mock.global.patch_builtin(); keyed by built-in name.
if (!global.__utest_builtin_overrides) global.__utest_builtin_overrides = {};
export const builtin_overrides = global.__utest_builtin_overrides;

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

// Read only the current scope (top layer, or global when none) with no
// fall-through — the exact location _channel_set writes to. A proxy holding
// transient per-scope state (e.g. uloop's timer queue) must read and write the
// same scope; a falling-through get would let it consume an outer scope's value
// while set could only clear its own, re-firing the outer value after a pop.
function _channel_get_local(name, channel, key) {
	const reg = get_registry(name);
	const scope = length(reg.layers) > 0 ? reg.layers[length(reg.layers) - 1] : reg.global;
	if (scope[channel] && exists(scope[channel], key))
		return scope[channel][key];
	return null;
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

function _channel_has(name, channel, key) {
	const reg = get_registry(name);
	for (let i = length(reg.layers) - 1; i >= 0; i--)
		if (reg.layers[i][channel] && exists(reg.layers[i][channel], key)) return true;
	return !!(reg.global[channel] && exists(reg.global[channel], key));
}

const internal_obj = {
	get_channel:          _channel_get,
	get_local_channel:    _channel_get_local,
	set_channel:          _channel_set,
	get_all_channel_keys: _channel_all_keys,
	has_channel:          _channel_has,

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
		// Walk layers top-down and honor the first that set strict explicitly
		// (true or false); a null layer inherits from below. Fall back to the
		// global state, whose strict is always a real bool.
		for (let i = length(reg.layers) - 1; i >= 0; i--) {
			if (reg.layers[i].strict !== null)
				return reg.layers[i].strict;
		}
		return reg.global.strict ? true : false;
	}
};

if (!global.__utest_internal_instance) global.__utest_internal_instance = internal_obj;

// When a shim is in -L, require(name) finds the shim's ES-module .uc and fails
// (program mode forbids import/export). Try real_<name> first (the symlink to
// the actual module created by manager.uc), then fall back to require(name).
export function get_real(name) {
	try { return require('real_' + name); } catch(e) {}
	try { return require(name); }           catch(e) {}
	warn(sprintf("[utest] warning: could not load module '%s'; non-overridden calls on its proxy will fail\n", name));
	return null;
};

export function build_proxy(name, real) {
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
};

export const __internal__ = internal_obj;
