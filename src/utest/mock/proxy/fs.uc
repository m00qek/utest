// Loaded via require() in ucode program mode — see proxy_base.uc for why `return` is used here.

// A path's directory prefix, with a trailing slash (except root), so a substring
// match selects only descendants and not siblings that share the name prefix.
function dir_prefix(path) {
	return (path !== "/" && substr(path, length(path) - 1) !== "/") ? path + "/" : path;
}

// Translate a glob(3) pattern into an anchored regex. Verified against the ucode
// interpreter (musl, openwrt/rootfs 25.12.4): '*' and '?' match within a single
// path component (never across '/'); '**' has NO globstar meaning — it is just
// two '*'; and '[...]' is a POSIX character class where a leading '!' or '^' means
// negation, '-' forms ranges (literal when leading/trailing), and a leading ']'
// is a literal member. Bracket expressions are parsed explicitly rather than
// escaped, because those members don't survive naive metacharacter escaping.
const GLOB_META = "\\.^$|+(){}]";  // regex metacharacters escaped when literal (outside a class)
function glob_to_regex(pattern) {
	let out = "^";
	let i = 0;
	const n = length(pattern);
	while (i < n) {
		const ch = substr(pattern, i, 1);
		if (ch === "*") { out += "[^/]*"; i++; continue; }
		if (ch === "?") { out += "[^/]";  i++; continue; }
		if (ch === "[") {
			let j = i + 1;
			let negated = false;
			if (j < n) {
				const marker = substr(pattern, j, 1);
				if (marker === "!" || marker === "^") { negated = true; j++; }
			}
			const body_start = j;
			// A ']' as the first member is a literal, not the terminator.
			if (j < n && substr(pattern, j, 1) === "]") j++;
			while (j < n && substr(pattern, j, 1) !== "]") j++;
			if (j >= n) {
				// No closing ']': POSIX treats the '[' as a literal character.
				out += "\\[";
				i++;
				continue;
			}
			// The parser already keeps a leading ']' (a literal member) at the front of
			// the body, and ucode's regex — like glob and POSIX — reads a leading ']'
			// as literal (backslash-escaping ']' inside a class does NOT work here, so
			// must not be attempted). Only a raw backslash needs escaping.
			let body = substr(pattern, body_start, j - body_start);
			body = replace(body, /\\/g, "\\\\");
			if (negated) {
				// A bracket expression never matches '/'. Append it to the exclusion,
				// escaping a trailing literal '-' first so it can't form a '-/' range.
				if (substr(body, length(body) - 1) === "-")
					body = substr(body, 0, length(body) - 1) + "\\-";
				out += "[^" + body + "/]";
			} else {
				out += "[" + body + "]";
			}
			i = j + 1;
			continue;
		}
		out += (index(GLOB_META, ch) >= 0) ? ("\\" + ch) : ch;
		i++;
	}
	return out + "$";
}

// A unique marker returned by stat_of() when the mock has no opinion about a path
// (neither a stored file nor a directory inferred from descendants), so the caller
// can fall through to strict-die / the real fs just like the other read ops.
const UNKNOWN = {};

// Canonicalize a path the way fs.realpath() does — collapse '.', '..' and
// redundant slashes — so realpath() returns a canonical key and matches a path
// stored under its canonical form. Purely lexical: the mock has no symlinks to
// resolve, which is consistent with how it models the filesystem.
function normalize_path(path) {
	let absolute = substr(path, 0, 1) === "/";
	let stack = [];
	for (let p in split(path, "/")) {
		if (p === "" || p === ".") continue;
		if (p === "..") {
			if (length(stack) > 0 && stack[length(stack) - 1] !== "..")
				stack = slice(stack, 0, length(stack) - 1);
			else if (!absolute)
				push(stack, "..");
			continue;
		}
		push(stack, p);
	}
	let joined = join("/", stack);
	return absolute ? "/" + joined : (length(joined) ? joined : ".");
}

