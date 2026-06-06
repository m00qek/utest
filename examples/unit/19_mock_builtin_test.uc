'use strict';

import { describe, it, assert, mock } from 'utest';

// Covers mock.inject_builtin() and mock.global.patch_builtin/unpatch_builtin.
// These intercept ucode built-in globals (warn, system, print, …) that are
// not loadable modules and therefore unreachable via the shim-based mock API.

describe('Mock built-ins', () => {
	it('inject_builtin() replaces the built-in for the duration of the callback', () => {
		const captured = [];
		mock.inject_builtin('warn', (...args) => push(captured, join('', args)), () => {
			warn('inside\n');
		});
		assert.match(1, length(captured));
		assert.match('inside\n', captured[0]);
	});

	it('inject_builtin() restores the original after the callback', () => {
		const orig = global.warn;
		mock.inject_builtin('warn', () => null, () => {});
		assert.match(orig, global.warn);
	});

	it('inject_builtin() restores the original even when the callback throws', () => {
		const orig = global.warn;
		let threw = false;
		try {
			mock.inject_builtin('warn', () => null, () => { die('boom'); });
		} catch (e) {
			threw = true;
		}
		assert.match(true, threw);
		assert.match(orig, global.warn);
	});

	it('inject_builtin() calls can be nested', () => {
		const log = [];
		mock.inject_builtin('warn', (...a) => push(log, 'outer:' + join('', a)), () => {
			warn('a');
			mock.inject_builtin('warn', (...a) => push(log, 'inner:' + join('', a)), () => {
				warn('b');
			});
			warn('c');
		});
		assert.match(['outer:a', 'inner:b', 'outer:c'], log);
	});

	it('inject_builtin() layers on top of an active patch_builtin()', () => {
		const log = [];
		mock.global.patch_builtin('warn', (...a) => push(log, 'patched:' + join('', a)));
		mock.inject_builtin('warn', (...a) => push(log, 'injected:' + join('', a)), () => {
			warn('inside');
		});
		warn('outside');
		mock.global.unpatch_builtin('warn');
		assert.match(['injected:inside', 'patched:outside'], log);
	});

	it('global.patch_builtin() replaces the built-in persistently', () => {
		const captured = [];
		mock.global.patch_builtin('warn', (...args) => push(captured, join('', args)));
		warn('patched\n');
		mock.global.unpatch_builtin('warn');
		assert.match(1, length(captured));
		assert.match('patched\n', captured[0]);
	});

	it('global.unpatch_builtin() restores the original', () => {
		const orig = global.warn;
		mock.global.patch_builtin('warn', () => null);
		mock.global.unpatch_builtin('warn');
		assert.match(orig, global.warn);
	});
});
