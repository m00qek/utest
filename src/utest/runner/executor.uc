import * as sequential from 'utest.runner.executor.sequential';
import * as parallel from 'utest.runner.executor.parallel';

export function execute_suites(files, reporter, jobs, filter, bundle_name, run_dir, src_dir, shim_paths, seed) {
	let executor = jobs > 1 ? parallel.create() : sequential.create();
	executor.execute(files, reporter, jobs, filter, bundle_name, run_dir, src_dir, shim_paths || [], seed);
};
