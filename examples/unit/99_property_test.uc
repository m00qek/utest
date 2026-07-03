import { describe, it, assert, prop, forall, gen } from 'utest';
import * as fs from 'fs';
import { mkdir_p } from 'utest.util';

// Property-based tests: instead of asserting on hand-picked inputs, you
// declare a property that should hold for *all* values drawn from a generator.
// The framework explores random cases.  When a property fails, it shrinks the
// counterexample down to a minimal failing input and reports it.

describe("Properties of arithmetic", () => {
	prop("addition is commutative",
		gen.tuple(gen.int(-100, 100), gen.int(-100, 100)),
		(p) => assert.match(p[0] + p[1], p[1] + p[0]));

	prop("multiplication by 0 is 0",
		gen.int(-1000, 1000),
		(n) => assert.match(0, n * 0));

	prop("absolute value is non-negative",
		gen.int(-1000, 1000),
		(n) => assert.match(true, (n >= 0 ? n : -n) >= 0));
});

describe("Properties of arrays", () => {
	// classify() reports how often each label held — useful for confirming
	// the generator actually hits the edge cases you care about.
	prop("length is non-negative",
		gen.array(gen.int(0, 100), { max_len: 10 }),
		(xs, ctx) => {
			ctx.classify("empty", length(xs) === 0);
			ctx.classify("full",  length(xs) === 10);
			assert.match(true, length(xs) >= 0);
		});

	prop("reverse of reverse is identity",
		gen.array(gen.int(0, 100), { max_len: 10 }),
		(xs) => {
			let r1 = [];
			for (let i = length(xs) - 1; i >= 0; i--) push(r1, xs[i]);
			let r2 = [];
			for (let i = length(r1) - 1; i >= 0; i--) push(r2, r1[i]);
			assert.match(xs, r2);
		});
});

describe("Properties with dependent generation", () => {
	// gen.bind lets a later generator's shape depend on an earlier value.
	prop("array of length n really has length ≤ n",
		gen.bind(gen.int(0, 5), (n) =>
			gen.array(gen.int(0, 9), { max_len: n })),
		(xs) => assert.match(true, length(xs) <= 5));
});

describe("Generator validation", () => {
	it("gen.int rejects lo > hi", () => {
		assert.throws(() => gen.int(10, 0), /lo \(10\) must be <= hi \(0\)/);
	});

	it("gen.float rejects lo > hi", () => {
		assert.throws(() => gen.float(1.0, 0.0), /lo .* must be <= hi/);
	});

	it("gen.float rejects NaN bounds", () => {
		assert.throws(() => gen.float(0.0 / 0.0, 1.0), /bounds must be finite/);
	});

	it("gen.float rejects infinite bounds", () => {
		assert.throws(() => gen.float(0.0, 1.0 / 0.0), /bounds must be finite/);
	});

	it("gen.array rejects negative max_len", () => {
		assert.throws(() => gen.array(gen.int(0, 9), { max_len: -1 }), /max_len \(-1\) must be >= 0/);
	});

	it("gen.string rejects negative max_len", () => {
		assert.throws(() => gen.string({ max_len: -1 }), /max_len \(-1\) must be >= 0/);
	});

	it("gen.frequency rejects a negative weight", () => {
		assert.throws(() => gen.frequency([2, gen.int(0, 1)], [-1, gen.int(2, 3)]),
		              /weight must be a non-negative integer/);
	});

	it("forall fails when all runs are discarded", () => {
		assert.throws(
			() => forall(gen.filter(gen.int(0, 0), (n) => n > 0), () => null,
			             { seed: 1, persist: false }),
			/Property exhausted/
		);
	});

	it("prop() with explicit persist_id: null disables persistence", () => {
		let caught = null;
		try {
			forall(gen.int(0, 0), (n) => assert.match(1, n),
			       { seed: 1, persist_id: null });
		} catch (e) { caught = e; }
		assert.match(true, caught !== null, "expected forall to fail");
		const sentinel = json(type(caught) === 'object' ? caught.message : sprintf('%s', caught));
		const msg = sentinel.__utest__.message;
		assert.match(true, !!match(msg, /Property failed/),  "failure message expected");
		assert.match(true,  !match(msg, /Saved to:/),        "no persist path expected when persist_id is null");
	});
});

