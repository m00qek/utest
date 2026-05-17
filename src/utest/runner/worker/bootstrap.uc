import * as worker_runner from 'utest.runner.worker.runner';
import * as worker_reporter from 'utest.runner.worker.reporter';
import * as fs from 'fs';

const args = json(ARGV[0]);
const test_file = args.file;
const test_filter = args.filter;
const test_seed = args.seed;
const bundle_name = args.bundle || "Default";

if (!test_file) {
	print("Usage: ucode bootstrap.uc '{\"file\":\"...\",\"filter\":\"...\",\"bundle\":\"...\"}'\n");
	exit(1);
}

const reporter = worker_reporter.create(test_file, bundle_name);

try {
	let test_dir = replace(test_file, /\/[^\/]+$/, "");
	if (test_dir != test_file) {
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
