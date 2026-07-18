# Writing your first property test

In this tutorial, we will write a property test that checks a function for *all* values in a range rather than a fixed set of hand-picked examples. We will run it, watch the framework find and shrink a counterexample, and learn to read the failure output.

---

## What we will build

A source module `src/calc.uc` with a `clamp` function, and a test file that uses `prop` and `gen.int` to verify it against hundreds of randomly generated inputs.

!!! note
    We name the module `calc` rather than `math`: `math` is a ucode built-in module, so a `math.uc` of your own would be shadowed by it. Avoid built-in names (`math`, `fs`, `uci`, `ubus`, …) for your own modules.

---

## Prerequisites

- A working test suite. If you have not written one yet, complete [Writing your first test suite](first-test.md) first.
- Basic familiarity with `it` and `assert.match`.

---

## Step 1 — Create the source module

Create `src/calc.uc`:

```js
export function clamp(value, lo, hi) {
    if (value < lo) return lo;
    if (value > hi) return hi;
    return value;
};
```

`clamp` returns `value` pinned to the range `[lo, hi]`.

---

## Step 2 — Write a passing property

Create `test/unit/calc_test.uc`:

```js
import { describe, prop, gen, assert } from 'utest';
import { clamp } from 'calc';

describe("clamp()", () => {
    prop("result is always within [lo, hi]",
        gen.tuple(gen.int(-100, 100), gen.int(-100, 100), gen.int(-100, 100)),
        (t) => {
            const lo = t[0] < t[2] ? t[0] : t[2];
            const hi = t[0] < t[2] ? t[2] : t[0];
            const result = clamp(t[1], lo, hi);
            assert.match(true, result >= lo && result <= hi,
                sprintf("clamp(%d, %d, %d) = %d is out of range", t[1], lo, hi, result));
        });
});
```

Run it:

```bash
utest -l src test/unit/calc_test.uc
```

The property passes, shown as a single `[PASS]` line. Behind that one line the framework generated 100 random `(value, lo, hi)` triples and checked the property against every one — a passing property reports as one test, not one per case.

---

## Step 3 — Introduce a bug and watch it shrink

Replace `clamp` with a broken version that handles only the lower bound:

```js
export function clamp(value, lo, hi) {
    if (value < lo) return lo;
    return value;   // bug: missing upper-bound check
};
```

Run the tests again. You will see output like:

```
  [FAIL] result is always within [lo, hi]
         Property failed after 1 case(s)
           Seed:           433556913 (regenerates the original value)
           Original value: [ 0, 2, -29 ]
           Shrunk value:   [ 0, 1, 0 ]
           Shrink evals:   20
           Error:          clamp(1, 0, 0) = 1 is out of range
                           Expected true
                             got false
           Saved to:       test/unit/.utest/property/19d78d9b.json (will replay on next run)
```

The framework found a failing triple, then automatically reduced it to the minimal failing triple `(0, 1, 0)` — a value above the upper bound, where `lo == hi == 0` and `value == 1`. That is the smallest possible counterexample. It also saved the counterexample to `.utest/property/`, so the next run replays this exact failure instead of searching for it again (see [How to reproduce a failing property](../../how-to/property-reproduce.md)).

!!! note
    The case count, seed, original value, shrink count, and saved filename will differ between runs. The shrunk value (`[ 0, 1, 0 ]`) should be stable because it is the true minimal counterexample for this bug.

---

## Step 4 — Fix the bug

Restore the correct implementation:

```js
export function clamp(value, lo, hi) {
    if (value < lo) return lo;
    if (value > hi) return hi;
    return value;
};
```

Run again. The property passes: the framework first replays the saved counterexample (which now holds), deletes it, and resumes random generation on the next run.

---

## What we just built

- A source module with a `clamp` function and a property test that checks it against hundreds of randomly generated inputs.
- A failing version of `clamp` that let us watch the framework find and shrink a counterexample down to the minimal `(0, 1, 0)`.
- Familiarity with reading the failure output: seed, original value, shrunk value, the shrink step count, and the saved counterexample that replays on the next run.

---

## Next steps

- Browse all available generators: [Property-based testing reference](../../reference/property.md).
- Learn how the shrinking model works: [About property-based testing](../../explanation/property-based-testing.md).
- Learn to reproduce and debug failures: [How to reproduce a failing property](../../how-to/property-reproduce.md).
