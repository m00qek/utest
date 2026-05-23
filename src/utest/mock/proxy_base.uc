// Loaded via require() in ucode program mode (not ES-module mode), so import/export
// is unavailable. Exports are expressed as a bare `return` at module scope.
const __internal__ = global.__utest_internal_instance;

function make_behavior_fn(mod_name, fn_name, fn) {
	return function(...args) {
		__internal__.record_call(mod_name, fn_name, args);
		let override = __internal__.get_fn(mod_name, fn_name);
		if (override) return override(...args);
		if (__internal__.is_strict(mod_name))
			die(sprintf("strict mock: '%s.%s' is not mocked", mod_name, fn_name));
		return fn(...args);
	};
}

return {
	context: function(name, real) {
		return {
			get_behavior:      function(fn_name) { return __internal__.get_fn(name, fn_name); },
			get_data:          function(key)     { return __internal__.get_data(name, key); },
			set_data:          function(key, val){ __internal__.set_data(name, key, val); },
			record_call:       function(fn_name, args) { __internal__.record_call(name, fn_name, args); },
			is_active:         function()        { return __internal__.is_active(name); },
			is_strict:         function()        { return __internal__.is_strict(name); },
			get_all_data_keys: function()        { return __internal__.get_all_data_keys(name); },
			base: function() {
				let proxy = {};
				const calls = __internal__.get_calls(name);
				for (let fn_name, fn in (real || {})) {
					if (type(fn) == 'function') {
						calls[fn_name] = calls[fn_name] || [];
						proxy[fn_name] = make_behavior_fn(name, fn_name, fn);
					} else {
						proxy[fn_name] = fn;
					}
				}
				proxy.__utest__ = { calls: calls };
				return proxy;
			}
		};
	}
};
