import * as detailed from 'utest.runner.reporter.detailed';
import * as compact from 'utest.runner.reporter.compact';
// Aliased to json_repo so the binding doesn't shadow the json() builtin.
import * as json_repo from 'utest.runner.reporter.json';

export function create_reporter(type, use_color, files, seed) {
	let reporter;

	if (type === "compact") {
		reporter = compact.create(use_color);
	} else if (type === "json") {
		reporter = json_repo.create();
	} else {
		reporter = detailed.create(use_color);
	}

	reporter.init(use_color, files, seed);
	return reporter;
};
