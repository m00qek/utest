import { elapsed_ms, mono_clock } from 'utest.util';

function empty_stats() {
	return { total: 0, passed: 0, failed: 0, errors: 0, fatals: 0, skipped: 0, ignored: 0 };
}

// Test status -> the stats counter it increments; FAIL/ERROR also go on the
// failures list. Drives test_result so adding a status is a one-line change.
const STATUS_KEY = { PASS: "passed", FAIL: "failed", ERROR: "errors", SKIP: "skipped", IGNORE: "ignored" };
const IS_FAILURE = { FAIL: true, ERROR: true };

export const ReporterBase = {
	stats: null,
	failures: null,
	results: null,
	use_color: false,
	files: null,
	seed: null,
	_bundle_start_times: null,
	_suite_stats: null,
	_bundle_stats: null,

	init: function(use_color, files, seed) {
		this.use_color = use_color;
		this.files = files;
		this.seed = seed;
		this.stats = { ...empty_stats(), suites: 0 };
		this.failures = [];
		this.results = [];
		this._start_time = mono_clock();
		this._suite_stats = {};
		this._bundle_stats = {};
		this._bundle_start_times = {};
		return this;
	},

	bundle_start: function(name) {
		this._bundle_start_times[name] = mono_clock();
		if (!this._bundle_stats[name]) {
			this._bundle_stats[name] = empty_stats();
		}
		if (this.render_bundle_start) this.render_bundle_start(name);
	},

	bundle_end: function(name) {
		let start = this._bundle_start_times[name];
		let duration_ms = start ? elapsed_ms(start, mono_clock()) : 0;
		if (this.render_bundle_end) this.render_bundle_end(name, int(duration_ms), this._bundle_stats[name]);
	},

	suite_start: function(msg) {
		let file = msg.suite;
		if (!this._suite_stats[file]) {
			this.stats.suites++;
			this._suite_stats[file] = empty_stats();
		}
		if (this.render_suite_start) this.render_suite_start(msg);
	},

	suite_end: function(msg) {
		let file = msg.suite;
		if (this.render_suite_end) this.render_suite_end({ ...msg, stats: this._suite_stats[file] });
	},

	test_result: function(msg) {
		let file = msg.suite;
		let bundle = msg.bundle;

		push(this.results, msg);

		if (!this._suite_stats[file]) this._suite_stats[file] = empty_stats();
		if (bundle && !this._bundle_stats[bundle]) this._bundle_stats[bundle] = empty_stats();

		let key = STATUS_KEY[msg.status];
		let targets = [ this.stats, this._suite_stats[file] ];
		if (bundle) push(targets, this._bundle_stats[bundle]);
		for (let s in targets) {
			s.total++;
			if (key) s[key]++;
		}
		if (IS_FAILURE[msg.status]) push(this.failures, msg);

		if (this.render_test_result) this.render_test_result(msg);
	},

	fatal: function(msg) {
		push(this.failures, msg);
		push(this.results, msg);
		this.stats.fatals++;

		if (msg.suite && !this._suite_stats[msg.suite]) {
			this.stats.suites++;
			this._suite_stats[msg.suite] = empty_stats();
		}
		if (msg.bundle) {
			if (!this._bundle_stats[msg.bundle])
				this._bundle_stats[msg.bundle] = empty_stats();
			this._bundle_stats[msg.bundle].fatals++;
		}
		if (this.render_fatal) this.render_fatal(msg);
	},

	summary: function() {
		let duration_ms = elapsed_ms(this._start_time, mono_clock());

		let context = {
			stats: this.stats,
			failures: this.failures,
			results: this.results,
			bundles: this._bundle_stats,
			files: this.files,
			duration_ms: int(duration_ms),
			seed: this.seed
		};

		if (this.render_summary) this.render_summary(context);
	}
};
