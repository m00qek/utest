// Loaded via require() in ucode program mode — see proxy_base.uc for why `return` is used here.
return {
	create: function(name, real, ctx) {
		let proxy = ctx.base();

		proxy.readfile = function(path) {
			let f = ctx.get_behavior('readfile');
			if (f) return f(path);
			let v = ctx.get_data(path);
			if (v != null) return v;
			if (ctx.is_strict())
				die("strict mock: 'fs.readfile' called with unmocked path: " + path);
			return real.readfile(path);
		};

		proxy.writefile = function(path, data) {
			let f = ctx.get_behavior('writefile');
			if (f) return f(path, data);
			if (ctx.is_active()) {
				ctx.set_data(path, data);
				return length(data);
			}
			return real.writefile(path, data);
		};

		proxy.access = function(path, mode) {
			let f = ctx.get_behavior('access');
			if (f) return f(path, mode);
			if (ctx.get_data(path) != null) return true;
			if (ctx.is_strict())
				die("strict mock: 'fs.access' called with unmocked path: " + path);
			return real ? real.access(path, mode) : null;
		};

		proxy.stat = function(path) {
			let f = ctx.get_behavior('stat');
			if (f) return f(path);
			let v = ctx.get_data(path);
			if (v != null) {
				let size = (type(v) == 'string') ? length(v) : 0;
				return { size, mtime: 0, type: 'regular' };
			}
			if (ctx.is_strict())
				die("strict mock: 'fs.stat' called with unmocked path: " + path);
			return real ? real.stat(path) : null;
		};

		proxy.rename = function(old_path, new_path) {
			let f = ctx.get_behavior('rename');
			if (f) return f(old_path, new_path);
			let v = ctx.get_data(old_path);
			if (v != null) {
				ctx.set_data(new_path, v);
				ctx.set_data(old_path, null);
				return true;
			}
			if (ctx.is_strict())
				die("strict mock: 'fs.rename' called with unmocked path: " + old_path);
			return real ? real.rename(old_path, new_path) : false;
		};

		proxy.unlink = function(path) {
			let f = ctx.get_behavior('unlink');
			if (f) return f(path);
			let v = ctx.get_data(path);
			if (v != null) {
				ctx.set_data(path, null);
				return true;
			}
			if (ctx.is_strict())
				die("strict mock: 'fs.unlink' called with unmocked path: " + path);
			return real ? real.unlink(path) : false;
		};

		proxy.mkdir = function(path, mode) {
			let f = ctx.get_behavior('mkdir');
			if (f) return f(path, mode);
			return true;
		};

		proxy.chmod = function(path, mode) {
			let f = ctx.get_behavior('chmod');
			if (f) return f(path, mode);
			return true;
		};

		proxy.error = function() {
			let f = ctx.get_behavior('error');
			if (f) return f();
			return null;
		};

		proxy.lsdir = function(path) {
			let f = ctx.get_behavior('lsdir');
			if (f) return f(path);
			let real_entries = ctx.is_strict() ? null : real.lsdir(path);
			let virtual_paths = ctx.get_all_data_keys();
			let entries = {};
			if (type(real_entries) == "array") {
				for (let e in real_entries) entries[e] = true;
			}
			let prefix = path;
			if (path != "/" && substr(prefix, length(prefix) - 1) != "/") prefix += "/";
			for (let vp in virtual_paths) {
				if (ctx.get_data(vp) == null) continue;
				if (substr(vp, 0, length(prefix)) == prefix) {
					let relative = substr(vp, length(prefix));
					let parts = split(relative, "/");
					if (length(parts) > 0 && parts[0] != "") {
						entries[parts[0]] = true;
					}
				}
			}
			let result = keys(entries);
			return length(result) > 0 ? result : null;
		};

		proxy.glob = function(pattern) {
			let f = ctx.get_behavior('glob');
			if (f) return f(pattern);
			let real_files = ctx.is_strict() ? null : real.glob(pattern);
			let virtual_paths = ctx.get_all_data_keys();
			let files = {};
			if (type(real_files) == "array") {
				for (let item in real_files) files[item] = true;
			}
			// Only * is translated; ? and ** are not supported in virtual path matching.
			let re_pattern = "^" + replace(replace(pattern, /\./g, "\\."), /\*/g, "[^/]*") + "$";
			let re = regexp(re_pattern);
			for (let vp in virtual_paths) {
				if (ctx.get_data(vp) == null) continue;
				if (match(vp, re)) files[vp] = true;
			}
			return length(keys(files)) > 0 ? keys(files) : null;
		};

		return proxy;
	}
};
