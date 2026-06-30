import { THEME, color } from 'utest.runner.reporter.colors';
import { ReporterBase } from 'utest.runner.reporter.base';

export function create(use_color) {
	const t = use_color ? THEME : {
		PASS: "", FAIL: "", ERROR: "", SKIP: "", IGNORE: "", HEADER: "", TIME: "", BOLD: ""
	};

	let bundle_data = {}; // name -> { dots_on_line, file_failures }

	function get_bundle(name) {
		if (!bundle_data[name]) {
			bundle_data[name] = {
				file_failures: {}, // file -> [failures]
				dots_on_line: 0
			};
		}
		return bundle_data[name];
	}

	function print_dot(bundle_name, sym, clr) {
		let b = get_bundle(bundle_name);
		// Start new bundle with indent
		if (b.dots_on_line === 0) {
			print("  ");
		}
		if (b.dots_on_line >= 78) {
			print("\n  ");
			b.dots_on_line = 0;
		}
		print(color(clr, sym));
		b.dots_on_line++;
	}

	function print_failure_details(f) {
		let path_str = "";
		let name = "";
		if (f.path) {
			for (let i = 0; i < length(f.path); i++) {
				let p = f.path[i];
				if (p.id !== 0) {
					if (i === length(f.path) - 1) {
						name = p.name;
					} else {
						path_str += p.name + " > ";
					}
				}
			}
		}

		let symbol = (f.status === "FAIL" ? "■" : "▲");
		let status_color = (f.status === "FAIL" ? t.FAIL : t.ERROR);

		print(sprintf("    %s %s%s\n", color(status_color, symbol), path_str, name));

		let lines = split(f.error, "\n");
		if (lines) {
			for (let line in lines) {
				print("        " + color(status_color, line) + "\n");
			}
		}
	}

	function print_summary_line(s_stats, duration_ms, indent) {
		let fatals_part = s_stats.fatals ? " / " + color(t.BOLD + t.ERROR, s_stats.fatals) + " fatals" : "";
		print(sprintf("%s%s successes / %s failures / %s errors%s / %s skipped / %s ignored (%s)\n",
			indent || "",
			color(t.BOLD + t.PASS, s_stats.passed || 0),
			color(t.BOLD + t.FAIL, s_stats.failed || 0),
			color(t.BOLD + t.ERROR, s_stats.errors || 0),
			fatals_part,
			color(t.BOLD + t.SKIP, s_stats.skipped || 0),
			color(t.BOLD + t.IGNORE, s_stats.ignored || 0),
			color(t.TIME, sprintf("%d ms", duration_ms || 0))));
	}

	return proto({
		render_bundle_start: function(name) {
			print(color(t.HEADER, "● Bundle: " + name) + "\n");
		},

		render_bundle_end: function(name, duration_ms, stats) {
			let b = get_bundle(name);
			print("\n");

			for (let file in keys(b.file_failures)) {
				let fails = b.file_failures[file];
				if (length(fails) > 0) {
					print("\n" + color(t.HEADER, "  " + file + ":") + "\n");
					let first = true;
					for (let f in fails) {
						if (!first) print("\n");
						print_failure_details(f);
						first = false;
					}
				}
			}
			print("\n");
			print_summary_line(stats, duration_ms, "  ");
		},

		render_suite_start: function(msg) {
			let b = get_bundle(msg.bundle);
			if (!b.file_failures[msg.suite]) {
				b.file_failures[msg.suite] = [];
			}
		},

		render_test_result: function(msg) {
			if (msg.status === "PASS") {
				print_dot(msg.bundle, "●", t.PASS);
			} else if (msg.status === "SKIP") {
				print_dot(msg.bundle, "○", t.SKIP);
			} else if (msg.status === "IGNORE") {
				print_dot(msg.bundle, "◌", t.IGNORE);
			} else if (msg.status === "FAIL") {
				print_dot(msg.bundle, "■", t.FAIL);
				let b = get_bundle(msg.bundle);
				if (!b.file_failures[msg.suite]) b.file_failures[msg.suite] = [];
				push(b.file_failures[msg.suite], msg);
			} else if (msg.status === "ERROR") {
				print_dot(msg.bundle, "▲", t.ERROR);
				let b = get_bundle(msg.bundle);
				if (!b.file_failures[msg.suite]) b.file_failures[msg.suite] = [];
				push(b.file_failures[msg.suite], msg);
			}
		},

		render_fatal: function(msg) {
			print_dot(msg.bundle, "!", t.BOLD + t.ERROR);
			let b = get_bundle(msg.bundle);
			if (!b.file_failures[msg.suite]) b.file_failures[msg.suite] = [];
			push(b.file_failures[msg.suite], {
				status: "ERROR",
				error: msg.error,
				path: [{ name: "Fatal Error" }]
			});
		},

		render_summary: function(ctx) {
			print("\n" + color(t.HEADER, "Summary:") + "\n\n");
			print_summary_line(ctx.stats, ctx.duration_ms, "  ");
			print("  Seed:   " + ctx.seed + "\n");
		}
	}, ReporterBase);
};
