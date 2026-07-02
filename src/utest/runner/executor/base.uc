import * as util from 'utest.util';
import * as fs from 'fs';

export const q = util.q;

export const dispatch = function(msg, reporter) {
	if (msg.event === "SUITE_START")      reporter.suite_start(msg);
	else if (msg.event === "TEST_RESULT") reporter.test_result(msg);
	else if (msg.event === "SUITE_END")   reporter.suite_end(msg);
	else if (msg.event === "FATAL")       reporter.fatal(msg);
};

// Per-worker decoder for the newline-delimited JSON event stream a worker emits.
// feed() classifies one complete line: protocol events (SUITE_START/TEST_RESULT/
// SUITE_END/FATAL) are dispatched to the reporter and update the flags; anything
// else — non-JSON diagnostics, or valid JSON that is not an event object (e.g. a
// test that printed a bare number/string/array, whose .event access would crash
// the runner) — is echoed to stderr and captured for the terminal FATAL message.
// capture_raw() records unparsed trailing output (a partial, non-newline-
// terminated line left behind by a crash) as diagnostics without ever treating
// it as a protocol event.  Both executors decode through one instance so the
// classification and capture policy cannot drift.
export const make_stream = function(reporter) {
	return {
		received_any: false,
		suite_ended: false,
		fatal_received: false,
		captured: [],
		feed: function(line) {
			let msg;
			try { msg = json(line); } catch (e) {
				warn(rtrim(line) + "\n");
				push(this.captured, rtrim(line));
				return;
			}
			if (type(msg) !== "object") {
				warn(rtrim(line) + "\n");
				push(this.captured, rtrim(line));
				return;
			}
			if (msg.event === "SUITE_END") this.suite_ended = true;
			if (msg.event === "FATAL") this.fatal_received = true;
			dispatch(msg, reporter);
			this.received_any = true;
		},
		capture_raw: function(text) {
			let t = rtrim(text);
			if (length(t)) push(this.captured, t);
		},
		// Merge the protocol flags and capture buffer with the caller's timeout
		// info into the shape terminal_fatal() expects.
		terminal: function(timed_out, timeout) {
			return {
				received_any: this.received_any,
				suite_ended: this.suite_ended,
				fatal_received: this.fatal_received,
				timed_out, timeout,
				captured: join("\n", this.captured)
			};
		}
	};
};

// The worker CLI argument: the per-suite job description a worker reads from its
// ARGV.  Built identically by both executors.
export const worker_arg = function(file, ctx) {
	return sprintf('%J', { file, filter: ctx.filter || null, bundle: ctx.bundle,
		seed: ctx.seed, prop_seed: ctx.prop_seed, mocks: ctx.mocks });
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
	execute: function(ctx) {
		// Generate the seed here so the same value drives both file-order shuffle
		// and each worker's test-order shuffle.  util.shuffle generates its own
		// seed internally when passed null but never surfaces it, so a null seed
		// forwarded to workers makes every run unreproducible.
		let seed = ctx.seed;
		if (seed === null) {
			let t = clock();
			seed = t[0] * 1000000000 + t[1];
		}
		return this.run({ ...ctx, seed, files: util.shuffle(ctx.files, seed) });
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
