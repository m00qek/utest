import { ReporterBase } from 'utest.runner.reporter.base';

export function create() {
	return proto({
		render_summary: function(ctx) {
			// Include bundle stats and all results in the final JSON output
			ctx.bundles = this._bundle_stats;
			ctx.results = this.results;
			print(sprintf("%J\n", ctx));
		}
	}, ReporterBase);
};
