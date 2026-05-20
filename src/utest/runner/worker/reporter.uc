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
				// die(msg) throws a plain string → FAIL (assertion failure).
				// Runtime interpreter exceptions (null dereference, wrong type, …)
				// throw a typed object. If type is "Error" it is still treated as
				// FAIL; any other type (e.g. ucode's runtime TypeError) → ERROR.
				if (type(error) == 'object' && error.type) {
					status = (error.type == "Error" ? "FAIL" : "ERROR");
					msg = error.message;
				} else {
					status = "FAIL";
					msg = sprintf('%s', error);
				}
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
