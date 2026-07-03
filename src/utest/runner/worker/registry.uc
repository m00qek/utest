/**
 * Worker test registry: the single global tree the DSL builds as describe()/it()
 * run at load time. `root` is the top-level group; `stack` tracks the current
 * nesting during declaration. Held on `global` (like the mock engine's registries)
 * so it survives across the module's re-imports within one worker process.
 *
 * @module utest.runner.worker.registry
 */

if (!global._utest_registry) {
	global._utest_registry = { 
		name: "root", 
		id: 0,
		id_counter: 0,
		test_counter: 0, // Used for declaration order
		tests: [], 
		groups: [], 
		setup: null,
		teardown: null,
		beforeEach: [],
		afterEach: [],
		is_running: false
	};
}

export const root = global._utest_registry;
export const stack = [root];
