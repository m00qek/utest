import * as worker_runner from 'utest.runner.worker.runner';
import * as worker_reporter from 'utest.runner.worker.reporter';
import { root } from 'utest.runner.worker.registry';
import * as fs from 'fs';

const args = json(ARGV[0]);
const test_file = args.file;
root.test_file = test_file;
root.prop_seed  = args.prop_seed ?? null;
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
		try { return _real_require('real_' + name); } catch(e) {}
	}
	return _real_require(name);
};

try {
	let test_dir = replace(test_file, /\/[^\/]+$/, "");
	if (test_dir !== test_file) {
		let real_dir = fs.realpath(test_dir) || test_dir;
		unshift(REQUIRE_SEARCH_PATH, real_dir);
	}

	let test_fn = loadfile(test_file);
	if (!test_fn) die(sprintf("Could not load test file: %s", test_file));
	test_fn();
	worker_runner.run_tests(reporter, test_filter, test_seed);
} catch (e) {
	reporter.fatal(e);
	exit(1);
}
