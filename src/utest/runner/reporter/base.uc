import { elapsed_ms, mono_clock } from 'utest.util';

function empty_stats() {
	return { total: 0, passed: 0, failed: 0, errors: 0, fatals: 0, skipped: 0, ignored: 0 };
}

// Test status -> the stats counter it increments; FAIL/ERROR also go on the
// failures list. Drives test_result so adding a status is a one-line change.
const STATUS_KEY = { PASS: "passed", FAIL: "failed", ERROR: "errors", SKIP: "skipped", IGNORE: "ignored" };
const IS_FAILURE = { FAIL: true, ERROR: true };

// _suite_stats is nested by (bundle, file), not keyed on file alone: the same
// file path can legitimately appear in two different bundles (overlapping
// bundle patterns, or the same file named in two bundle args), and a
// file-only key would merge the second bundle's counts into the first's
// bucket instead of giving each occurrence its own. Nesting (rather than a
// joined string key) sidesteps ucode object keys truncating at an embedded
// NUL — verified live: `{}["a\0b"]` and `{}["a\0c"]` collide on "a".
export function has_suite_stats(store, bundle, file) {
	let b = store[bundle ?? ""];
	return !!(b && b[file]);
};

export function get_suite_stats(store, bundle, file) {
	let b = bundle ?? "";
	if (!store[b]) store[b] = {};
	if (!store[b][file]) store[b][file] = empty_stats();
	return store[b][file];
};

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
		if (!has_suite_stats(this._suite_stats, msg.bundle, msg.suite)) this.stats.suites++;
		get_suite_stats(this._suite_stats, msg.bundle, msg.suite);
		if (this.render_suite_start) this.render_suite_start(msg);
	},

	suite_end: function(msg) {
		let stats = get_suite_stats(this._suite_stats, msg.bundle, msg.suite);
		if (this.render_suite_end) this.render_suite_end({ ...msg, stats: stats });
	},

	test_result: function(msg) {
		let bundle = msg.bundle;

		push(this.results, msg);

		let suite_stats = get_suite_stats(this._suite_stats, bundle, msg.suite);
		if (bundle && !this._bundle_stats[bundle]) this._bundle_stats[bundle] = empty_stats();

		let status_key = STATUS_KEY[msg.status];
		let targets = [ this.stats, suite_stats ];
		if (bundle) push(targets, this._bundle_stats[bundle]);
		for (let s in targets) {
			s.total++;
			if (status_key) s[status_key]++;
		}
		if (IS_FAILURE[msg.status]) push(this.failures, msg);

		if (this.render_test_result) this.render_test_result(msg);
	},

	fatal: function(msg) {
		push(this.failures, msg);
		push(this.results, msg);
		this.stats.fatals++;

		// An aggregate FATAL (e.g. the parallel-run interrupt) names a pseudo-suite,
		// not a real one, so it must not count toward the suite total.
		if (msg.suite && !msg.aggregate) {
			if (!has_suite_stats(this._suite_stats, msg.bundle, msg.suite)) this.stats.suites++;
			get_suite_stats(this._suite_stats, msg.bundle, msg.suite);
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
