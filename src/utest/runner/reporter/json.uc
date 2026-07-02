import { ReporterBase } from 'utest.runner.reporter.base';

export function create() {
	return proto({
		render_summary: function(ctx) {
			// The base summary context already carries stats, bundles, results,
			// failures, files, duration and seed — just serialize it.
			print(sprintf("%J\n", ctx));
		}
	}, ReporterBase);
};
