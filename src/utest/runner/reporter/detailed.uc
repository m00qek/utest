import { theme, color } from 'utest.runner.reporter.colors';
import { ReporterBase } from 'utest.runner.reporter.base';

export function create(use_color) {
	const t = theme(use_color);

	let reported_suites = {};

	// Results stream live, printed as events arrive. This is safe under parallel
	// execution because the uloop executor feeds each worker's entire output in a
	// single callback, so one suite's events always arrive contiguously — concurrent
	// suites never interleave.
	return proto({
		render_suite_start: function(msg) {
			if (reported_suites[msg.suite]) return;
			if (length(keys(reported_suites)) > 0) print("\n");
			reported_suites[msg.suite] = true;

			let header = color(t.HEADER, "[" + (msg.bundle || "Default") + "] " + msg.suite);
			print(header + (msg.count !== null ? " (" + msg.count + " tests)\n" : "\n"));
		},

		render_test_result: function(msg) {
			// Ensure header is printed even if suite_start wasn't called
			this.render_suite_start(msg);

			let name = msg.path[length(msg.path) - 1].name;
			let text;

			if (msg.status === "PASS") {
				text = "  [" + color(t.PASS, "PASS") + "] " + name + "\n";
			} else if (msg.status === "FAIL") {
				text = "  [" + color(t.FAIL, "FAIL") + "] " + name + "\n" +
				       "         " + color(t.FAIL, replace(msg.error || "", "\n", "\n         ")) + "\n";
			} else if (msg.status === "SKIP") {
				text = "  [" + color(t.SKIP, "SKIP") + "] " + name + "\n";
			} else if (msg.status === "IGNORE") {
				text = "  [" + color(t.IGNORE, "IGNORE") + "] " + name + "\n";
			} else {
				text = "  [" + color(t.BOLD + t.ERROR, "ERR!") + "] " + name + "\n" +
				       "         " + color(t.ERROR, replace(msg.error || "", "\n", "\n         ")) + "\n";
			}
			print(text);
		},

		render_fatal: function(msg) {
			this.render_suite_start(msg);
			print("  [" + color(t.BOLD + t.ERROR, "FATAL") + "] " + (msg.error || "") + "\n");
		},

		render_summary: function(ctx) {
			let stats = ctx.stats;
			print("\n" + color(t.HEADER, "Summary:") + "\n");
			print("  Suites:  " + stats.suites + "\n");
			print("  Total:   " + stats.total + "\n");

			print("  Passed:  " + color(t.PASS, stats.passed) + "\n");
			print("  Failed:  " + color(t.FAIL, stats.failed) + "\n");
			print("  Errors:  " + color(t.BOLD + t.ERROR, stats.errors) + "\n");
			if (stats.fatals)  print("  Fatals:  " + color(t.BOLD + t.ERROR, stats.fatals) + "\n");
			if (stats.skipped) print("  Skipped: " + color(t.SKIP, stats.skipped) + "\n");
			if (stats.ignored) print("  Ignored: " + color(t.IGNORE, stats.ignored) + "\n");

			print("  Time:    " + color(t.TIME, ctx.duration_ms + " ms") + "\n");
			print("  Seed:    " + ctx.seed + "\n");
		}
	}, ReporterBase);
};
