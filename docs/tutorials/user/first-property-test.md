# Writing your first property test

In this tutorial, we will write a property test that checks a function for *all* values in a range rather than a fixed set of hand-picked examples. We will run it, watch the framework find and shrink a counterexample, and learn to read the failure output.

---

## What we will build

A source module `src/math.uc` with a `clamp` function, and a test file that uses `prop` and `gen.int` to verify it against hundreds of randomly generated inputs.

---

## Prerequisites

- A working test suite. If you have not written one yet, complete [Writing your first test suite](first-test.md) first.
- Basic familiarity with `it` and `assert.match`.

---

## Step 1 — Create the source module

Create `src/math.uc`:

```js
export function clamp(value, lo, hi) {
    if (value < lo) return lo;
    if (value > hi) return hi;
    return value;
}
```

`clamp` returns `value` pinned to the range `[lo, hi]`.

---

## Step 2 — Write a passing property

Create `test/unit/math_test.uc`:

```js
import { describe, prop, gen, assert } from 'utest';
import { clamp } from 'math';

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
utest -l src test/unit/math_test.uc
```

You should see 100 cases pass. The framework tried 100 randomly generated `(value, lo, hi)` triples and the property held for all of them.

---

## Step 3 — Introduce a bug and watch it shrink

Replace `clamp` with a broken version that handles only the lower bound:

```js
export function clamp(value, lo, hi) {
    if (value < lo) return lo;
    return value;   // bug: missing upper-bound check
}
```

Run the tests again. You will see output like:

```
  [FAIL] result is always within [lo, hi]
         Property failed after 3 case(s)
         Seed:           ...
         Original value: [ -47, 91, 12 ]
         Shrunk value:   [ 0, 1, 0 ]
         Shrink steps:   8
         Error:          clamp(1, 0, 0) = 1 is out of range
                         Expected true
                           got false
```

The framework found a failure on its third attempt with `(-47, 91, 12)`, then automatically reduced it to the minimal failing triple `(0, 1, 0)` — a value above the upper bound, where `lo == hi == 0` and `value == 1`. That is the smallest possible counterexample.

!!! note
    The exact seed, original value, and shrink count will differ between runs. The shrunk value (`[ 0, 1, 0 ]`) should be stable because it is the true minimal counterexample for this bug.

---

## Step 4 — Fix the bug

Restore the correct implementation:

```js
export function clamp(value, lo, hi) {
    if (value < lo) return lo;
    if (value > hi) return hi;
    return value;
}
```

Run again. All 100 cases pass.

---

## What we just built

- A source module with a `clamp` function and a property test that checks it against hundreds of randomly generated inputs.
- A failing version of `clamp` that let us watch the framework find and shrink a counterexample from `(-47, 91, 12)` down to `(0, 1, 0)`.
- Familiarity with reading the failure output: seed, original value, shrunk value, and the shrink step count.

---

## Next steps

- Browse all available generators: [Property-based testing reference](../../reference/property.md).
- Learn how the shrinking model works: [About property-based testing](../../explanation/property-based-testing.md).
- Learn to reproduce and debug failures: [How to reproduce a failing property](../../how-to/property-reproduce.md).