describe("Generator smoke tests", () => {
	prop("gen.bool produces only true or false",
		gen.bool(),
		(b) => assert.match(true, b === true || b === false),
		{ seed: 1, persist: false });

	prop("gen.float is within bounds",
		gen.float(-1.0, 1.0),
		(f) => assert.match(true, f >= -1.0 && f <= 1.0),
		{ seed: 1, persist: false });

	prop("gen.float with hi=0 never produces NaN",
		gen.float(-1.0, 0.0),
		(f) => assert.match(true, f === f && f >= -1.0 && f <= 0.0),
		{ seed: 1, persist: false });

	prop("gen.float with lo=0 never produces NaN",
		gen.float(0.0, 1.0),
		(f) => assert.match(true, f === f && f >= 0.0 && f <= 1.0),
		{ seed: 1, persist: false });

	prop("gen.string has bounded length",
		gen.string({ max_len: 10 }),
		(s) => assert.match(true, length(s) <= 10),
		{ seed: 1, persist: false });

	prop("gen.ascii has bounded length",
		gen.ascii({ max_len: 8 }),
		(s) => assert.match(true, length(s) <= 8),
		{ seed: 1, persist: false });

	prop("gen.alphanumeric has bounded length",
		gen.alphanumeric({ max_len: 8 }),
		(s) => assert.match(true, length(s) <= 8),
		{ seed: 1, persist: false });

	prop("gen.record produces an object with correct field ranges",
		gen.record({ x: gen.int(0, 10), y: gen.int(0, 10) }),
		(r) => {
			assert.match(true, r.x >= 0 && r.x <= 10);
			assert.match(true, r.y >= 0 && r.y <= 10);
		},
		{ seed: 1, persist: false });

	prop("gen.oneof picks one of the given generators",
		gen.oneof(gen.int(0, 0), gen.int(1, 1)),
		(n) => assert.match(true, n === 0 || n === 1),
		{ seed: 1, persist: false });

	prop("gen.elements picks one of the given values",
		gen.elements("a", "b", "c"),
		(s) => assert.match(true, s === "a" || s === "b" || s === "c"),
		{ seed: 1, persist: false });

	prop("gen.frequency picks a value from one of the weighted generators",
		gen.frequency([1, gen.int(0, 0)], [2, gen.int(1, 1)]),
		(n) => assert.match(true, n === 0 || n === 1),
		{ seed: 1, persist: false });

	prop("gen.optional produces null or a value in range",
		gen.optional(gen.int(0, 10)),
		(v) => assert.match(true, v === null || (v >= 0 && v <= 10)),
		{ seed: 1, persist: false });

	prop("gen.map transforms the output of a generator",
		gen.map(gen.int(0, 10), (n) => n * 2),
		(n) => assert.match(true, n >= 0 && n <= 20 && n % 2 === 0),
		{ seed: 1, persist: false });

	prop("gen.constant always produces the same value",
		gen.constant(42),
		(n) => assert.match(42, n),
		{ seed: 1, persist: false });

	prop("gen.filter only returns values matching the predicate",
		gen.filter(gen.int(0, 10), (n) => n % 2 === 0),
		(n) => assert.match(true, n % 2 === 0),
		{ seed: 1, persist: false });

	prop("gen.array with exact length via len option",
		gen.array(gen.int(0, 9), { len: 3 }),
		(xs) => assert.match(3, length(xs)),
		{ seed: 1, persist: false });

	prop("gen.string with exact length via len option",
		gen.string({ len: 5 }),
		(s) => assert.match(5, length(s)),
		{ seed: 1, persist: false });
});

describe("Regression tests", () => {
	it("gen.float with strongly asymmetric range generates values on both sides of zero", () => {
		// Before the fix, int() truncated pos_quota to 0 when pos_room/total < 1/precision.
		// With precision=10 and gen.float(-1000, 1): pos_quota was 0, making the entire
		// positive side unreachable regardless of the draw.
		let saw_positive = false;
		forall(gen.float(-1000.0, 1.0, { precision: 10 }),
		       (f) => {
		           assert.match(true, f >= -1000.0 && f <= 1.0);
		           if (f > 0) saw_positive = true;
		       },
		       { seed: 1, runs: 50, persist: false });
		assert.match(true, saw_positive, "gen.float with asymmetric range must reach the positive side");
	});

	it("mkdir_p creates directories at relative paths without redirecting to root", () => {
		// Before the fix, the first non-empty path segment was joined as '/'+part
		// instead of part, turning './.utest/test' into '/./.utest/test'.
		const dir = ".utest/mkdir_regression_test";
		assert.match(true, mkdir_p(dir), "mkdir_p must succeed for a relative path");
		assert.match(true, !!fs.access(dir, "r"), "directory must exist at the relative path");
		assert.match(false, !!fs.access("/.utest/mkdir_regression_test", "r"),
		             "directory must NOT exist under the root filesystem");
		fs.rmdir(dir);
	});

	it("gen.int reaches nonzero multiples of the 0-bias denominator", () => {
		// Before the fix, the 1-in-8 zero-bias decision and the value were drawn
		// from the same rand(), so nonzero multiples of 8 were unreachable when 8
		// divided the range: gen.int(0, 15) could never produce 8.
		let saw_8 = false;
		forall(gen.int(0, 15), (n) => { if (n === 8) saw_8 = true; },
		       { seed: 1, runs: 200, persist: false });
		assert.match(true, saw_8, "gen.int(0, 15) must be able to produce 8");
	});

	it("gen.int produces values above 2^31 for wide ranges", () => {
		// Before the fix, draws were math.rand() % bound with rand() capped at
		// 2^31-1, silently truncating any span wider than 2^31.
		let saw_large = false;
		forall(gen.int(0, 1099511627776), (n) => { if (n > 2147483647) saw_large = true; },
		       { seed: 1, runs: 100, persist: false });
		assert.match(true, saw_large, "gen.int over a 2^40 range must exceed 2^31");
	});
});

describe("Failing properties (demonstrate shrinking output)", () => {
	// Bogus claim: every int in [0, 1000] is < 50.  When this fails the
	// framework shrinks the counterexample to the boundary value, 50.
	// We pin the seed and disable persistence so the demo output is
	// reproducible from one run to the next.
	//
	// Note the explicit assertion message: a bare `assert.match(true, n < 50)`
	// would only produce "Expected true got false", which makes failures hard
	// to interpret.  Including the actual value lets the reader connect the
	// shrunk counterexample to the failed condition immediately.
	prop("all ints in [0, 1000] are < 50",
		gen.int(0, 1000),
		(n) => assert.match(true, n < 50, sprintf("n = %d is not < 50", n)),
		{ seed: 1, persist: false });

	// Bogus claim: no array of small ints contains a 3.  Shrinker reduces
	// to a short array that still contains 3.
	prop("no array of ints contains 3",
		gen.array(gen.int(0, 9), { max_len: 8 }),
		(xs) => {
			for (let i = 0; i < length(xs); i++)
				assert.match(true, xs[i] !== 3,
					sprintf("xs[%d] is 3", i));
		},
		{ seed: 1, persist: false });
});
