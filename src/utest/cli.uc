import { run } from 'utest.runner';
import { seed_from_clock } from 'utest.util';
import * as fs from 'fs';

const VALID_REPORTERS = /^(detailed|compact|json)$/;

// -j/-s reach us as strings (utest.sh wraps every option value with json_str);
// config values reach us as ints. int("abc") silently yields 0 — so a typo'd -j
// becomes "sequential" and a typo'd -s becomes "seed 0" with no diagnostic.
// Validate before coercing so the mistake is loud.
function require_uint(v, label) {
	let ok = (type(v) === 'int') ? (v >= 1)
	       : (type(v) === 'string' && match(v, /^[0-9]+$/)) ? (int(v) >= 1)
	       : false;
	if (!ok) die(sprintf("Invalid %s '%s': expected a positive integer.\n", label, v));
	return int(v);
}

function require_int(v, label) {
	let ok = (type(v) === 'int') ||
	         (type(v) === 'string' && match(v, /^-?[0-9]+$/));
	if (!ok) die(sprintf("Invalid %s '%s': expected an integer.\n", label, v));
	return int(v);
}

function parse_bundles(positional, pattern) {
	let bundles = [];
	pattern = pattern || "*_test.uc";

	if (length(positional) === 0) {
		push(bundles, { name: "Default", pattern: "test/unit/" + pattern });
		return bundles;
	}

	for (let i = 0; i < length(positional); i++) {
		let arg = positional[i];
		let parts = split(arg, ":");
		let name, path;

		if (length(parts) > 2) {
			die(sprintf("Invalid bundle argument: '%s'. Expected format: [Name:]path\n", arg));
		} else if (length(parts) === 2) {
			name = parts[0];
			path = parts[1];
		} else {
			name = parts[0];
			path = parts[0];
		}

		if (!match(path, /\.uc$/)) {
			if (substr(path, length(path) - 1) !== "/")
				path = path + "/";
			path = path + pattern;
		}

		push(bundles, { name: name, pattern: path });
	}

	return bundles;
}

function load_config(path) {
	let resolved = path || "utest.config.uc";
	if (!fs.access(resolved, "r")) {
		if (path) die(sprintf("Configuration file not found: %s\n", path));
		return { path: null, data: {} };
	}
	resolved = fs.realpath(resolved);
	try {
		return { path: resolved, data: loadfile(resolved)() || {} };
	} catch (e) {
		die(sprintf("Failed to load configuration '%s': %s\n", resolved, e));
	}
}

function main() {
	let opts = json(ARGV[1]);
	let positional = slice(ARGV, 2);

	if (opts.reporter !== null && !match(opts.reporter, VALID_REPORTERS))
		die(sprintf("Invalid -r value '%s': expected one of: detailed, compact, json.\n", opts.reporter));

	let file_config = load_config(opts.config);

	// The config's reporter was previously unvalidated, so `reporter: "compakt"`
	// silently fell through to the default. Hold it to the same set as -r.
	if (file_config.data.reporter !== null && !match(file_config.data.reporter, VALID_REPORTERS))
		die(sprintf("Invalid config reporter '%s': expected one of: detailed, compact, json.\n", file_config.data.reporter));

	let lib_paths = opts.lib_paths || [];
	const config_dir = file_config.path ? replace(file_config.path, /\/[^\/]+$/, "") : null;

	// Resolve a config-relative path against the config file's directory.
	function resolve_rel(p) {
		if (!config_dir || !p || match(p, /^\//)) return p;
		return fs.realpath(config_dir + "/" + p) || config_dir + "/" + p;
	}

	for (let p in (file_config.data.lib_paths || []))
		push(lib_paths, resolve_rel(p));

	let raw_mocks = file_config.data.mocks || {};
	let mocks = {};
	for (let name in keys(raw_mocks)) {
		let entry = raw_mocks[name];
		mocks[name] = (type(entry) === 'object' && entry.proxy)
			? { ...entry, proxy: resolve_rel(entry.proxy) }
			: entry;
	}

	let config = {
		bundles:   parse_bundles(positional, file_config.data.pattern),
		jobs:      opts.jobs !== null ? require_uint(opts.jobs, "-j value")
		                             : (file_config.data.jobs !== null ? require_uint(file_config.data.jobs, "config jobs") : null),
		color:     file_config.data.color !== false,
		filter:    opts.filter   || file_config.data.filter,
		reporter:  opts.reporter || file_config.data.reporter,
		run_dir:   opts.run_dir,
		src_dir:   opts.src_dir,
		mocks:     mocks,
		seed:      opts.seed !== null ? require_int(opts.seed, "-s value") : seed_from_clock(),
		prop_seed: opts.seed !== null ? require_int(opts.seed, "-s value") : null,
		timeout:   int(file_config.data.timeout || 60),
		lib_paths: lib_paths
	};

	exit(run(config) ? 0 : 1);
}

main();
