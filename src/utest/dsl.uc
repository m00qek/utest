import { root, stack } from 'utest.runner.worker.registry';

function guard(msg) {
	if (root.is_running) {
		die(msg || "DSL functions cannot be called during test execution");
	}
}

function is_currently_skipped() {
	for (let i = length(stack) - 1; i >= 0; i--) {
		if (stack[i].skipped) return true;
	}
	return false;
}

/**
 * @typedef {function(): void} TestCallback
 */

/**
 * Defines a test suite.
 * 
 * @param {string} name - The name of the test suite.
 * @param {TestCallback} fn - The callback containing the test suite definition.
 */
export function describe(name, fn) {
	guard();
	let parent = stack[length(stack)-1];
	let group = {
		id: ++root.id_counter,
		name,
		tests: [],
		groups: [],
		beforeEach: [],
		afterEach: [],
		skipped: is_currently_skipped()
	};
	push(parent.groups, group);
	push(stack, group);
	let _err = null;
	try { fn(); } catch(e) { _err = e; }
	pop(stack);
	if (_err !== null) die(_err);
};

/**
 * Defines a single test case.
 * 
 * @param {string} name - The name of the test.
 * @param {TestCallback} fn - The test logic to execute.
 */
export function it(name, fn) {
	guard();
	let current = stack[length(stack)-1];
	push(current.tests, { 
		id: ++root.id_counter,
		name, 
		fn,
		index: ++root.test_counter,
		skipped: is_currently_skipped()
	});
};

/**
 * Unconditionally skips a test case.
 * 
 * @param {string} name - The name of the test.
 * @param {TestCallback} [fn] - The test logic (which will not be executed).
 */
export function skip(name, fn) {
	guard();
	let current = stack[length(stack)-1];
	push(current.tests, {
		id: ++root.id_counter,
		name,
		fn: null,
		index: ++root.test_counter,
		skipped: true
	});
};

/**
 * Alias for skip. Unconditionally skips a test case.
 * 
 * @type {function}
 */
export const xit = skip;

/**
 * Unconditionally skips an entire test suite and all tests within it.
 * 
 * @param {string} name - The name of the test suite.
 * @param {TestCallback} [fn] - The callback containing the suite definition.
 */
export function xdescribe(name, fn) {
	guard();
	let parent = stack[length(stack)-1];
	let group = {
		id: ++root.id_counter,
		name,
		tests: [],
		groups: [],
		beforeEach: [],
		afterEach: [],
		skipped: true
	};
	push(parent.groups, group);
	push(stack, group);
	let _err = null;
	try { if (fn) fn(); } catch(e) { _err = e; }
	pop(stack);
	if (_err !== null) die(_err);
};

/**
 * Registers a setup function to run once before any tests in the current module.
 * 
 * @param {TestCallback} fn - The setup logic.
 */
export function setup(fn) {
	guard();
	if (length(stack) > 1)
		die("setup() can only be used at module level (outside describe)");
	if (root.setup !== null)
		die("setup() can only be called once per file");
	root.setup = fn;
};

/**
 * Registers a teardown function to run once after all tests in the current module.
 * 
 * @param {TestCallback} fn - The teardown logic.
 */
export function teardown(fn) {
	guard();
	if (length(stack) > 1)
		die("teardown() can only be used at module level (outside describe)");
	if (root.teardown !== null)
		die("teardown() can only be called once per file");
	root.teardown = fn;
};

/**
 * Registers a function to run before each test in the current suite.
 * 
 * @param {TestCallback} fn - The logic to execute.
 */
export function beforeEach(fn) {
	guard();
	push(stack[length(stack)-1].beforeEach, fn);
};

/**
 * Registers a function to run after each test in the current suite.
 * 
 * @param {TestCallback} fn - The logic to execute.
 */
export function afterEach(fn) {
	guard();
	push(stack[length(stack)-1].afterEach, fn);
};
