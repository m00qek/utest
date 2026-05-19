import { run } from 'utest.runner';
import { q } from 'utest.util';
import * as fs from 'fs';

function parse_args(argv) {
	let args = {
		flags: {},
		positional: []
	};

	const aliases = {
		'h': 'help',
		'r': 'reporter',
		'p': 'pattern',
		'j': 'jobs',
		'f': 'filter',
		'c': 'config'
	};

	// Flags that require an argument
	const expects_value = {
		'reporter': true,
		'pattern': true,
		'jobs': true,
		'filter': true,
		'config': true,
		'run-dir': true,
		'src-dir': true,
		'seed': true,
		'timeout': true
	};

	for (let i = 0; i < length(argv); i++) {
		let arg = argv[i];
		
		if (match(arg, /^--/)) {
			let kv = match(arg, /^--([^=]+)=(.*)$/);
			let key = kv ? kv[1] : substr(arg, 2);
			let val;
			if (kv) {
				val = kv[2];
			} else {
				if (expects_value[key] && i + 1 < length(argv)) {
					val = argv[++i];
				} else {
					val = true;
				}
			}

			args.flags[key] = val;
		} 
		else if (match(arg, /^-/)) {
			let key_char = substr(arg, 1);
			let key = aliases[key_char] || key_char;
			let val;
			if (expects_value[key] && i + 1 < length(argv)) {
				val = argv[++i];
			} else {
				val = true;
			}

			args.flags[key] = val;
		}
		else {
			push(args.positional, arg);
		}
	}

	return args;
}


function parse_bundles(positional, default_pattern) {
	let bundles = [];
	let pattern = default_pattern || "*_test.uc";

	if (length(positional) == 0) {
		push(bundles, { name: "Default", pattern: "test/unit/" + pattern });
		return bundles;
	}

	for (let i = 0; i < length(positional); i++) {
		let arg = positional[i];
		let parts = split(arg, ":");
		let name, path;

		if (length(parts) > 2) {
			die(sprintf("Invalid bundle argument: '%s'. Expected format: [Name:]path\n", arg));
		} else if (length(parts) == 2) {
			name = parts[0];
			path = parts[1];
		} else {
			name = parts[0];
			path = parts[0];
		}

		// If it doesn't end in .uc, assume it's a directory/prefix and append pattern
		if (!match(path, /\.uc$/)) {
			// Ensure it ends with a slash before appending
			if (substr(path, length(path) - 1) != "/") {
				path = path + "/";
			}
			path = path + pattern;
		}

		push(bundles, { name: name, pattern: path });
	}

	return bundles;
}


function usage() {
	print("utest — A modern, non-invasive testing stack for the ucode ecosystem.\n\n");
	print("Usage:\n");
	print("  utest [options] [<bundle>...]\n\n");
	print("Options:\n");
	print("  -h, --help            Show this screen.\n");
	print("  -r, --reporter=<fmt>  Set reporter format (detailed, compact, json) [default: detailed].\n");
	print("  -p, --pattern=<glob>  Set test file pattern [default: *_test.uc].\n");
	print("  -j, --jobs=<n>        Set number of parallel jobs [default: 1].\n");
	print("  --no-color            Disable colorized output.\n");
	print("  -f, --filter=<regex>  Only run tests matching regex.\n");
	print("  -c, --config=<path>   Path to configuration file [default: utest.config.uc].\n");
	print("  --seed=<n>            Fix shuffle seed for reproducible ordering.\n");
	print("  --timeout=<s>         Worker timeout in seconds [default: 60].\n\n");
	print("Examples:\n");
	print("  utest test/unit\n");
	print("  utest \"Unit:test/unit/*.uc\" \"Integration:test/integration/*.uc\"\n");
	print("  utest --jobs=4 --config=my_setup.uc test/unit\n");
	exit(0);
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
		die("Failed to load configuration: " + e + "\n");
	}
}

function main() {
	let args = parse_args(ARGV);
	if (args.flags.help) usage();

	if (args.flags.seed != null && !match(args.flags.seed, /^\d+$/))
		die(sprintf("Invalid --seed value '%s': expected a non-negative integer.\n", args.flags.seed));

	// 1. Read config file
	let file_config = load_config(args.flags.config);

	// 2. Merge config file with CLI params (params win)
	let t = clock();
	let own_run_dir = !args.flags['run-dir'];
	let config = {
		bundles:     parse_bundles(args.positional, args.flags.pattern || file_config.data.pattern),
		jobs:        args.flags.jobs      || file_config.data.jobs,
		color:       args.flags['no-color'] ? false : (file_config.data.color !== false),
		filter:      args.flags.filter    || file_config.data.filter,
		reporter:    args.flags.reporter  || file_config.data.reporter,
		run_dir:     args.flags['run-dir'] || sprintf("/tmp/utest_%d_%d", t[0], t[1]),
		src_dir:     args.flags['src-dir'] || fs.realpath("src"),
		mocks:       file_config.data.mocks || {},
		seed:        args.flags.seed != null ? int(args.flags.seed) : int(t[1]),
		timeout:     int(args.flags.timeout || file_config.data.timeout || 60)
	};

	// 3. Run
	// When invoked via utest.sh the EXIT trap owns cleanup; when invoked directly
	// (no --run-dir flag) we own it here.
	let success = false;
	try {
		success = run(config);
	} catch (e) {
		if (own_run_dir) system("rm -rf " + q(config.run_dir));
		die(e);
	}

	if (own_run_dir) system("rm -rf " + q(config.run_dir));
	exit(success ? 0 : 1);
}

main();
