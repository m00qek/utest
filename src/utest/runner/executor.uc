import * as sequential from 'utest.runner.executor.sequential';
import * as parallel from 'utest.runner.executor.parallel';

export function execute_suites(files, reporter, jobs, filter, bundle_name, run_dir, src_dir, shim_paths, seed, timeout, lib_paths, mocks) {
	let executor = jobs > 1 ? parallel.create() : sequential.create();
	executor.execute(files, reporter, jobs, filter, bundle_name, run_dir, src_dir, shim_paths || [], seed, timeout || 60, lib_paths || [], mocks || []);
};
