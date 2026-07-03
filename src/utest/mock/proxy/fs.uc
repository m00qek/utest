// Loaded via require() in ucode program mode — see proxy_base.uc for why `return` is used here.

// A path's directory prefix, with a trailing slash (except root), so a substring
// match selects only descendants and not siblings that share the name prefix.
function dir_prefix(path) {
	return (path !== "/" && substr(path, length(path) - 1) !== "/") ? path + "/" : path;
}

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

			if (substr(mode, 0, 1) === 'r') {
				if (ctx.has_data(path)) {
					let existing = ctx.get_data(path);
					return existing !== null ? make_handle(existing, null) : null;
				}
				if (ctx.is_strict()) die("strict mock: 'fs.open' called with unmocked path: " + path);
				return ctx.real_call('open', [path, mode], null);
			}

			let existing = ctx.get_data(path);
			if (ctx.is_active()) {
				let base = '';
				if (substr(mode, 0, 1) === 'a') {
					// Append starts from existing mock content. For an unmocked path,
					// overlay-read the real file (mirroring rename) so an append doesn't
					// silently drop real content. A tombstoned path (has_data but null)
					// stays empty — the mock says it was deleted.
					base = ctx.has_data(path) ? (existing ?? '')
					                          : (ctx.real_call('readfile', [path], null) ?? '');
				}
				return make_handle('', (data) => ctx.set_data(path, base + data));
			}

			return ctx.real_call('open', [path, mode], null);
		};

		proxy.popen = function(cmd, mode) {
			ctx.record_call('popen', [cmd, mode]);
			let f = ctx.get_behavior('popen');
			if (f) return f(cmd, mode);

			mode ??= 'r';

			if (substr(mode, 0, 1) === 'r') {
				if (ctx.has('commands', cmd)) {
					let existing = ctx.get('commands', cmd);
					return existing !== null ? make_handle(existing, null) : null;
				}
				if (ctx.is_strict()) die("strict mock: 'fs.popen' called with unmocked command: " + cmd);
				return ctx.real_call('popen', [cmd, mode], null);
			}

			if (ctx.is_active())
				return make_handle('', (data) => ctx.set('commands', cmd, data));

			return ctx.real_call('popen', [cmd, mode], null);
		};

		proxy.readfile = function(path) {
			ctx.record_call('readfile', [path]);
			let f = ctx.get_behavior('readfile');
			if (f) return f(path);
			if (ctx.has_data(path)) return ctx.get_data(path);
			if (ctx.is_strict())
				die("strict mock: 'fs.readfile' called with unmocked path: " + path);
			return ctx.real_call('readfile', [path], null);
		};

		proxy.writefile = function(path, data) {
			ctx.record_call('writefile', [path, data]);
			let f = ctx.get_behavior('writefile');
			if (f) return f(path, data);
			if (ctx.is_active()) {
				ctx.set_data(path, data);
				return length(data);
			}
			return ctx.real_call('writefile', [path, data], null);
		};

		proxy.access = function(path, mode) {
			ctx.record_call('access', [path, mode]);
			let f = ctx.get_behavior('access');
			if (f) return f(path, mode);
			if (ctx.has_data(path)) return ctx.get_data(path) !== null;
			let prefix = dir_prefix(path);
			for (let vp in ctx.get_all_data_keys()) {
				if (ctx.get_data(vp) !== null && substr(vp, 0, length(prefix)) === prefix) return true;
			}
			if (ctx.is_strict())
				die("strict mock: 'fs.access' called with unmocked path: " + path);
			return ctx.real_call('access', [path, mode], null);
		};

		proxy.stat = function(path) {
			ctx.record_call('stat', [path]);
			let f = ctx.get_behavior('stat');
			if (f) return f(path);
			if (ctx.has_data(path)) {
				let v = ctx.get_data(path);
				if (v === null) return null;
				let size = (type(v) === 'string') ? length(v) : 0;
				return { size, mtime: 0, type: 'regular' };
			}
			let prefix = dir_prefix(path);
			for (let vp in ctx.get_all_data_keys()) {
				if (ctx.get_data(vp) !== null && substr(vp, 0, length(prefix)) === prefix)
					return { size: 0, mtime: 0, type: 'directory' };
			}
			if (ctx.is_strict())
				die("strict mock: 'fs.stat' called with unmocked path: " + path);
			return ctx.real_call('stat', [path], null);
		};

		proxy.rename = function(old_path, new_path) {
			ctx.record_call('rename', [old_path, new_path]);
			let f = ctx.get_behavior('rename');
			if (f) return f(old_path, new_path);
			if (ctx.has_data(old_path)) {
				let v = ctx.get_data(old_path);
				if (v === null) return false;       // deleted in mock
				if (old_path === new_path) return true;  // rename onto self is a no-op
				ctx.set_data(new_path, v);
				ctx.set_data(old_path, null);
				return true;
			}
			if (ctx.is_strict())
				die("strict mock: 'fs.rename' called with unmocked path: " + old_path);
			// Sealed like writes: a destructive op never mutates the real filesystem
			// while a mock is active. Overlay-read the real content of an unmocked
			// source (null for a nonexistent path or a directory - nothing to move,
			// so report failure) and move it *within the mock*, leaving the real
			// file intact.
			if (ctx.is_active()) {
				let v = ctx.real_call('readfile', [old_path], null);
				if (v === null) return false;
				if (old_path === new_path) return true;
				ctx.set_data(new_path, v);
				ctx.set_data(old_path, null);
				return true;
			}
			return ctx.real_call('rename', [old_path, new_path], false);
		};

		proxy.unlink = function(path) {
			ctx.record_call('unlink', [path]);
			let f = ctx.get_behavior('unlink');
			if (f) return f(path);
			if (ctx.has_data(path)) {
				if (ctx.get_data(path) === null) return false;  // already deleted in mock
				ctx.set_data(path, null);
				return true;
			}
			if (ctx.is_strict())
				die("strict mock: 'fs.unlink' called with unmocked path: " + path);
			// Sealed like writes: never delete on the real filesystem while a mock is
			// active. Probe reality like rename: a path that exists nowhere — or a
			// directory (readfile returns null for both) — cannot be unlinked, so
			// report failure and exercise SUT branches on unlink failure. Otherwise
			// tombstone the path so subsequent reads/access/stat see it gone; the real
			// file is left intact.
			if (ctx.is_active()) {
				if (ctx.real_call('readfile', [path], null) === null) return false;
				ctx.set_data(path, null);
				return true;
			}
			return ctx.real_call('unlink', [path], false);
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
			let real_entries = ctx.is_strict() ? null : ctx.real_call('lsdir', [path], null);
			let virtual_paths = ctx.get_all_data_keys();
			let entries = {};
			if (type(real_entries) === "array") {
				for (let e in real_entries) entries[e] = true;
			}
			let prefix = dir_prefix(path);
			let saw_descendant = false;
			for (let vp in virtual_paths) {
				if (substr(vp, 0, length(prefix)) !== prefix) continue;
				let relative = substr(vp, length(prefix));
				let parts = split(relative, "/");
				if (length(parts) === 0 || parts[0] === "") continue;
				// Any path placed under this prefix — even a since-tombstoned one —
				// means the directory is known to the mock.
				saw_descendant = true;
				// A deleted (null) direct child removes the entry even if it exists on
				// the real filesystem; a non-null path (direct or nested) adds its
				// top-level component.
				if (length(parts) === 1 && ctx.get_data(vp) === null)
					delete entries[parts[0]];
				else if (ctx.get_data(vp) !== null)
					entries[parts[0]] = true;
			}
			let result = keys(entries);
			if (length(result) > 0) return result;
			// The directory is empty. Distinguish "exists but empty" from ENOENT:
			// real fs returns [] for the former, null for the latter. It exists if the
			// real dir was listable or the mock has any path under it.
			let dir_exists = (type(real_entries) === "array") || saw_descendant;
			// Under strict, real results are suppressed, so an unknown directory (no
			// mock paths under it) is a typo like an unmocked readfile — die loudly
			// rather than silently return null. A known-but-emptied dir still returns [].
			if (ctx.is_strict() && !dir_exists)
				die("strict mock: 'fs.lsdir' called with unmocked path: " + path);
			return dir_exists ? [] : null;
		};

		proxy.glob = function(pattern) {
			ctx.record_call('glob', [pattern]);
			let f = ctx.get_behavior('glob');
			if (f) return f(pattern);
			// Unlike lsdir/readfile, glob is a search, not a lookup of a named resource:
			// matching nothing is a valid result, not a typo, so strict suppresses the
			// real filesystem (returning only virtual matches) but never dies.
			let real_files = ctx.is_strict() ? null : ctx.real_call('glob', [pattern], null);
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
			p = replace(p, /\/\*\*\//g, "\x02");  // /**/ → zero-or-more path components
			p = replace(p, /\*\*/g, "\x01");
			p = replace(p, /\*/g,  "[^/]*");
			p = replace(p, /\?/g,  "[^/]");
			p = replace(p, /\x01/g, ".*");
			p = replace(p, /\x02/g, "(/.*)?/");
			let re_pattern = "^" + p + "$";
			let re = regexp(re_pattern);
			for (let vp in virtual_paths) {
				if (!match(vp, re)) continue;
				// A matching path mocked as deleted (null) must be removed even when the
				// real glob returned it, not merely skipped.
				if (ctx.get_data(vp) === null) delete files[vp];
				else files[vp] = true;
			}
			return length(keys(files)) > 0 ? keys(files) : null;
		};

		return proxy;
	}
};
