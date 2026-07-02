import * as detailed from 'utest.runner.reporter.detailed';
import * as compact from 'utest.runner.reporter.compact';
import * as json_repo from 'utest.runner.reporter.json';

export function create_reporter(type, use_color, files, seed, parallel) {
	let reporter;

	if (type === "compact") {
		reporter = compact.create(use_color);
	} else if (type === "json") {
		reporter = json_repo.create();
	} else {
		// The detailed reporter streams per-suite; under parallel execution
		// results from concurrent suites interleave, so it buffers per suite.
		reporter = detailed.create(use_color, parallel);
	}

	reporter.init(use_color, files, seed);
	return reporter;
};
