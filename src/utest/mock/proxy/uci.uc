// Loaded via require() in ucode program mode — see proxy_base.uc for why `return` is used here.
return {
	create: function(name, real, ctx) {
		let proxy = ctx.base();

		proxy.cursor = function() {
			ctx.record_call('cursor', []);
			let f = ctx.get_behavior('cursor');
			if (f) return f();

			let cursor_calls = { load: [], get: [], get_all: [], foreach: [], set: [], commit: [], save: [], "delete": [] };
			return {
				__utest__: { calls: cursor_calls },

				load: function(pkg) {
					push(cursor_calls.load, [pkg]);
					let override = ctx.get_behavior('load');
					if (override) return override(pkg);
					// Real uci load() returns false for a package that has no config.
					// Under strict, an unmocked package reports that false (rather than
					// dying) — get()/foreach()/get_all()/delete() still enforce strict on
					// any actual data access, so a typo is still caught the moment the
					// code reads. Non-strict stays optimistic (always true).
					if (ctx.is_strict() && type(ctx.get_data(pkg)) !== 'object')
						return false;
					return true;
				},

				get: function(pkg, sec, opt) {
					push(cursor_calls.get, [pkg, sec, opt]);
					let override = ctx.get_behavior('get');
					if (override) return override(pkg, sec, opt);

					let p = ctx.get_data(pkg);
					if (type(p) !== 'object') {
						if (ctx.is_strict()) die(sprintf("strict mock: uci package '%s' is not mocked", pkg));
						return null;
					}
					let s = p[sec];
					if (type(s) !== 'object') return null;
					// 2-arg get(pkg, sec): real uci returns the section type.
					if (opt === null) return s['.type'];
					return s[opt];
				},

				get_all: function(pkg, sec) {
					push(cursor_calls.get_all, [pkg, sec]);
					let override = ctx.get_behavior('get_all');
					if (override) return override(pkg, sec);

					let p = ctx.get_data(pkg);
					if (type(p) !== 'object') {
						if (ctx.is_strict()) die(sprintf("strict mock: uci package '%s' is not mocked", pkg));
						return null;
					}
					let s = p[sec];
					if (type(s) !== 'object') return null;
					return { ...s, '.name': sec };
				},

				foreach: function(pkg, type_name, cb) {
					push(cursor_calls.foreach, [pkg, type_name, cb]);
					let override = ctx.get_behavior('foreach');
					if (override) return override(pkg, type_name, cb);

					let p = ctx.get_data(pkg);
					if (type(p) !== 'object') {
						if (ctx.is_strict()) die(sprintf("strict mock: uci package '%s' is not mocked", pkg));
						return;
					}
					let matched = false;
					for (let sec_name, sec in p) {
						// Real uci visits every section when type_name is null; only
						// filter by type when a type was actually requested.
						if (type(sec) !== 'object' || (type_name !== null && sec['.type'] !== type_name)) continue;
						let s = { ...sec };
						s['.name'] = sec_name;
						cb(s);
						matched = true;
					}
					// Real uci foreach returns false when no section of the type exists,
					// so callers can detect "no matching sections" — don't always claim true.
					return matched;
				},

				set: function(pkg, sec, opt, val) {
					push(cursor_calls.set, [pkg, sec, opt, val]);
					let override = ctx.get_behavior('set');
					if (override) return override(pkg, sec, opt, val);

					let p = ctx.get_data(pkg);
					p = (type(p) === 'object') ? { ...p } : {};
					p[sec] = (type(p[sec]) === 'object') ? { ...p[sec] } : {};
					p[sec][opt] = val;
					ctx.set_data(pkg, p);
					return true;
				},

				commit: function(pkg) {
					push(cursor_calls.commit, [pkg]);
					let override = ctx.get_behavior('commit');
					if (override) return override(pkg);
					return true;
				},

				save: function(pkg) {
					push(cursor_calls.save, [pkg]);
					let override = ctx.get_behavior('save');
					if (override) return override(pkg);
					return true;
				},

				"delete": function(pkg, sec, opt) {
					push(cursor_calls["delete"], [pkg, sec, opt]);
					let override = ctx.get_behavior('delete');
					if (override) return override(pkg, sec, opt);

					let p = ctx.get_data(pkg);
					if (type(p) !== 'object') {
						if (ctx.is_strict()) die(sprintf("strict mock: uci package '%s' is not mocked", pkg));
						return false;
					}
					p = { ...p };
					if (opt !== null) {
						if (type(p[sec]) !== 'object') return false;
						p[sec] = { ...p[sec] };
						delete p[sec][opt];
					} else {
						delete p[sec];
					}
					ctx.set_data(pkg, p);
					return true;
				}
			};
		};

		return proxy;
	}
};
