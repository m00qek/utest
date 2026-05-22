if (!global.__utest_registries) global.__utest_registries = {};
const registries = global.__utest_registries;

function get_registry(name) {
	if (!registries[name]) {
		registries[name] = {
			name: name,
			layers: [],
			global: { data: {}, fns: {}, strict: false, proxy: null }
		};
	}
	return registries[name];
}

function to_layer(state) {
	return {
		data:   state.data     ? { ...state.data }     : {},
		fns:    state.behavior ? { ...state.behavior } : {},
		strict: state.strict   ? true : false
	};
}

function reset_layers() {
	for (let name, reg in registries) {
		reg.layers = [];
	}
}

if (!global.__utest_internal_instance) global.__utest_internal_instance = {};
const internal_obj = global.__utest_internal_instance;

internal_obj.get_data = function(name, key) {
	const reg = get_registry(name);
	for (let i = length(reg.layers) - 1; i >= 0; i--) {
		if (exists(reg.layers[i].data, key)) return reg.layers[i].data[key];
	}
	if (exists(reg.global.data, key)) return reg.global.data[key];
	return null;
};

internal_obj.set_data = function(name, key, val) {
	const reg = get_registry(name);
	const layers = reg.layers;
	const target = length(layers) > 0 ? layers[length(layers) - 1] : reg.global;
	target.data[key] = val;
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
	const reg = get_registry(name);
	let keys_map = {};
	for (let i = length(reg.layers) - 1; i >= 0; i--)
		for (let k, v in reg.layers[i].data) keys_map[k] = true;
	for (let k, v in reg.global.data) keys_map[k] = true;
	return keys(keys_map);
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
	try {
		let m = require('utest.mock.proxy.' + name);
		factory = m ? m.create : null;
	} catch(e) {
		factory = null;
	}
	if (factory) return factory(name, real, ctx);

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
		snap[name] = {
			data:   { ...reg.global.data },
			fns:    { ...reg.global.fns },
			strict: reg.global.strict,
			proxy:  reg.global.proxy
		};
	}
	return snap;
};

mock_obj.restore = function(snap) {
	reset_layers();
	for (let name, saved in snap) {
		get_registry(name).global = { ...saved };
	}
	for (let name in keys(registries)) {
		if (!exists(snap, name)) {
			registries[name].global = { data: {}, fns: {}, strict: false, proxy: null };
		}
	}
};

// When a shim is in -L, require(name) finds the shim's ES-module .uc and fails
// (program mode forbids import/export). Try real_<name> first (the symlink to
// the actual module created by manager.uc), then fall back to require(name).
function get_real(name) {
	try { return require('real_' + name); } catch(e) {}
	try { return require(name); }           catch(e) {}
	print(sprintf("[utest] warning: could not load module '%s'; non-overridden calls on its proxy will fail\n", name));
	return null;
}

mock_obj.inject = function(name, state, cb) {
	const reg = get_registry(name);
	push(reg.layers, to_layer(state));
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
		const reg = get_registry(name);
		reg.global.data   = state.data     ? { ...state.data }     : {};
		reg.global.fns    = state.behavior ? { ...state.behavior } : {};
		reg.global.strict = state.strict   ? true : false;
		const proxy = build_proxy(name, get_real(name));
		reg.global.proxy = proxy;
		return proxy;
	},

	unpatch: function(name) {
		const reg = get_registry(name);
		reg.global = { data: {}, fns: {}, strict: false, proxy: null };
	}
};

export const mock = mock_obj;
export const __internal__ = internal_obj;
