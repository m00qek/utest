function empty_stats() {
	return { total: 0, passed: 0, failed: 0, errors: 0, fatals: 0, skipped: 0, ignored: 0 };
}

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
		this.stats = {
			total: 0, passed: 0, failed: 0, errors: 0, fatals: 0, skipped: 0, ignored: 0, suites: 0
		};
		this.failures = [];
		this.results = [];
		this._start_time = clock();
		this._suite_stats = {};
		this._bundle_stats = {};
		this._bundle_start_times = {};
		return this;
	},

	bundle_start: function(name) {
		this._bundle_start_times[name] = clock();
		if (!this._bundle_stats[name]) {
			this._bundle_stats[name] = empty_stats();
		}
		if (this.render_bundle_start) this.render_bundle_start(name);
	},

	bundle_end: function(name) {
		let start = this._bundle_start_times[name];
		let end_time = clock();
		let duration_ms = start
			? (end_time[0] - start[0]) * 1000 + (end_time[1] - start[1]) / 1000000
			: 0;
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

		this.stats.total++;
		if (!this._suite_stats[file]) {
			this._suite_stats[file] = empty_stats();
		}
		this._suite_stats[file].total++;

		if (bundle) {
			if (!this._bundle_stats[bundle]) {
				this._bundle_stats[bundle] = empty_stats();
			}
			this._bundle_stats[bundle].total++;
		}

		if (msg.status === "PASS") {
			this.stats.passed++;
			this._suite_stats[file].passed++;
			if (bundle) this._bundle_stats[bundle].passed++;
		} else if (msg.status === "FAIL") {
			this.stats.failed++;
			this._suite_stats[file].failed++;
			if (bundle) this._bundle_stats[bundle].failed++;
			push(this.failures, msg);
		} else if (msg.status === "ERROR") {
			this.stats.errors++;
			this._suite_stats[file].errors++;
			if (bundle) this._bundle_stats[bundle].errors++;
			push(this.failures, msg);
		} else if (msg.status === "SKIP") {
			this.stats.skipped++;
			this._suite_stats[file].skipped++;
			if (bundle) this._bundle_stats[bundle].skipped++;
		} else if (msg.status === "IGNORE") {
			this.stats.ignored++;
			this._suite_stats[file].ignored++;
			if (bundle) this._bundle_stats[bundle].ignored++;
		}
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
		let end_time = clock();
		let duration_ms = (end_time[0] - this._start_time[0]) * 1000 + (end_time[1] - this._start_time[1]) / 1000000;
		
		let context = {
			stats: this.stats,
			failures: this.failures,
			results: this.results,
			files: this.files,
			duration_ms: int(duration_ms),
			seed: this.seed
		};

		if (this.render_summary) this.render_summary(context);
	}
};
