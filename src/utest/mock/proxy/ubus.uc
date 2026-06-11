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

					let val = ctx.get_data(obj + ':' + method);
					if (val === null) val = ctx.get_data(obj);

					if (val === null) {
						if (ctx.is_strict())
							die(sprintf("strict mock: ubus.call('%s', '%s') is not mocked", obj, method));
						return null;
					}

					return (type(val) === 'function') ? val(args) : val;
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
