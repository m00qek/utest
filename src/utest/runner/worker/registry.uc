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
