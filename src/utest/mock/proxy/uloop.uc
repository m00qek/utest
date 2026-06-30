// Loaded via require() in ucode program mode — see proxy_base.uc for why `return` is used here.
return {
	api: ['init', 'timer', 'run', 'end'],
	create: function(name, real, ctx) {
		let proxy = ctx.base();

		proxy.init = function() {
			ctx.record_call('init', []);
			let f = ctx.get_behavior('init');
			if (f) return f();
		};

		proxy.timer = function(ms, cb) {
			ctx.record_call('timer', [ms, cb]);
			let f = ctx.get_behavior('timer');
			if (f) return f(ms, cb);
			const pending = ctx.get_data('__pending__');
			ctx.set_data('__pending__', [...(type(pending) === 'array' ? pending : []), { ms, cb }]);
		};

		proxy.run = function() {
			ctx.record_call('run', []);
			let f = ctx.get_behavior('run');
			if (f) return f();
			let pending = ctx.get_data('__pending__') || [];
			ctx.set_data('__pending__', []);
			for (let t in pending) t.cb();
		};

		proxy.end = function() {
			ctx.record_call('end', []);
			let f = ctx.get_behavior('end');
			if (f) return f();
		};

		return proxy;
	}
};