// Shared file/directory metadata behind stat()/lstat()/readlink()/realpath(): a
// stored non-null value is a regular file; a path that is a strict prefix of any
// stored key is an inferred directory; a stored null is a tombstoned (deleted)
// path. Returns the stat dict, null for a deleted path, or UNKNOWN when the mock
// has never heard of the path. `type` uses the real fs vocabulary ('file' /
// 'directory'), so a SUT that switches on stat().type behaves the same as live.
function stat_of(ctx, path) {
	if (ctx.has_data(path)) {
		let v = ctx.get_data(path);
		if (v === null) return null;
		let size = (type(v) === 'string') ? length(v) : 0;
		return { size, mtime: 0, type: 'file' };
	}
	let prefix = dir_prefix(path);
	for (let vp in ctx.get_all_data_keys()) {
		if (ctx.get_data(vp) !== null && substr(vp, 0, length(prefix)) === prefix)
			return { size: 0, mtime: 0, type: 'directory' };
	}
	return UNKNOWN;
}

// The merged (real ∪ mock) directory listing shared by lsdir() and opendir().
// Returns an array of entry names (possibly empty when the directory exists but
// is empty) or null when the directory does not exist. `op` names the caller for
// the strict-mode die. In strict mode the real filesystem is suppressed.
function list_dir(ctx, op, path) {
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
		// Any path placed under this prefix — even a since-tombstoned one — means
		// the directory is known to the mock.
		saw_descendant = true;
		// A deleted (null) direct child removes the entry even if it exists on the
		// real filesystem; a non-null path (direct or nested) adds its top-level
		// component.
		if (length(parts) === 1 && ctx.get_data(vp) === null)
			delete entries[parts[0]];
		else if (ctx.get_data(vp) !== null)
			entries[parts[0]] = true;
	}
	let result = keys(entries);
	if (length(result) > 0) return result;
	// The directory is empty. Distinguish "exists but empty" from ENOENT: real fs
	// returns [] for the former, null for the latter. It exists if the real dir was
	// listable or the mock has any path under it.
	let dir_exists = (type(real_entries) === "array") || saw_descendant;
	// Under strict, real results are suppressed, so an unknown directory (no mock
	// paths under it) is a typo like an unmocked readfile — die loudly rather than
	// silently return null. A known-but-emptied dir still returns [].
	if (ctx.is_strict() && !dir_exists)
		die(sprintf("strict mock: 'fs.%s' called with unmocked path: %s", op, path));
	return dir_exists ? [] : null;
}

// A cursor over a directory listing, exposing the subset of the fs.dir resource
// the mock models: sequential read() (null past the end), tell()/seek() for the
// position, and no-op close()/error(). Real fs.dir order is filesystem-defined;
// the mock serves its merged listing in the computed order (deterministic per test).
function make_dir_handle(entries) {
	let pos = 0;
	return {
		read:  function()    { return (pos < length(entries)) ? entries[pos++] : null; },
		tell:  function()    { return pos; },
		seek:  function(off) { pos = (off ?? 0); return true; },
		close: function()    { },
		error: function()    { return null; }
	};
}

