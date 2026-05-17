// Loaded via require() in ucode program mode — see proxy_base.uc for why `return` is used here.
return {
	api: ['init', 'timer', 'run', 'end'],
	create: function(name, real, ctx) {
		let proxy = ctx.base();

		proxy.init = function() {
			let f = ctx.get_behavior('init');
			if (f) return f();
		};

		proxy.timer = function(ms, cb) {
			let f = ctx.get_behavior('timer');
			if (f) return f(ms, cb);
			let pending = ctx.get_data('__pending__');
			if (type(pending) != 'array') {
				pending = [];
				ctx.set_data('__pending__', pending);
			}
			push(pending, { ms, cb });
		};

		proxy.run = function() {
			let f = ctx.get_behavior('run');
			if (f) return f();
			let pending = ctx.get_data('__pending__') || [];
			ctx.set_data('__pending__', []);
			for (let t in pending) t.cb();
		};

		proxy.end = function() {
			let f = ctx.get_behavior('end');
			if (f) return f();
		};

		return proxy;
	}
};
