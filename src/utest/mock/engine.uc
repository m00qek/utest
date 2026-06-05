if (!global.__utest_registries) global.__utest_registries = {};
const registries = global.__utest_registries;

function deep_clone(obj) {
	if (type(obj) == 'array') {
		let r = [];
		for (let v in obj) push(r, deep_clone(v));
		return r;
	}
	if (type(obj) == 'object') {
		let r = {};
		for (let k, v in obj) r[k] = deep_clone(v);
		return r;
	}
	// scalars (string, int, bool, null) and functions are immutable — share the reference
	return obj;
}

// Returns the channel list declared by the proxy for `name`.  Always includes
// 'data'; extra channels come from the proxy factory's `channels` array.
function get_proxy_channels(name) {
	let m = null;
	try { m = require('utest.mock.proxy.' + name); } catch(e) {}
	if (!m || type(m.channels) != 'array') return ['data'];
	let channels = ['data'];
	for (let ch in m.channels)
		if (ch != 'data') push(channels, ch);
	return channels;
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
			if (existing == ch) { found = true; break; }
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

if (!global.__utest_internal_instance) global.__utest_internal_instance = {};
const internal_obj = global.__utest_internal_instance;

internal_obj.get_channel = function(name, channel, key) {
	const reg = get_registry(name);
	for (let i = length(reg.layers) - 1; i >= 0; i--) {
		if (reg.layers[i][channel] && exists(reg.layers[i][channel], key))
			return reg.layers[i][channel][key];
	}
	if (reg.global[channel] && exists(reg.global[channel], key))
		return reg.global[channel][key];
	return null;
};

internal_obj.set_channel = function(name, channel, key, val) {
	const reg = get_registry(name);
	const layers = reg.layers;
	const target = length(layers) > 0 ? layers[length(layers) - 1] : reg.global;
	if (!target[channel]) target[channel] = {};
	target[channel][key] = val;
};

internal_obj.get_all_channel_keys = function(name, channel) {
	const reg = get_registry(name);
	let keys_map = {};
	for (let i = length(reg.layers) - 1; i >= 0; i--)
		if (reg.layers[i][channel])
			for (let k, v in reg.layers[i][channel]) keys_map[k] = true;
	if (reg.global[channel])
		for (let k, v in reg.global[channel]) keys_map[k] = true;
	return keys(keys_map);
};

internal_obj.get_data = function(name, key) {
	return internal_obj.get_channel(name, 'data', key);
};

internal_obj.set_data = function(name, key, val) {
	internal_obj.set_channel(name, 'data', key, val);
};

internal_obj.get_fn = function(name, fn_name) {
	const reg = get_registry(name);
	for (let i = length(reg.layers) - 1; i >= 0; i--) {
		if (exists(reg.layers[i].fns, fn_name)) return reg.layers[i].fns[fn_name];
	}
	if (exists(reg.global.fns, fn_name)) return reg.global.fns[fn_name];
	return null;
};

internal_obj.is_active = function(name) {
	const reg = get_registry(name);
	return length(reg.layers) > 0
	    || length(keys(reg.global.data)) > 0
	    || length(keys(reg.global.fns)) > 0
	    || reg.global.proxy != null;
};

internal_obj.get_all_data_keys = function(name) {
	return internal_obj.get_all_channel_keys(name, 'data');
};

internal_obj.record_call = function(name, fn_name, args) {
	const reg = get_registry(name);
	const target = length(reg.layers) > 0 ? reg.layers[length(reg.layers) - 1] : reg.global;
	if (!target.calls[fn_name]) target.calls[fn_name] = [];
	push(target.calls[fn_name], args);
};

internal_obj.get_calls = function(name) {
	const reg = get_registry(name);
	const target = length(reg.layers) > 0 ? reg.layers[length(reg.layers) - 1] : reg.global;
	return target.calls;
};

internal_obj.get_proxy_global = function(name) {
	return get_registry(name).global.proxy || null;
};

internal_obj.is_strict = function(name) {
	const reg = get_registry(name);
	if (reg.global.strict) return true;
	for (let i = 0; i < length(reg.layers); i++)
		if (reg.layers[i].strict) return true;
	return false;
};

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
		if (m && type(m.api) == 'array') {
			const calls = internal_obj.get_calls(name);
			for (let fn_name in m.api)
				if (!calls[fn_name]) calls[fn_name] = [];
		}
		return proxy;
	}

	// Generic proxy: behavior overrides, passthrough to real otherwise
	return ctx.base();
}

if (!global.__utest_mock_instance) global.__utest_mock_instance = {};
const mock_obj = global.__utest_mock_instance;

mock_obj.reset = function() {
	reset_layers();
};

mock_obj.snapshot = function() {
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

mock_obj.restore = function(snap) {
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

// When a shim is in -L, require(name) finds the shim's ES-module .uc and fails
// (program mode forbids import/export). Try real_<name> first (the symlink to
// the actual module created by manager.uc), then fall back to require(name).
function get_real(name) {
	try { return require('real_' + name); } catch(e) {}
	try { return require(name); }           catch(e) {}
	warn(sprintf("[utest] warning: could not load module '%s'; non-overridden calls on its proxy will fail\n", name));
	return null;
}

mock_obj.inject = function(name, state, cb) {
	const channels = get_proxy_channels(name);
	const reg = get_registry(name);
	ensure_channels(reg, channels);
	push(reg.layers, to_layer(state, channels));
	let err = null;
	let result;
	try {
		let proxy = build_proxy(name, get_real(name));
		result = cb(proxy);
	} catch (e) {
		err = e;
	}
	pop(reg.layers);
	if (err != null) die(err);
	return result;
};

mock_obj.global = {
	patch: function(name, state) {
		const channels = get_proxy_channels(name);
		const reg = get_registry(name);
		ensure_channels(reg, channels);
		for (let ch in channels)
			reg.global[ch] = state[ch] ? deep_clone(state[ch]) : {};
		reg.global.fns    = state.behavior ? { ...state.behavior }  : {};
		reg.global.strict = state.strict   ? true : false;
		reg.global.calls  = {};
		const proxy = build_proxy(name, get_real(name));
		reg.global.proxy = proxy;
		return proxy;
	},

	unpatch: function(name) {
		const reg = get_registry(name);
		let new_global = { fns: {}, strict: false, proxy: null, calls: {} };
		for (let ch in reg.channels) new_global[ch] = {};
		reg.global = new_global;
	}
};

export const mock = mock_obj;
export const __internal__ = internal_obj;
