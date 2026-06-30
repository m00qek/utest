import * as util from 'utest.util';
import * as fs from 'fs';

export const q = util.q;

export const dispatch = function(msg, reporter) {
	if (msg.event === "SUITE_START")      reporter.suite_start(msg);
	else if (msg.event === "TEST_RESULT") reporter.test_result(msg);
	else if (msg.event === "SUITE_END")   reporter.suite_end(msg);
	else if (msg.event === "FATAL")       reporter.fatal(msg);
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
	execute: function(files, reporter, jobs, filter, bundle_name, run_dir, src_dir, shim_paths, seed, timeout, lib_paths, mocks, prop_seed) {
		// Generate the seed here so the same value drives both file-order shuffle
		// and each worker's test-order shuffle.  util.shuffle generates its own
		// seed internally when passed null but never surfaces it, so a null seed
		// forwarded to workers makes every run unreproducible.
		if (seed === null) {
			let t = clock();
			seed = t[0] * 1000000000 + t[1];
		}
		return this.run(util.shuffle(files, seed), reporter, jobs, filter, bundle_name, run_dir, src_dir, shim_paths || [], seed, timeout || 60, lib_paths || [], mocks || [], prop_seed);
	},

	// Given the terminal state of a finished or killed worker, return the FATAL
	// error string to report, or null when the worker completed cleanly (or
	// already emitted its own FATAL).  Shared by both executors so the -j1 and
	// -jN paths cannot drift in their wording or suppression rule.
	//   st = { received_any, suite_ended, fatal_received, timed_out, timeout, captured }
	terminal_fatal: function(st) {
		if (!st.received_any)
			return st.timed_out
				? sprintf("worker timed out after %ds", st.timeout)
				: length(st.captured) > 0
					? "worker produced no test output. Captured:\n" + st.captured
					: "worker produced no output (possible spawn failure)";
		if (!st.suite_ended && !st.fatal_received)
			return st.timed_out
				? sprintf("worker timed out after %ds (partial results above)", st.timeout)
				: "worker terminated before completing (partial results above)";
		return null;
	}
};
