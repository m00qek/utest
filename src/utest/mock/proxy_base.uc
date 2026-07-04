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
	// is_live() reports whether the owning inject()/patch() scope is still active.
	// Every second-order object a proxy hands out (an fs open() handle, a uci
	// cursor, a ubus connection, a uclient handle) closes over this ctx and reaches
	// mock state only through it, so guarding the state-touching methods here makes
	// a use of any such object after its scope ended die — instead of silently
	// reading or corrupting reg.global (guard_proxy only covers the proxy's own
	// top-level methods). `guarded` wraps each state method with that check; pure
	// (clone) and metadata (is_active/is_strict) accessors are left ungated, and a
	// null is_live (a caller that never scopes) makes the check a no-op.
	context: function(name, real, is_live) {
		function guarded(fn) {
			return function(...args) {
				if (is_live && !is_live())
					die(sprintf("[utest] mock: a '%s' mock object was used outside its scope — its inject()/patch() has already ended", name));
				return fn(...args);
			};
		}
		return {
			// Generic channel API — preferred for proxies with multiple namespaces
			get:      guarded(function(channel, key)      { return __internal__.get_channel(name, channel, key); }),
			// Read only the current scope (no fall-through), symmetric with set().
			// Use for transient per-scope state a proxy consumes in place.
			get_local: guarded(function(channel, key)     { return __internal__.get_local_channel(name, channel, key); }),
			set:      guarded(function(channel, key, val) { __internal__.set_channel(name, channel, key, val); }),

			// Shorthands for the 'data' channel — the primary API of every built-in
			// proxy (fs.uc alone uses get_data/set_data ~30 times); the generic
			// channel form above is for proxies that need multiple namespaces.
			get_data:          guarded(function(key)      { return __internal__.get_channel(name, 'data', key); }),
			get_local_data:    guarded(function(key)      { return __internal__.get_local_channel(name, 'data', key); }),
			set_data:          guarded(function(key, val) { __internal__.set_channel(name, 'data', key, val); }),
			get_all_data_keys: guarded(function()         { return __internal__.get_all_channel_keys(name, 'data'); }),
			has_data:          guarded(function(key)      { return __internal__.has_channel(name, 'data', key); }),
			has:               guarded(function(ch, key)  { return __internal__.has_channel(name, ch, key); }),

			// Deep-copy a value read out of the mock store, so a proxy can hand back a
			// fresh value the way a real module would (real uci/fs return copies) —
			// SUT mutation of the result must not corrupt layer state. Pure, so ungated.
			clone:             function(v)             { return __internal__.deep_clone(v); },
			get_behavior:      guarded(function(fn_name)  { return __internal__.get_fn(name, fn_name); }),
			record_call:       guarded(function(fn_name, args){ __internal__.record_call(name, fn_name, args); }),
			is_active:         function()             { return __internal__.is_active(name); },
			is_strict:         function()             { return __internal__.is_strict(name); },
			// Forward to the real module, or return `fallback` when it could not be
			// loaded (real === null).  Centralizes the null-guard so a proxy method
			// can never accidentally dereference a null real module.
			real_call:         guarded(function(fn_name, args, fallback) { return real ? real[fn_name](...args) : fallback; }),
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
