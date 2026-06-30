import { root } from 'utest.runner.worker.registry';
import * as util from 'utest.util';

function flatten(group, context, list) {
	let new_context = {
		path: [ ...context.path, { id: group.id, name: group.name } ],
		beforeEach: [ ...context.beforeEach, ...group.beforeEach ],
		afterEach: [ ...group.afterEach, ...context.afterEach ]
	};

	for (let test in group.tests) {
		let full_path = [ ...new_context.path, { id: test.id, name: test.name } ];
		push(list, {
			path: full_path,
			path_str: util.format_path(full_path),
			fn: test.fn,
			beforeEach: new_context.beforeEach,
			afterEach: new_context.afterEach,
			skipped: test.skipped,
			index: test.index
		});
	}

	for (let sub in group.groups) {
		flatten(sub, new_context, list);
	}
}

export function run_tests(reporter, filter, seed) {
	let start_time = clock();
	let filter_re = filter ? regexp(filter) : null;

	let atomic_tests = [];
	flatten(root, { path: [], beforeEach: [], afterEach: [] }, atomic_tests);
	atomic_tests = util.shuffle(atomic_tests, seed);

	let run_count = 0;
	for (let t in atomic_tests)
		if (!filter_re || match(t.path_str, filter_re))
			run_count++;
	reporter.suite_start(run_count);

	let setup_ok = true;
	if (root.setup) {
		try {
			root.setup();
		} catch (e) {
			reporter.fatal("Module setup failed: " + util.parse_thrown(e).message);
			setup_ok = false;
		}
	}

	if (setup_ok) {
		root.is_running = true;
		const mock = global.__utest_mock_instance;
		let mock_snap = null;
		let snap_ok = true;
		try {
			mock_snap = mock ? mock.snapshot() : null;
		} catch (e) {
			reporter.fatal("Mock snapshot failed: " + util.parse_thrown(e).message);
			snap_ok = false;
		}

		if (snap_ok) {
			for (let test in atomic_tests) {
				if (filter_re && !match(test.path_str, filter_re)) {
					reporter.test_result(null, test.path, "IGNORE", test.index);
					continue;
				}

				if (test.skipped) {
					reporter.test_result(null, test.path, "SKIP", test.index);
					continue;
				}

				let error = null;

				for (let hook in test.beforeEach) {
					try { hook(); } catch (e) {
						if (error === null) error = e;
					}
				}

				// Snapshot after beforeEach (even when it threw) so a patch() applied in
				// beforeEach — whether or not it was followed by unpatch() — cannot leak
				// into afterEach regardless of which hook failed.
				let pre_body_snap = null;
				try {
					pre_body_snap = mock_snap !== null ? mock.snapshot() : null;
				} catch (e) {
					if (error === null) error = e;
				}

				if (error === null) {
					try { test.fn(); } catch (e) { error = e; }
				}

				try {
					if (pre_body_snap !== null) mock.restore(pre_body_snap);
				} catch (e) {
					if (error === null) error = e;
				}

				for (let hook in test.afterEach) {
					try { hook(); } catch (e) {
						if (error === null) error = e;
					}
				}

				if (error !== null) {
					reporter.test_result(error, test.path, null, test.index);
				} else {
					reporter.test_result(null, test.path, "PASS", test.index);
				}

				try {
					if (mock_snap !== null) mock.restore(mock_snap);
				} catch (e) {
					reporter.fatal("Mock state reset failed: " + util.parse_thrown(e).message);
					break;
				}
			}
		}

		root.is_running = false;
	}

	if (setup_ok && root.teardown) {
		try {
			root.teardown();
		} catch (e) {
			reporter.fatal("Module teardown failed: " + util.parse_thrown(e).message);
		}
	}

	let end_time = clock();
	let duration_ms = (end_time[0] - start_time[0]) * 1000 + (end_time[1] - start_time[1]) / 1000000;

	reporter.suite_end(int(duration_ms));
};
