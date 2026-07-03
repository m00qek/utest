// Loaded via require() in ucode program mode — see proxy_base.uc for why `return` is used here.
return {
	api: ['new'],
	create: function(name, real, ctx) {
		let proxy = ctx.base();

		proxy.new = function(url, auth, callbacks) {
			ctx.record_call('new', [url, auth, callbacks]);
			let f = ctx.get_behavior('new');
			if (f) return f(url, auth, callbacks);

			let _body_served = false;
			let u_calls = { ssl_init: [], set_timeout: [], connect: [], request: [], get_headers: [], status: [], read: [], disconnect: [] };

			// u must be assigned before method bodies run so closures can reference it.
			let u = {};
			u.__utest__ = { calls: u_calls };

			u.ssl_init = function(opts) {
				push(u_calls.ssl_init, [opts]);
				let f = ctx.get_behavior('ssl_init');
				if (f) return f(opts);
				return true;
			};

			u.set_timeout = function(ms) {
				push(u_calls.set_timeout, [ms]);
				let f = ctx.get_behavior('set_timeout');
				if (f) return f(ms);
			};

			u.connect = function() {
				push(u_calls.connect, []);
				let f = ctx.get_behavior('connect');
				if (f) return f();
				return true;
			};

			u.request = function(method, opts) {
				push(u_calls.request, [method, opts]);
				// A new request serves a fresh response body; reset so read() returns
				// it instead of the previous request's already-consumed EOF (real
				// uclient serves each response's body when a handle is reused).
				_body_served = false;
				let f = ctx.get_behavior('request');
				if (f) return f(method, opts);

				// Use has_data so a URL explicitly mocked to null is treated as a
				// real (unreachable) response, not as "unmocked" — otherwise it
				// would trip strict mode instead of returning false.
				if (!ctx.has_data(url)) {
					if (ctx.is_strict())
						die(sprintf("strict mock: uclient.request('%s') is not mocked", url));
					return false;
				}

				let response = ctx.get_data(url);
				if (response === null)
					return false;

				if (response.error !== null) {
					if (callbacks && callbacks.error)
						callbacks.error(u, response.error);
					return true;
				}

				if (callbacks && callbacks.header_done)
					callbacks.header_done(u);
				if (callbacks && callbacks.data_read && response.body !== null)
					callbacks.data_read(u);
				if (callbacks && callbacks.data_eof)
					callbacks.data_eof(u);
				return true;
			};

			u.get_headers = function() {
				push(u_calls.get_headers, []);
				let f = ctx.get_behavior('get_headers');
				if (f) return f();
				let response = ctx.get_data(url);
				return (response && response.headers) ? response.headers : {};
			};

			u.status = function() {
				push(u_calls.status, []);
				let f = ctx.get_behavior('status');
				if (f) return f();
				let response = ctx.get_data(url);
				return (response && response.status !== null) ? { status: response.status } : null;
			};

			u.read = function() {
				push(u_calls.read, []);
				let f = ctx.get_behavior('read');
				if (f) return f();
				if (_body_served) return null;
				_body_served = true;
				let response = ctx.get_data(url);
				return (response && response.body !== null) ? response.body : null;
			};

			u.disconnect = function() {
				push(u_calls.disconnect, []);
				let f = ctx.get_behavior('disconnect');
				if (f) return f();
			};

			return u;
		};

		return proxy;
	}
};
