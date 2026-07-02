import { find_files } from 'utest.runner.discovery';
import { execute_suites } from 'utest.runner.executor';
import { create_reporter } from 'utest.runner.reporter';
import * as MockManager from 'utest.mock.manager';

export function run(options) {
	let jobs = int(options.jobs || 1);
	let color = !!options.color;
	let test_filter = options.filter;
	let reporter_type = options.reporter;

	// 1. Test Discovery
	let all_files = [];
	let bundle_work = [];

	for (let i = 0; i < length(options.bundles); i++) {
		let b = options.bundles[i];
		let files = find_files(b.pattern);
		if (length(files) > 0) {
			push(bundle_work, { name: b.name, files: files });
			for (let f in files) push(all_files, f);
		} else {
			warn(sprintf("[utest] warning: bundle '%s' matched no files for pattern '%s'\n",
				b.name, b.pattern));
		}
	}

	if (!length(bundle_work)) {
		die("No test files found for provided bundles.\n");
	}

	// Set up shims for modules listed in config.mocks.
	options = MockManager.setup(options);

	let reporter = create_reporter(reporter_type, color, all_files, options.seed);

	// Run-wide context threaded to the executor. Defaults are applied once here so
	// the executor layers can read the fields directly without re-defaulting.
	let run_ctx = {
		reporter:   reporter,
		jobs:       jobs,
		filter:     test_filter,
		run_dir:    options.run_dir,
		src_dir:    options.src_dir,
		shim_paths: options.shim_paths || [],
		seed:       options.seed,
		timeout:    options.timeout || 60,
		lib_paths:  options.lib_paths || [],
		mocks:      keys(options.mocks || {}),
		prop_seed:  options.prop_seed
	};

	// 2. Execution Loop
	for (let i = 0; i < length(bundle_work); i++) {
		let b = bundle_work[i];
		reporter.bundle_start(b.name);
		execute_suites({ ...run_ctx, files: b.files, bundle: b.name });
		reporter.bundle_end(b.name);
	}

	reporter.summary();

	return (reporter.stats.failed === 0 && reporter.stats.errors === 0 && reporter.stats.fatals === 0);
};
