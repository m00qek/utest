import * as fs from 'fs';
import { mkdir_p } from 'utest.util';

function find_real_module(name) {
	for (let pattern in REQUIRE_SEARCH_PATH) {
		let path = replace(pattern, /\*/, name);
		if (fs.access(path, "r")) return path;
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
	fs.writefile(shim_dir + "/" + name + ".uc", join("\n", lines) + "\n");
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
			fs.writefile(shim_dir + "/" + name + ".uc", join("\n", lines) + "\n");
		}
		return;
	}
	generate_standard_shim(name, shim_dir);
	let ext = match(real_path, /\.[^.]+$/)[0];
	if (!fs.symlink(real_path, shim_dir + "/real_" + name + ext))
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
			if (!fs.symlink(abs, proxy_subdir + "/" + name + ".uc"))
				print(sprintf("[utest] warning: could not install proxy for '%s'\n", name));
		}

		setup_shim(name, shim_dir);
	}

	// proxy dir is prepended so user proxies shadow built-ins when both exist.
	const proxy_dir = config.run_dir + "/proxy";
	return { ...config, shim_paths: [proxy_dir, shim_dir] };
};
