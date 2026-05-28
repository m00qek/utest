import * as util from 'utest.util';
import * as fs from 'fs';

export const q = util.q;

export const dispatch = function(msg, reporter) {
	if (msg.event == "SUITE_START")      reporter.suite_start(msg);
	else if (msg.event == "TEST_RESULT") reporter.test_result(msg);
	else if (msg.event == "SUITE_END")   reporter.suite_end(msg);
	else if (msg.event == "FATAL")       reporter.fatal(msg);
};

// Returns { flags, worker_path } for spawning a worker process.
// shim_paths are prepended so they shadow the base paths in ucode's search order.
// lib_paths are appended to extend the search without shadowing framework modules.
export const build_l_flags = function(src_dir, shim_paths, lib_paths) {
	const root_path = fs.realpath(".");
	const worker_path = src_dir + "/utest/runner/worker";
	let flags = sprintf("-L %s -L %s -L %s", q(src_dir), q(root_path), q(worker_path));
	for (let p in (lib_paths || [])) flags = sprintf("%s -L %s", flags, q(p));
	for (let p in shim_paths) flags = sprintf("-L %s %s", q(p), flags);
	return { flags, worker_path };
};

export const ExecutorBase = {
	execute: function(files, reporter, jobs, filter, bundle_name, run_dir, src_dir, shim_paths, seed, timeout, lib_paths, mocks) {
		return this.run(util.shuffle(files, seed), reporter, jobs, filter, bundle_name, run_dir, src_dir, shim_paths || [], seed, timeout || 60, lib_paths || [], mocks || []);
	}
};
