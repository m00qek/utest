import { describe, it, equals, contains, truthy, falsy, not, pred, any_order, any, regex } from 'utest';
import { assert } from 'utest.assert';

/**
 * Combinator Assertions
 *
 * Demonstrates assert.match() and the combinator factories that compose with it.
 * Combinators are composable predicates: each returns an object whose .match()
 * method returns { ok, message } without throwing.
 */

describe('Combinators', () => {
	it('assert.match() with a plain scalar behaves like assert.eq()', () => {
		assert.match(42, 42);
		assert.match('hello', 'hello');
		assert.match(null, null);
	});

	it('assert.match() with a plain object requires exact equality', () => {
		assert.match({ a: 1, b: 2 }, { a: 1, b: 2 });
		assert.throws(
			() => assert.match({ a: 1, b: 2, c: 3 }, { a: 1, b: 2 }),
			/Expected/
		);
	});

	it('assert.match() allows combinators inside a plain object', () => {
		assert.match(
			{ code: 200, body: 'connected to host' },
			{ code: 200, body: contains('host') }
		);
	});

	it('assert.match() with a plain array requires exact elements in order', () => {
		assert.match([1, 2, 3], [1, 2, 3]);
		assert.throws(
			() => assert.match([1, 3, 2], [1, 2, 3]),
			/Expected/
		);
	});

	it('assert.match() allows combinators inside a plain array', () => {
		assert.match([1, 'x', null], [any(), any(), any()]);
		assert.match(
			[{ id: 1, extra: 'ignored' }, 2],
			[contains({ id: 1 }), 2]
		);
	});

	it('equals() matches by deep equality', () => {
		assert.match({ x: 1 }, equals({ x: 1 }));
		assert.throws(
			() => assert.match({ x: 2 }, equals({ x: 1 })),
			/Expected/
		);
	});

	it('contains() works on strings, arrays, and objects', () => {
		assert.match('OpenWrt 24.10', contains('24.10'));
		assert.match([1, 2, 3], contains([2]));
		assert.match({ code: 200, body: 'ok' }, contains({ code: 200 }));
		assert.throws(
			() => assert.match('hello', contains('xyz')),
			/contain/
		);
	});

	it('contains() accepts a combinator as the expected array element', () => {
		assert.match(
			[{ id: 1, extra: 'ignored' }, { id: 2 }],
			contains([contains({ id: 1 })])
		);
	});

	it('contains() with an array checks all elements are present', () => {
		assert.match([1, 2, 3], contains([1, 3]));
		assert.match(
			[{ id: 1, extra: 'ignored' }, { id: 2 }],
			contains([contains({ id: 1 }), contains({ id: 2 })])
		);
		assert.throws(
			() => assert.match([1, 2], contains([1, 3])),
			/contain/
		);
	});

	it('contains() recurses into nested arrays', () => {
		assert.match([[1, 2, 3], [4, 5, 6]], contains([[1, 3]]));
		assert.throws(
			() => assert.match([[1, 2], [4, 5]], contains([[1, 9]])),
			/contain/
		);
	});

	it('contains() on a string expected fails for non-string actual', () => {
		assert.throws(
			() => assert.match(42, contains('foo')),
			/Expected a string/
		);
	});

	it('contains() matches partial objects, ignoring extra keys', () => {
		assert.match({ code: 200, body: 'ok', latency: 5 }, contains({ code: 200 }));
		assert.throws(
			() => assert.match({ code: 404 }, contains({ code: 200 })),
			/Expected/
		);
	});

	it('contains() values may be nested combinators', () => {
		const response = { code: 200, body: 'connected to host' };
		assert.match(response, contains({ code: 200, body: contains('host') }));
	});

	it('contains() recurses into plain object values', () => {
		const response = { code: 200, body: { status: 'ok', extra: 'ignored' } };
		assert.match(response, contains({ body: { status: 'ok' } }));
	});

	it('any_order() matches an array regardless of element order', () => {
		assert.match([3, 1, 2], any_order([1, 2, 3]));
		assert.match(
			[{ id: 2 }, { id: 1 }],
			any_order([contains({ id: 1 }), contains({ id: 2 })])
		);
		assert.throws(
			() => assert.match([1, 2], any_order([1, 2, 3])),
			/elements/
		);
	});

	it('any() is a wildcard that matches any value', () => {
		assert.match({ id: 7, name: 'Alice' }, contains({ id: any(), name: 'Alice' }));
		assert.match(null, any());
	});

	it('regex() tests a string against a regex', () => {
		assert.match('utest@v1.2.3', regex(/^utest/));
		assert.match({ version: '1.2.3' }, contains({ version: regex(/^\d+\.\d+/) }));
		assert.throws(
			() => assert.match('hello', regex(/^\d+/)),
			/match/
		);
	});

	it('combinators compose into nested structures', () => {
		const event = {
			type: 'response',
			payload: {
				code: 200,
				headers: ['content-type: application/json', 'x-request-id: abc']
			}
		};

		assert.match(event, contains({
			type: 'response',
			payload: contains({
				code: 200,
				headers: contains(['content-type: application/json'])
			})
		}));
	});

	it('pred() applies a custom predicate function', () => {
		assert.match(4, pred(x => x % 2 == 0));
		assert.match([1, 2, 3], contains([pred(x => x > 2)]));
		assert.throws(
			() => assert.match(3, pred(x => x % 2 == 0, 'expected even')),
			/expected even/
		);
	});

	it('not() inverts a combinator', () => {
		assert.match(5, not(equals(4)));
		assert.match('hello', not(regex(/^\d+/)));
		assert.match({ code: 404 }, not(contains({ code: 200 })));
		assert.throws(
			() => assert.match(4, not(equals(4))),
			/not to match/
		);
	});

	it('any_order() backtracks when a wildcard steals a specific matcher\'s element', () => {
		assert.match([1, 2], any_order([any(), 1]));
		assert.match(['a', 'b', 'c'], any_order(['c', any(), 'a']));
		assert.throws(
			() => assert.match([2, 3], any_order([any(), 1])),
			/permutation/
		);
	});

	it('truthy() and falsy() check truthiness', () => {
		assert.match(1, truthy());
		assert.match('x', truthy());
		assert.match(0, falsy());
		assert.match(null, falsy());
		assert.throws(() => assert.match(0, truthy()), /truthy/);
		assert.throws(() => assert.match(1, falsy()), /falsy/);
	});
});