// Filesystem-mutating functions the mock does not model. Left to fall through (as
// ctx.base() does for any un-overridden function in non-strict mode), they would
// hit the REAL filesystem during an active mock — e.g. rmdir deleting a real
// directory — silently defeating the seal. Each is sealed below to record the
// call, honour a behavior: override when the test supplies one, and otherwise die
// with an actionable message rather than leak the side effect. The read-only
// family (lstat/readlink/realpath/opendir) is modeled directly below against the
// same store as stat/lsdir, so it no longer leaks to the real fs. chdir is
// included because it leaks a process-global cwd change into later tests.
const SEALED_OPS = ['rmdir', 'symlink', 'chown', 'chdir', 'mkdtemp', 'mkstemp'];
function seal_op(ctx, op) {
	return function(...args) {
		ctx.record_call(op, args);
		const override = ctx.get_behavior(op);
		if (override) return override(...args);
		die(sprintf("[utest] fs mock: fs.%s() is not implemented by the mock and would mutate the real filesystem; pass behavior: { %s: ... } to handle it", op, op));
	};
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
			let s = stat_of(ctx, path);
			if (s !== UNKNOWN) return s;
			if (ctx.is_strict())
				die("strict mock: 'fs.stat' called with unmocked path: " + path);
			return ctx.real_call('stat', [path], null);
		};

		proxy.lstat = function(path) {
			ctx.record_call('lstat', [path]);
			let f = ctx.get_behavior('lstat');
			if (f) return f(path);
			// The mock models no symlinks (fs.symlink is sealed), so a path it knows
			// is never a link — lstat is identical to stat for every mocked path.
			let s = stat_of(ctx, path);
			if (s !== UNKNOWN) return s;
			if (ctx.is_strict())
				die("strict mock: 'fs.lstat' called with unmocked path: " + path);
			return ctx.real_call('lstat', [path], null);
		};

		proxy.readlink = function(path) {
			ctx.record_call('readlink', [path]);
			let f = ctx.get_behavior('readlink');
			if (f) return f(path);
			// No symlinks in the mock: a known path is a regular file or directory, so
			// readlink reports "not a symlink" (null) exactly as the real fs does for a
			// non-link. Only a wholly unknown path falls through.
			let s = stat_of(ctx, path);
			if (s !== UNKNOWN) return null;
			if (ctx.is_strict())
				die("strict mock: 'fs.readlink' called with unmocked path: " + path);
			return ctx.real_call('readlink', [path], null);
		};

		proxy.realpath = function(path) {
			ctx.record_call('realpath', [path]);
			let f = ctx.get_behavior('realpath');
			if (f) return f(path);
			// realpath requires the path to exist; canonicalize first so a path given
			// with '.'/'..' matches its stored key, then confirm the mock knows it.
			let canon = normalize_path(path);
			let s = stat_of(ctx, canon);
			if (s === UNKNOWN) {
				if (ctx.is_strict())
					die("strict mock: 'fs.realpath' called with unmocked path: " + path);
				return ctx.real_call('realpath', [path], null);
			}
			return (s === null) ? null : canon;   // null: a tombstoned (deleted) path
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
			return list_dir(ctx, 'lsdir', path);
		};

		proxy.opendir = function(path) {
			ctx.record_call('opendir', [path]);
			let f = ctx.get_behavior('opendir');
			if (f) return f(path);
			// Serve the same merged listing as lsdir() through a cursor handle. A
			// non-array result (a file, or a nonexistent path) opens as null, exactly
			// as the real fs.opendir returns null for ENOENT / ENOTDIR.
			let entries = list_dir(ctx, 'opendir', path);
			if (type(entries) !== 'array') return null;
			return make_dir_handle(entries);
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
			// Translate the glob to an anchored regex (see glob_to_regex: glob(3)
			// semantics — '**' is not globstar, '[...]' is a real character class).
			let re = regexp(glob_to_regex(pattern));
			for (let vp in virtual_paths) {
				if (!match(vp, re)) continue;
				// A matching path mocked as deleted (null) must be removed even when the
				// real glob returned it, not merely skipped.
				if (ctx.get_data(vp) === null) delete files[vp];
				else files[vp] = true;
			}
			// Real fs.glob returns lexically sorted paths; without this, merged results
			// would list real matches first, then virtual ones in key order, so a SUT
			// that relies on conf.d/priority ordering would behave differently under mock.
			let out = keys(files);
			return length(out) > 0 ? sort(out) : null;
		};

		// Seal the filesystem-mutating functions the mock does not implement so a
		// call cannot fall through to the real fs (see seal_op / SEALED_OPS). seal_op
		// takes op as a parameter, so the per-iteration binding is captured correctly.
		for (let op in SEALED_OPS)
			proxy[op] = seal_op(ctx, op);

		return proxy;
	}
};
