import { parse_thrown } from 'utest.util';

export function create(suite, bundle) {
	return {
		suite_start: function(count) {
			print(sprintf('%J', {
				event: "SUITE_START",
				suite: suite,
				bundle: bundle,
				count: count
			}) + "\n");
		},

		suite_end: function(duration_ms) {
			print(sprintf('%J', {
				event: "SUITE_END",
				suite: suite,
				bundle: bundle,
				duration_ms: duration_ms
			}) + "\n");
		},

		fatal: function(msg) {
			print(sprintf('%J', {
				event: "FATAL",
				suite: suite,
				bundle: bundle,
				error: sprintf('%s', msg)
			}) + "\n");
		},

		test_result: function(error, path, forced_status, index) {
			let status, msg;

			if (error != null) {
				const p = parse_thrown(error);
				status = p.is_assertion ? "FAIL" : "ERROR";
				msg = p.message;
			} else {
				status = forced_status || "PASS";
				msg = null;
			}

			print(sprintf('%J', {
				event: "TEST_RESULT",
				suite: suite,
				bundle: bundle,
				status: status,
				error: msg,
				path: path,
				index: index
			}) + "\n");
		}
	};
};
