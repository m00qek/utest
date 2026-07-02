import * as sequential from 'utest.runner.executor.sequential';
import * as parallel from 'utest.runner.executor.parallel';

// ctx carries the run-wide config plus per-bundle `files` and `bundle`; see
// runner.uc for the field list. Defaults are already applied by the caller.
export function execute_suites(ctx) {
	let executor = ctx.jobs > 1 ? parallel.create() : sequential.create();
	executor.execute(ctx);
};
