// Loaded via require() in ucode program mode — see proxy_base.uc for why `return` is used here.
return {
	create: function(name, real, ctx) {
		let proxy = ctx.base();

		proxy.connect = function() {
			ctx.record_call('connect', []);
			let f = ctx.get_behavior('connect');
			if (f) return f();

			let conn_calls = { call: [], disconnect: [] };
			return {
				__utest__: { calls: conn_calls },
				call: function(obj, method, args) {
					push(conn_calls.call, [obj, method, args]);
					let override = ctx.get_behavior('call');
					if (override) return override(obj, method, args);

					// Use has_data so a method (or object) explicitly mocked to null is
					// treated as a real null response, not as "unmocked" — otherwise an
					// intentional null reply would wrongly fall through to the object-level
					// mock or trip strict mode.
					let val, found = false;
					if (ctx.has_data(obj + ':' + method)) {
						val = ctx.get_data(obj + ':' + method); found = true;
					} else if (ctx.has_data(obj)) {
						val = ctx.get_data(obj); found = true;
					}

					if (!found) {
						if (ctx.is_strict())
							die(sprintf("strict mock: ubus.call('%s', '%s') is not mocked", obj, method));
						return null;
					}

					// Deep-clone a stored reply so a caller mutating the result cannot
					// corrupt the mock store for the next call (real ubus returns a fresh
					// object per call). A data-as-function reply owns its own return value.
					return (type(val) === 'function') ? val(args) : ctx.clone(val);
				},
				disconnect: function() {
					push(conn_calls.disconnect, []);
					let override = ctx.get_behavior('disconnect');
					if (override) return override();
				}
			};
		};

		return proxy;
	}
};
