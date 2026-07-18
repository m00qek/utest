import * as worker_runner from 'utest.runner.worker.runner';
import * as worker_reporter from 'utest.runner.worker.reporter';
import * as property from 'utest.property';
import * as fs from 'fs';

const args = json(ARGV[0]);
const test_file = args.file;
// Hand the property engine its run-scoped config explicitly rather than letting
// it read worker globals; must run before test files load (prop() derives its
// persist_id at declaration time).
property.configure({
	test_file: fs.realpath(test_file) || test_file,
	prop_seed: args.prop_seed ?? null
});
const test_filter = args.filter;
const test_seed = args.seed;
const bundle_name = args.bundle || "Default";

if (!test_file) {
	print("Usage: ucode bootstrap.uc '{\"file\":\"...\",\"filter\":\"...\",\"bundle\":\"...\"}'\n");
	exit(1);
}

const reporter = worker_reporter.create(test_file, bundle_name);

const _real_require = require;
const _mocked = {};
for (let name in (args.mocks || [])) _mocked[name] = true;
global.require = function(name) {
	let reg = global.__utest_registries && global.__utest_registries[name];
	let proxy = reg && reg.global.proxy;
	if (proxy) return proxy;
	if (_mocked[name]) {
		try { return _real_require('real_' + name); } catch(e) {
			warn(sprintf("[utest] warning: mock configured for '%s' but no shim found (real_%s.uc missing from search path); falling back to real module\n", name, name));
		}
	}
	return _real_require(name);
};

try {
	let test_dir = replace(test_file, /\/[^\/]+$/, "");
	if (test_dir !== test_file) {
		let real_dir = fs.realpath(test_dir) || test_dir;
		// REQUIRE_SEARCH_PATH entries are glob templates (the '*' is replaced
		// with the module name); a bare directory never matches, so a test could
		// not require() a helper sitting next to it. Append (not unshift) the
		// templates: the test's own directory must rank below every fixed tier
		// (shims, framework source, lib_paths) — the same tier as the project
		// root — so a coincidentally same-named sibling file (e.g. a stray
		// fs.uc) cannot silently outrank the shim and defeat a mock.
		push(REQUIRE_SEARCH_PATH, real_dir + "/*.uc");
		push(REQUIRE_SEARCH_PATH, real_dir + "/*.so");
	}

	let test_fn = loadfile(test_file);
	if (!test_fn) die(sprintf("Could not load test file: %s", test_file));
	test_fn();
	worker_runner.run_tests(reporter, test_filter, test_seed);
} catch (e) {
	reporter.fatal(e);
	exit(1);
}
