// Loaded via require() in ucode program mode — see proxy_base.uc for why `return` is used here.
return {
	api: ['new'],
	create: function(name, real, ctx) {
		let proxy = ctx.base();

		proxy.new = function(url, auth, callbacks) {
			let f = ctx.get_behavior('new');
			if (f) return f(url, auth, callbacks);

			let _body_served = false;

			// u must be assigned before method bodies run so closures can reference it.
			let u = {};

			u.ssl_init = function(opts) {
				let f = ctx.get_behavior('ssl_init');
				if (f) return f(opts);
				return true;
			};

			u.set_timeout = function(ms) {
				let f = ctx.get_behavior('set_timeout');
				if (f) return f(ms);
			};

			u.connect = function() {
				let f = ctx.get_behavior('connect');
				if (f) return f();
				return true;
			};

			u.request = function(method, opts) {
				let f = ctx.get_behavior('request');
				if (f) return f(method, opts);

				let response = ctx.get_data(url);
				if (response == null) {
					if (ctx.is_strict())
						die(sprintf("strict mock: uclient.request('%s') is not mocked", url));
					return false;
				}

				if (response.error != null) {
					if (callbacks && callbacks.error)
						callbacks.error(u, response.error);
					return true;
				}

				if (callbacks && callbacks.header_done)
					callbacks.header_done(u);
				if (callbacks && callbacks.data_read && response.body != null)
					callbacks.data_read(u);
				if (callbacks && callbacks.data_eof)
					callbacks.data_eof(u);
				return true;
			};

			u.get_headers = function() {
				let f = ctx.get_behavior('get_headers');
				if (f) return f();
				let response = ctx.get_data(url);
				return (response && response.headers) ? response.headers : {};
			};

			u.status = function() {
				let f = ctx.get_behavior('status');
				if (f) return f();
				let response = ctx.get_data(url);
				return (response && response.status != null) ? { status: response.status } : null;
			};

			u.read = function() {
				let f = ctx.get_behavior('read');
				if (f) return f();
				if (_body_served) return null;
				_body_served = true;
				let response = ctx.get_data(url);
				return (response && response.body != null) ? response.body : null;
			};

			u.disconnect = function() {
				let f = ctx.get_behavior('disconnect');
				if (f) return f();
			};

			return u;
		};

		return proxy;
	}
};
