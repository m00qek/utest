import { THEME, color } from 'utest.runner.reporter.colors';
import { ReporterBase } from 'utest.runner.reporter.base';

export function create(use_color) {
	const t = use_color ? THEME : {
		PASS: "", FAIL: "", ERROR: "", SKIP: "", IGNORE: "", HEADER: "", TIME: "", BOLD: ""
	};

	let reported_suites = {};

	return proto({
		render_suite_start: function(msg) {
			if (reported_suites[msg.suite]) return;
			if (length(keys(reported_suites)) > 0) print("\n");
			reported_suites[msg.suite] = true;
			
			let header = color(t.HEADER, "[" + (msg.bundle || "Default") + "] " + msg.suite);
			print(header);

			if (msg.count !== null) {
				print(" (" + msg.count + " tests)\n");
			} else {
				print("\n");
			}
		},

		render_test_result: function(msg) {
			// Ensure header is printed even if suite_start wasn't called
			this.render_suite_start(msg);

			let name = msg.path[length(msg.path) - 1].name;

			if (msg.status === "PASS") {
				print("  [" + color(t.PASS, "PASS") + "] " + name + "\n");
			} else if (msg.status === "FAIL") {
				print("  [" + color(t.FAIL, "FAIL") + "] " + name + "\n");
				print("         " + color(t.FAIL, replace(msg.error || "", "\n", "\n         ")) + "\n");
			} else if (msg.status === "SKIP") {
				print("  [" + color(t.SKIP, "SKIP") + "] " + name + "\n");
			} else if (msg.status === "IGNORE") {
				print("  [" + color(t.IGNORE, "IGNORE") + "] " + name + "\n");
			} else {
				print("  [" + color(t.BOLD + t.ERROR, "ERR!") + "] " + name + "\n");
				print("         " + color(t.ERROR, replace(msg.error || "", "\n", "\n         ")) + "\n");
			}
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
