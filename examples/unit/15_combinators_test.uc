import { describe, it, equals, contains, has, any_order, any, matches } from 'utest';
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
			[has({ id: 1 }), 2]
		);
	});

	it('equals() matches by deep equality', () => {
		assert.match({ x: 1 }, equals({ x: 1 }));
		assert.throws(
			() => assert.match({ x: 2 }, equals({ x: 1 })),
			/Expected/
		);
	});

	it('contains() matches substrings and array elements', () => {
		assert.match('OpenWrt 24.10', contains('24.10'));
		assert.match([1, 2, 3], contains(2));
		assert.match([{ id: 1 }, { id: 2 }], contains({ id: 1 }));
		assert.throws(
			() => assert.match('hello', contains('xyz')),
			/contain/
		);
	});

	it('contains() accepts a combinator as the expected array element', () => {
		assert.match(
			[{ id: 1, extra: 'ignored' }, { id: 2 }],
			contains(has({ id: 1 }))
		);
	});

	it('contains() with an array checks all elements are present', () => {
		assert.match([1, 2, 3], contains([1, 3]));
		assert.match(
			[{ id: 1, extra: 'ignored' }, { id: 2 }],
			contains([has({ id: 1 }), has({ id: 2 })])
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

	it('has() matches partial objects, ignoring extra keys', () => {
		assert.match({ code: 200, body: 'ok', latency: 5 }, has({ code: 200 }));
		assert.throws(
			() => assert.match({ code: 404 }, has({ code: 200 })),
			/Expected/
		);
	});

	it('has() values may be nested combinators', () => {
		const response = { code: 200, body: 'connected to host' };
		assert.match(response, has({ code: 200, body: contains('host') }));
	});

	it('has() recurses into plain object values', () => {
		const response = { code: 200, body: { status: 'ok', extra: 'ignored' } };
		assert.match(response, has({ body: { status: 'ok' } }));
	});

	it('any_order() matches an array regardless of element order', () => {
		assert.match([3, 1, 2], any_order([1, 2, 3]));
		assert.match(
			[{ id: 2 }, { id: 1 }],
			any_order([has({ id: 1 }), has({ id: 2 })])
		);
		assert.throws(
			() => assert.match([1, 2], any_order([1, 2, 3])),
			/elements/
		);
	});

	it('any() is a wildcard that matches any value', () => {
		assert.match({ id: 7, name: 'Alice' }, has({ id: any(), name: 'Alice' }));
		assert.match(null, any());
	});

	it('matches() tests a string against a regex', () => {
		assert.match('utest@v1.2.3', matches(/^utest/));
		assert.match({ version: '1.2.3' }, has({ version: matches(/^\d+\.\d+/) }));
		assert.throws(
			() => assert.match('hello', matches(/^\d+/)),
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

		assert.match(event, has({
			type: 'response',
			payload: has({
				code: 200,
				headers: contains(['content-type: application/json'])
			})
		}));
	});

	it('any_order() backtracks when a wildcard steals a specific matcher\'s element', () => {
		assert.match([1, 2], any_order([any(), 1]));
		assert.match(['a', 'b', 'c'], any_order(['c', any(), 'a']));
		assert.throws(
			() => assert.match([2, 3], any_order([any(), 1])),
			/permutation/
		);
	});
});
