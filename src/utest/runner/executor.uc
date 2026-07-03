import * as sequential from 'utest.runner.executor.sequential';
import * as parallel from 'utest.runner.executor.parallel';

// ctx carries the run-wide config plus per-bundle `files` and `bundle`; see
// runner.uc for the field list. Defaults are already applied by the caller.
// Returns true when the run was interrupted (SIGINT/SIGTERM caught mid-run under
// -jN), so the caller can stop launching further bundles. Sequential (-j1) is
// killed outright by a signal and returns nothing (falsy).
export function execute_suites(ctx) {
	let executor = ctx.jobs > 1 ? parallel.create() : sequential.create();
	return executor.execute(ctx);
};
