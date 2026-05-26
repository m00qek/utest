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
	if (_err != null) die(_err);
};

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

export const xit = skip;

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
	if (_err != null) die(_err);
};

export function setup(fn) {
	guard();
	if (length(stack) > 1) {
		die("setup() can only be used at module level (outside describe)");
	}
	root.setup = fn;
};

export function teardown(fn) {
	guard();
	if (length(stack) > 1) {
		die("teardown() can only be used at module level (outside describe)");
	}
	root.teardown = fn;
};

export function beforeEach(fn) {
	guard();
	push(stack[length(stack)-1].beforeEach, fn);
};

export function afterEach(fn) {
	guard();
	push(stack[length(stack)-1].afterEach, fn);
};
