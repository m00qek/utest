import * as fs from 'fs';
import { mkdir_p } from 'utest.util';

// ucode's require maps dotted module names to path separators
// (require('a.b') resolves a/b.uc), so any module name that becomes a
// filesystem path must have its dots translated to '/' and its parent
// directories created — otherwise the shim/symlink is written to a flat
// 'a.b.uc' that require() never looks for.
function module_path(name) {
	return replace(name, ".", "/");
}

// Create the parent directory of a module file so writefile/symlink succeed
// for namespaced (dotted) module names.
function ensure_parent(path) {
	let dir = replace(path, /\/[^\/]+$/, "");
	if (dir !== path && !mkdir_p(dir))
		die("[utest] error: could not create module directory: " + dir);
}

function find_real_module(name) {
	let rel = module_path(name);
	for (let pattern in REQUIRE_SEARCH_PATH) {
		let path = replace(pattern, /\*/, rel);
		// Return an absolute path: the result becomes a symlink target, and a
		// relative one (e.g. "./mylib/thing.uc" from the "./*.uc" search entry)
		// would resolve against the link's own nested directory, not the cwd.
		if (fs.access(path, "r")) return fs.realpath(path) || path;
	}
	return null;
}

// Extract the proxy path from a config.mocks entry, or null if none.
function proxy_path(raw) {
	if (type(raw) === 'object') return raw.proxy || null;
	return null;
}

function generate_standard_shim(name, shim_dir) {
	let real;
	try { real = require(name); } catch(e) { real = null; }
	if (!real) {
		warn(sprintf("[utest] warning: could not inspect '%s'; the shim will have no interceptable functions\n", name));
	}
	let lines = [
		sprintf("import * as _real from 'real_%s';", name),
		"import { __internal__ } from 'utest.mock.engine';"
	];
	for (let fn_name in (real ? keys(real) : [])) {
		if (type(real[fn_name]) === 'function') {
			push(lines, sprintf(
				"export const %s = function(...args) { let p = __internal__.get_proxy_global('%s'); return p ? p.%s(...args) : _real.%s(...args); };",
				fn_name, name, fn_name, fn_name
			));
		} else {
			push(lines, sprintf("export const %s = _real.%s;", fn_name, fn_name));
		}
	}
	let shim_path = shim_dir + "/" + module_path(name) + ".uc";
	ensure_parent(shim_path);
	fs.writefile(shim_path, join("\n", lines) + "\n");
}

// Install a shim for one module.
// If the real module is absent but the built-in proxy declares an `api` list,
// a stub shim is generated from that list so the module can still be mocked.
function setup_shim(name, shim_dir) {
	let real_path = find_real_module(name);
	if (!real_path) {
		let api = null;
		try {
			let proxy = require('utest.mock.proxy.' + name);
			if (proxy && type(proxy.api) === 'array') api = proxy.api;
		} catch(e) {}
		if (api) {
			let lines = ["import { __internal__ } from 'utest.mock.engine';"];
			for (let fn_name in api) {
				push(lines, sprintf(
					"export const %s = function(...args) { let p = __internal__.get_proxy_global('%s'); if (p) return p.%s(...args); };",
					fn_name, name, fn_name
				));
			}
			let stub_path = shim_dir + "/" + module_path(name) + ".uc";
			ensure_parent(stub_path);
			fs.writefile(stub_path, join("\n", lines) + "\n");
		} else {
			warn(sprintf("[utest] warning: no shim created for '%s': module not found on disk and no proxy api list — mock will have no effect\n", name));
		}
		return;
	}
	generate_standard_shim(name, shim_dir);
	let ext_m = match(real_path, /\.[^.]+$/);
	let ext = ext_m ? ext_m[0] : '';
	// The shim imports 'real_<name>'; require resolves that with dots→'/', so the
	// symlink must live at module_path("real_" + name) + ext to be found.
	let real_link = shim_dir + "/" + module_path("real_" + name) + ext;
	ensure_parent(real_link);
	if (!fs.symlink(real_path, real_link))
		die(sprintf("[utest] error: could not link real module for '%s'\n", name));
}

// config.mocks: map of module name → null | { proxy: 'path/to/proxy.uc' }
//   null               → shim the module using its built-in or generic proxy
//   { proxy: 'path' }  → shim with a custom proxy factory; path resolved by cli.uc
export const setup = function(config) {
	const shim_dir = config.run_dir + "/shims";
	// proxy_dir mirrors the utest.mock.proxy.* search structure so that
	// require('utest.mock.proxy.<name>') finds user proxies before built-ins.
	const proxy_subdir = config.run_dir + "/proxy/utest/mock/proxy";
	if (!mkdir_p(shim_dir))
		die("[utest] error: could not create shim directory: " + shim_dir);
	if (!mkdir_p(proxy_subdir))
		die("[utest] error: could not create proxy directory: " + proxy_subdir);

	for (let name in keys(config.mocks || {})) {
		let ppath = proxy_path(config.mocks[name]);

		// Install user proxy: symlinked so require('utest.mock.proxy.<name>') finds it.
		if (ppath) {
			let abs = fs.realpath(ppath) || ppath;
			let proxy_link = proxy_subdir + "/" + module_path(name) + ".uc";
			ensure_parent(proxy_link);
			if (!fs.symlink(abs, proxy_link))
				die(sprintf("[utest] error: could not install proxy for '%s': symlink '%s' -> '%s' failed\n", name, abs, proxy_link));
		}

		setup_shim(name, shim_dir);
	}

	// proxy dir is prepended so user proxies shadow built-ins when both exist.
	const proxy_dir = config.run_dir + "/proxy";
	return { ...config, shim_paths: [proxy_dir, shim_dir] };
};
