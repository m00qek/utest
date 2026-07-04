import * as fs from 'fs';
import { parse_thrown } from 'utest.util';

// Emit one protocol event and flush immediately. On musl (every OpenWrt target)
// stdout is demoted to fully-buffered the moment it is not a tty, so an unflushed
// event sits in a ~1KB buffer until the process exits cleanly — and the parallel
// executor's SIGKILL / sequential executor's SIGTERM on timeout discard that
// buffer, losing every result after SUITE_START. Flushing per event is what makes
// "partial results above" honest and keeps -j1's live streaming line-at-a-time.
// print() writes libc's stdout; fs.stdout wraps the same FILE*, so its flush()
// drains print()'s buffer (verified on the target interpreter).
function emit(obj) {
	print(sprintf('%J', obj) + "\n");
	fs.stdout.flush();
}

export function create(suite, bundle) {
	return {
		suite_start: function(count) {
			emit({
				event: "SUITE_START",
				suite: suite,
				bundle: bundle,
				count: count
			});
		},

		suite_end: function(duration_ms) {
			emit({
				event: "SUITE_END",
				suite: suite,
				bundle: bundle,
				duration_ms: duration_ms
			});
		},

		fatal: function(msg) {
			const text = (type(msg) === 'object' && msg !== null)
				? parse_thrown(msg).message
				: sprintf('%s', msg);
			emit({
				event: "FATAL",
				suite: suite,
				bundle: bundle,
				error: text
			});
		},

		test_result: function(error, path, forced_status, index) {
			let status, msg;

			if (error !== null) {
				const p = parse_thrown(error);
				status = (p.kind === 'fail') ? "FAIL" : "ERROR";
				msg = p.message;
			} else {
				status = forced_status || "PASS";
				msg = null;
			}

			emit({
				event: "TEST_RESULT",
				suite: suite,
				bundle: bundle,
				status: status,
				error: msg,
				path: path,
				index: index
			});
		}
	};
};
