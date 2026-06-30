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
			// Generic channel API — preferred for proxies with multiple namespaces
			get:      function(channel, key)      { return __internal__.get_channel(name, channel, key); },
			set:      function(channel, key, val) { __internal__.set_channel(name, channel, key, val); },
			all_keys: function(channel)           { return __internal__.get_all_channel_keys(name, channel); },

			// Shorthands for the 'data' channel — kept for backward compatibility
			get_data:          function(key)      { return __internal__.get_channel(name, 'data', key); },
			set_data:          function(key, val) { __internal__.set_channel(name, 'data', key, val); },
			get_all_data_keys: function()         { return __internal__.get_all_channel_keys(name, 'data'); },
			has_data:          function(key)      { return __internal__.has_channel(name, 'data', key); },
			has:               function(ch, key)  { return __internal__.has_channel(name, ch, key); },

			get_behavior:      function(fn_name)      { return __internal__.get_fn(name, fn_name); },
			record_call:       function(fn_name, args){ __internal__.record_call(name, fn_name, args); },
			is_active:         function()             { return __internal__.is_active(name); },
			is_strict:         function()             { return __internal__.is_strict(name); },
			base: function() {
				let proxy = {};
				const calls = __internal__.get_calls(name);
				for (let fn_name, fn in (real || {})) {
					if (type(fn) === 'function') {
						calls[fn_name] = calls[fn_name] || [];
						proxy[fn_name] = make_behavior_fn(name, fn_name, fn);
					} else {
						proxy[fn_name] = fn;
					}
				}
				proxy.__utest__ = { name: name };
				return proxy;
			}
		};
	}
};
