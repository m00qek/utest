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
 * A function passed to describe, it, skip, setup, teardown, beforeEach, or afterEach.
 *
 * @typedef {function(): void} TestCallback
 */

// Shared body for describe/xdescribe: push a group, run its definition callback
// with the stack extended, then pop — propagating any error only after the pop so
// the stack stays balanced (ucode has no `finally`). `skipped` is the one axis
// that varies between the plain and x-prefixed forms.
function define_group(name, fn, skipped) {
	guard();
	let parent = stack[length(stack)-1];
	let group = {
		id: ++root.id_counter,
		name,
		tests: [],
		groups: [],
		beforeEach: [],
		afterEach: [],
		skipped
	};
	push(parent.groups, group);
	push(stack, group);
	let _err, _had_err = false;
	try { if (fn) fn(); } catch(e) { _err = e; _had_err = true; }
	pop(stack);
	if (_had_err) die(_err);
}

// Shared body for it/skip: register a test on the current group.
function define_test(name, fn, skipped) {
	guard();
	push(stack[length(stack)-1].tests, {
		id: ++root.id_counter,
		name,
		fn,
		index: ++root.test_counter,
		skipped
	});
}

/**
 * Defines a test suite.
 *
 * @param {string} name - The name of the test suite.
 * @param {TestCallback} fn - The callback containing the test suite definition.
 */
export function describe(name, fn) {
	if (type(fn) !== 'function')
		die(sprintf("describe(%J) requires a function argument", name));
	define_group(name, fn, is_currently_skipped());
};

/**
 * Defines a single test case.
 *
 * @param {string} name - The name of the test.
 * @param {TestCallback} fn - The test logic to execute.
 */
export function it(name, fn) {
	// A missing/non-function body would otherwise register fine and only explode at
	// run time as an opaque "left-hand side is not a function". Fail at declaration,
	// pointing at skip() for a deliberately pending test — the one case where a body
	// is legitimately absent (skip()/xit go through define_test directly, not here).
	if (type(fn) !== 'function')
		die(sprintf("it(%J) needs a function body — use skip() for a pending test", name));
	define_test(name, fn, is_currently_skipped());
};

/**
 * Unconditionally skips a test case.
 *
 * @param {string} name - The name of the test.
 * @param {TestCallback} [fn] - The test logic (which will not be executed).
 */
export function skip(name, fn) { define_test(name, null, true); };

/**
 * Alias for {@link skip} — an `it`-shaped name for an unconditionally skipped
 * test case.
 *
 * @param {string} name - The name of the test.
 * @param {TestCallback} [fn] - The test logic (which will not be executed).
 */
export const xit = skip;

/**
 * Unconditionally skips an entire test suite and all tests within it.
 *
 * @param {string} name - The name of the test suite.
 * @param {TestCallback} [fn] - The callback containing the suite definition.
 */
export function xdescribe(name, fn) { define_group(name, fn, true); };

/**
 * Registers a setup function to run once before any tests in the current module.
 * 
 * @param {TestCallback} fn - The setup logic.
 */
export function setup(fn) {
	guard();
	if (type(fn) !== 'function')
		die("setup() requires a function argument");
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
	if (type(fn) !== 'function')
		die("teardown() requires a function argument");
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
	if (type(fn) !== 'function')
		die("beforeEach() requires a function argument");
	push(stack[length(stack)-1].beforeEach, fn);
};

/**
 * Registers a function to run after each test in the current suite.
 * 
 * @param {TestCallback} fn - The logic to execute.
 */
export function afterEach(fn) {
	guard();
	if (type(fn) !== 'function')
		die("afterEach() requires a function argument");
	push(stack[length(stack)-1].afterEach, fn);
};
