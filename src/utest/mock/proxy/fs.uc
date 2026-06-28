// Loaded via require() in ucode program mode — see proxy_base.uc for why `return` is used here.
return {
	channels: ['commands'],
	create: function(name, real, ctx) {
		let proxy = ctx.base();

		// Build a file handle backed by a string.  on_close(written), if provided,
		// is called with everything that was write()n when close() is called.
		function make_handle(content, on_close) {
			let remaining = content ?? '';
			let written = '';
			return {
				read: function(n) {
					if (n === 'all') { let r = remaining; remaining = ''; return r; }
					if (n === 'line') {
						let i = index(remaining, '\n');
						if (i < 0) { let r = remaining; remaining = ''; return length(r) ? r : null; }
						let r = substr(remaining, 0, i + 1);
						remaining = substr(remaining, i + 1);
						return r;
					}
					let cnt = +n;
					let r = substr(remaining, 0, cnt);
					remaining = substr(remaining, cnt);
					return r;
				},
				write: function(data) { written += data; return length(data); },
				close: function() { if (on_close) on_close(written); },
				error: function() { return null; }
			};
		}

		proxy.open = function(path, mode) {
			ctx.record_call('open', [path, mode]);
			let f = ctx.get_behavior('open');
			if (f) return f(path, mode);

			mode ??= 'r';
			let existing = ctx.get_data(path);

			if (substr(mode, 0, 1) === 'r') {
				if (existing !== null) return make_handle(existing, null);
				if (ctx.is_strict()) die("strict mock: 'fs.open' called with unmocked path: " + path);
				return real ? real.open(path, mode) : null;
			}

			if (ctx.is_active()) {
				let base = (substr(mode, 0, 1) === 'a') ? (existing ?? '') : '';
				return make_handle('', (data) => ctx.set_data(path, base + data));
			}

			return real ? real.open(path, mode) : null;
		};

		proxy.popen = function(cmd, mode) {
			ctx.record_call('popen', [cmd, mode]);
			let f = ctx.get_behavior('popen');
			if (f) return f(cmd, mode);

			mode ??= 'r';
			let existing = ctx.get('commands', cmd);

			if (substr(mode, 0, 1) === 'r') {
				if (existing !== null) return make_handle(existing, null);
				if (ctx.is_strict()) die("strict mock: 'fs.popen' called with unmocked command: " + cmd);
				return real ? real.popen(cmd, mode) : null;
			}

			if (ctx.is_active())
				return make_handle('', (data) => ctx.set('commands', cmd, data));

			return real ? real.popen(cmd, mode) : null;
		};

		proxy.readfile = function(path) {
			ctx.record_call('readfile', [path]);
			let f = ctx.get_behavior('readfile');
			if (f) return f(path);
			let v = ctx.get_data(path);
			if (v !== null) return v;
			if (ctx.is_strict())
				die("strict mock: 'fs.readfile' called with unmocked path: " + path);
			return real ? real.readfile(path) : null;
		};

		proxy.writefile = function(path, data) {
			ctx.record_call('writefile', [path, data]);
			let f = ctx.get_behavior('writefile');
			if (f) return f(path, data);
			if (ctx.is_active()) {
				ctx.set_data(path, data);
				return length(data);
			}
			return real ? real.writefile(path, data) : null;
		};

		proxy.access = function(path, mode) {
			ctx.record_call('access', [path, mode]);
			let f = ctx.get_behavior('access');
			if (f) return f(path, mode);
			if (ctx.get_data(path) !== null) return true;
			let prefix = (path !== "/" && substr(path, length(path) - 1) !== "/") ? path + "/" : path;
			for (let vp in ctx.get_all_data_keys()) {
				if (ctx.get_data(vp) !== null && substr(vp, 0, length(prefix)) === prefix) return true;
			}
			if (ctx.is_strict())
				die("strict mock: 'fs.access' called with unmocked path: " + path);
			return real ? real.access(path, mode) : null;
		};

		proxy.stat = function(path) {
			ctx.record_call('stat', [path]);
			let f = ctx.get_behavior('stat');
			if (f) return f(path);
			let v = ctx.get_data(path);
			if (v !== null) {
				let size = (type(v) === 'string') ? length(v) : 0;
				return { size, mtime: 0, type: 'regular' };
			}
			let prefix = (path !== "/" && substr(path, length(path) - 1) !== "/") ? path + "/" : path;
			for (let vp in ctx.get_all_data_keys()) {
				if (ctx.get_data(vp) !== null && substr(vp, 0, length(prefix)) === prefix)
					return { size: 0, mtime: 0, type: 'directory' };
			}
			if (ctx.is_strict())
				die("strict mock: 'fs.stat' called with unmocked path: " + path);
			return real ? real.stat(path) : null;
		};

		proxy.rename = function(old_path, new_path) {
			ctx.record_call('rename', [old_path, new_path]);
			let f = ctx.get_behavior('rename');
			if (f) return f(old_path, new_path);
			let v = ctx.get_data(old_path);
			if (v !== null) {
				ctx.set_data(new_path, v);
				ctx.set_data(old_path, null);
				return true;
			}
			if (ctx.is_strict())
				die("strict mock: 'fs.rename' called with unmocked path: " + old_path);
			return real ? real.rename(old_path, new_path) : false;
		};

		proxy.unlink = function(path) {
			ctx.record_call('unlink', [path]);
			let f = ctx.get_behavior('unlink');
			if (f) return f(path);
			let v = ctx.get_data(path);
			if (v !== null) {
				ctx.set_data(path, null);
				return true;
			}
			if (ctx.is_strict())
				die("strict mock: 'fs.unlink' called with unmocked path: " + path);
			return real ? real.unlink(path) : false;
		};

		proxy.mkdir = function(path, mode) {
			ctx.record_call('mkdir', [path, mode]);
			let f = ctx.get_behavior('mkdir');
			if (f) return f(path, mode);
			return true;
		};

		proxy.chmod = function(path, mode) {
			ctx.record_call('chmod', [path, mode]);
			let f = ctx.get_behavior('chmod');
			if (f) return f(path, mode);
			return true;
		};

		proxy.error = function() {
			ctx.record_call('error', []);
			let f = ctx.get_behavior('error');
			if (f) return f();
			return null;
		};

		proxy.lsdir = function(path) {
			ctx.record_call('lsdir', [path]);
			let f = ctx.get_behavior('lsdir');
			if (f) return f(path);
			let real_entries = ctx.is_strict() ? null : (real ? real.lsdir(path) : null);
			let virtual_paths = ctx.get_all_data_keys();
			let entries = {};
			if (type(real_entries) === "array") {
				for (let e in real_entries) entries[e] = true;
			}
			let prefix = path;
			if (path !== "/" && substr(prefix, length(prefix) - 1) !== "/") prefix += "/";
			for (let vp in virtual_paths) {
				if (ctx.get_data(vp) === null) continue;
				if (substr(vp, 0, length(prefix)) === prefix) {
					let relative = substr(vp, length(prefix));
					let parts = split(relative, "/");
					if (length(parts) > 0 && parts[0] !== "") {
						entries[parts[0]] = true;
					}
				}
			}
			let result = keys(entries);
			return length(result) > 0 ? result : null;
		};

		proxy.glob = function(pattern) {
			ctx.record_call('glob', [pattern]);
			let f = ctx.get_behavior('glob');
			if (f) return f(pattern);
			let real_files = ctx.is_strict() ? null : (real ? real.glob(pattern) : null);
			let virtual_paths = ctx.get_all_data_keys();
			let files = {};
			if (type(real_files) === "array") {
				for (let item in real_files) files[item] = true;
			}
			// Translate glob to regex. Escape all regex metacharacters that have
			// no glob meaning first (\\ must be first to avoid double-escaping),
			// then translate **, *, ? in that order. Character classes unsupported.
			let p = pattern;
			p = replace(p, /\\/g,  "\\\\");
			p = replace(p, /\[/g,  "\\[");
			p = replace(p, /\]/g,  "\\]");
			p = replace(p, /\+/g,  "\\+");
			p = replace(p, /\^/g,  "\\^");
			p = replace(p, /\$/g,  "\\$");
			p = replace(p, /\{/g,  "\\{");
			p = replace(p, /\}/g,  "\\}");
			p = replace(p, /\(/g,  "\\(");
			p = replace(p, /\)/g,  "\\)");
			p = replace(p, /\|/g,  "\\|");
			p = replace(p, /\./g,  "\\.");
			p = replace(p, /\*\*/g, "\x01");
			p = replace(p, /\*/g,  "[^/]*");
			p = replace(p, /\?/g,  "[^/]");
			p = replace(p, /\x01/g, ".*");
			let re_pattern = "^" + p + "$";
			let re = regexp(re_pattern);
			for (let vp in virtual_paths) {
				if (ctx.get_data(vp) === null) continue;
				if (match(vp, re)) files[vp] = true;
			}
			return length(keys(files)) > 0 ? keys(files) : null;
		};

		return proxy;
	}
};
