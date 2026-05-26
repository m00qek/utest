import { describe, it, assert, equals, contains, truthy, falsy, not, pred, any_order, any, regex } from 'utest';

describe('Combinators', () => {
	it('assert.match() with a plain scalar behaves like assert.eq()', () => {
		assert.match(42, 42);
		assert.match('hello', 'hello');
		assert.match(null, null);
	});

	it('assert.match() with a plain object requires exact equality', () => {
		assert.match({ a: 1, b: 2 }, { a: 1, b: 2 });
		assert.throws(
			() => assert.match({ a: 1, b: 2 }, { a: 1, b: 2, c: 3 }),
			/Expected/
		);
	});

	it('assert.match() allows combinators inside a plain object', () => {
		assert.match({ code: 200, body: contains('host') },{ code: 200, body: 'connected to host' });
	});

	it('assert.match() with a plain array requires exact elements in order', () => {
		assert.match([1, 2, 3], [1, 2, 3]);
		assert.throws(
			() => assert.match([1, 2, 3], [1, 3, 2]),
			/Expected/
		);
	});

	it('assert.match() allows combinators inside a plain array', () => {
		assert.match([any(), any(), any()], [1, 'x', null]);
		assert.match([contains({ id: 1 }), 2],[{ id: 1, extra: 'ignored' }, 2]);
	});

	it('equals() matches by deep equality', () => {
		assert.match(equals({ x: 1 }), { x: 1 });
		assert.throws(
			() => assert.match(equals({ x: 1 }), { x: 2 }),
			/Expected/
		);
	});

	it('contains() works on strings, arrays, and objects', () => {
		assert.match(contains('24.10'), 'OpenWrt 24.10');
		assert.match(contains([2]), [1, 2, 3]);
		assert.match(contains({ code: 200 }), { code: 200, body: 'ok' });
		assert.throws(
			() => assert.match(contains('xyz'), 'hello'),
			/contain/
		);
	});

	it('contains() accepts a combinator as the expected array element', () => {
		assert.match(contains([contains({ id: 1 })]),[{ id: 1, extra: 'ignored' }, { id: 2 }]);
	});

	it('contains() with an array checks for an ordered subsequence', () => {
		assert.match(contains([1, 3]), [1, 2, 3]);
		assert.match(contains([contains({ id: 1 }), contains({ id: 2 })]),[{ id: 1, extra: 'ignored' }, { id: 2 }]);
		assert.throws(
			() => assert.match(contains([1, 3]), [1, 2]),
			/contain/
		);
		// order matters: 1 must appear before 2 in the actual array
		assert.throws(
			() => assert.match(contains([1, 2]), [3, 2, 1]),
			/contain/
		);
	});

	it('contains() recurses into nested arrays', () => {
		assert.match(contains([[1, 3]]), [[1, 2, 3], [4, 5, 6]]);
		assert.throws(
			() => assert.match(contains([[1, 9]]), [[1, 2], [4, 5]]),
			/contain/
		);
	});

	it('contains() on a string expected fails for non-string actual', () => {
		assert.throws(
			() => assert.match(contains('foo'), 42),
			/Expected a string/
		);
	});

	it('contains() matches partial objects, ignoring extra keys', () => {
		assert.match(contains({ code: 200 }), { code: 200, body: 'ok', latency: 5 });
		assert.throws(
			() => assert.match(contains({ code: 200 }), { code: 404 }),
			/Expected/
		);
	});

	it('contains() values may be nested combinators', () => {
		const response = { code: 200, body: 'connected to host' };
		assert.match(contains({ code: 200, body: contains('host') }), response);
	});

	it('contains() recurses into plain object values', () => {
		const response = { code: 200, body: { status: 'ok', extra: 'ignored' } };
		assert.match(contains({ body: { status: 'ok' } }), response);
	});

	it('any_order() matches an array regardless of element order', () => {
		assert.match(any_order([1, 2, 3]), [3, 1, 2]);
		assert.match(any_order([contains({ id: 1 }), contains({ id: 2 })]),[{ id: 2 }, { id: 1 }]);
		assert.throws(
			() => assert.match(any_order([1, 2, 3]), [1, 2]),
			/elements/
		);
	});

	it('any() is a wildcard that matches any value', () => {
		assert.match(contains({ id: any(), name: 'Alice' }), { id: 7, name: 'Alice' });
		assert.match(any(), null);
	});

	it('regex() tests a string against a regex', () => {
		assert.match(regex(/^utest/), 'utest@v1.2.3');
		assert.match(contains({ version: regex(/^\d+\.\d+/) }), { version: '1.2.3' });
		assert.throws(
			() => assert.match(regex(/^\d+/), 'hello'),
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

		assert.match(contains({
			type: 'response',
			payload: contains({
				code: 200,
				headers: contains(['content-type: application/json'])
			})
		}), event);
	});

	it('pred() applies a custom predicate function', () => {
		assert.match(pred(x => x % 2 == 0), 4);
		assert.match(contains([pred(x => x > 2)]), [1, 2, 3]);
		assert.throws(
			() => assert.match(pred(x => x % 2 == 0), 3, 'expected even'),
			/expected even/
		);
	});

	it('not() inverts a combinator', () => {
		assert.match(not(equals(4)), 5);
		assert.match(not(regex(/^\d+/)), 'hello');
		assert.match(not(contains({ code: 200 })), { code: 404 });
		assert.throws(
			() => assert.match(not(equals(4)), 4),
			/not to match/
		);
	});

	it('any_order() backtracks when a wildcard steals a specific matcher\'s element', () => {
		assert.match(any_order([any(), 1]), [1, 2]);
		assert.match(any_order(['c', any(), 'a']), ['a', 'b', 'c']);
		assert.throws(
			() => assert.match(any_order([any(), 1]), [2, 3]),
			/permutation/
		);
	});

	it('contains() on arrays cannot reuse positions and backtracks over wildcards', () => {
		// the same actual position cannot satisfy two matchers
		assert.throws(
			() => assert.match(contains([1, 1]), [1]),
			/contain/
		);
		// backtracking: any() must not permanently block a later specific matcher
		assert.match(contains([any(), 1]), [2, 1]);
		assert.match(contains([any(), 1]), [1, 2, 1]);
		assert.throws(
			() => assert.match(contains([any(), 1]), [1]),
			/contain/
		);
	});

	it('truthy() and falsy() check truthiness', () => {
		assert.match(truthy(), 1);
		assert.match(truthy(), 'x');
		assert.match(falsy(), 0);
		assert.match(falsy(), null);
		assert.throws(() => assert.match(truthy(), 0), /truthy/);
		assert.throws(() => assert.match(falsy(), 1), /falsy/);
	});
});
