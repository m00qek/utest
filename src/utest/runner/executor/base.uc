import * as util from 'utest.util';
import * as fs from 'fs';

export const q = util.q;

const dispatch = function(msg, reporter) {
	if (msg.event === "SUITE_START")      reporter.suite_start(msg);
	else if (msg.event === "TEST_RESULT") reporter.test_result(msg);
	else if (msg.event === "SUITE_END")   reporter.suite_end(msg);
	else if (msg.event === "FATAL")       reporter.fatal(msg);
};

// The set of TEST_RESULT statuses the reporters know how to tally (reporter/
// base.uc keys stats off these). A result with any other status would render as
// an error but count as nothing, so treat it as malformed rather than dispatch.
const KNOWN_STATUS = { PASS: true, FAIL: true, ERROR: true, SKIP: true, IGNORE: true };

// A line is a protocol event only if it is an object with a recognized `event`
// AND every field the reporters dereference for it. Every event carries a `suite`
// string (reporter/base.uc keys per-suite stats on it). A TEST_RESULT additionally
// carries a known `status` and a non-empty `path` array whose every element is an
// object with a string `name` — the detailed reporter reads the leaf's `name` and
// compact reads each element's `id`/`name`, so a scalar element (e.g. `[1]`) would
// raise an uncaught reference error mid-dispatch and, in parallel mode, abort the
// whole run from inside the exit callback. The stream is in-band — a test's own
// stdout shares it — so a well-typed but malformed line (e.g. `{"event":
// "TEST_RESULT","status":"PASS","path":[1]}` printed by a test) must be treated as
// diagnostics, never dispatched. Fully-formed forgeries are an accepted limitation
// of an in-band protocol and out of scope here.
function is_event(msg) {
	if (type(msg) !== "object" || type(msg.suite) !== "string") return false;
	let e = msg.event;
	if (e === "SUITE_START" || e === "SUITE_END" || e === "FATAL") return true;
	if (e === "TEST_RESULT") {
		if (!KNOWN_STATUS[msg.status]) return false;
		if (type(msg.path) !== "array" || length(msg.path) === 0) return false;
		for (let p in msg.path)
			if (type(p) !== "object" || type(p.name) !== "string") return false;
		return true;
	}
	return false;
}

// Per-worker decoder for the newline-delimited JSON event stream a worker emits.
// feed() classifies one complete line: well-formed protocol events (see is_event)
// are dispatched to the reporter and update the flags; anything else — non-JSON
// diagnostics, valid JSON that is not an event object (e.g. a test that printed a
// bare number/string/array), or a malformed event missing required fields — is
// echoed to stderr and captured for the terminal FATAL message, never dispatched.
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
			if (!is_event(msg)) {
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
		if (seed === null) seed = util.seed_from_clock();
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
