import { THEME, color } from 'utest.runner.reporter.colors';
import { ReporterBase } from 'utest.runner.reporter.base';

export function create(use_color, parallel) {
	const t = use_color ? THEME : {
		PASS: "", FAIL: "", ERROR: "", SKIP: "", IGNORE: "", HEADER: "", TIME: "", BOLD: ""
	};

	let reported_suites = {};
	// Parallel only: collect each suite's rendered lines and print the whole
	// block when the suite ends, so results from concurrently-executing suites
	// don't interleave under the wrong header.
	let buffers = {};
	let flushed_any = false;

	// Print directly for -j1 (live streaming, unchanged); accumulate per suite
	// under parallel execution.
	function emit(suite, text) {
		if (parallel) {
			if (!buffers[suite]) buffers[suite] = [];
			push(buffers[suite], text);
		} else {
			print(text);
		}
	}

	function flush(suite) {
		if (!parallel || !buffers[suite]) return;
		if (flushed_any) print("\n");
		for (let line in buffers[suite]) print(line);
		flushed_any = true;
		delete buffers[suite];
	}

	return proto({
		render_suite_start: function(msg) {
			if (reported_suites[msg.suite]) return;
			// -j1 separates suites with a blank line here; under parallel the
			// separator is emitted by flush() between completed blocks instead.
			if (!parallel && length(keys(reported_suites)) > 0) print("\n");
			reported_suites[msg.suite] = true;

			let header = color(t.HEADER, "[" + (msg.bundle || "Default") + "] " + msg.suite);
			emit(msg.suite, header + (msg.count !== null ? " (" + msg.count + " tests)\n" : "\n"));
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
			emit(msg.suite, text);
		},

		render_suite_end: function(msg) {
			flush(msg.suite);
		},

		render_fatal: function(msg) {
			this.render_suite_start(msg);
			emit(msg.suite, "  [" + color(t.BOLD + t.ERROR, "FATAL") + "] " + (msg.error || "") + "\n");
		},

		render_summary: function(ctx) {
			// Flush any suites that never emitted SUITE_END (timeouts / fatals).
			if (parallel) for (let s in keys(buffers)) flush(s);

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
