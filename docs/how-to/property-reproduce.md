# How to reproduce a failing property

When a property test fails, the framework automatically shrinks the input to the minimal counterexample and saves the failure state locally. This guide shows how to reproduce failures both locally and from CI.

---

## Replay a local failure

You don't need to do anything to reproduce a local failure. Just run the test again:

```bash
utest test/unit/math_test.uc
```

The framework automatically saves the minimal counterexample to `.utest/property/`. On the next run, it will detect this file, skip the random generation phase, and immediately replay the exact same failing inputs. 

If the test passes during the replay (e.g., because you fixed the bug), the framework deletes the saved counterexample and resumes normal randomized testing on subsequent runs.

---

## Reproduce a CI failure locally

If a property fails in CI, the automatic `.utest/property/` file is lost when the CI job ends. To reproduce it locally, you need the **Seed** printed in the CI failure output:

```
  [FAIL] result is always within [lo, hi]
         Property failed after 42 case(s)
         Seed:           1708451234
         Original value: [ -47, 91, 12 ]
         Shrunk value:   [ 0, 1, 0 ]
```

If you want to reproduce the exact run without touching source, pass the seed via the `-s` CLI flag:

```bash
utest -s 1708451234 test/unit/math_test.uc
```

This seeds both the test-file shuffle order and the default seed for all property tests, so the full run matches what CI saw.

If you need to isolate a single property — for example, when the file contains multiple properties with different seeds — hardcode the seed on that one `prop` call instead:

```js
prop("result is always within [lo, hi]", generator, (t) => {
    // ...
}, { seed: 1708451234 });
```

!!! warning "Remove hardcoded seeds"
    Remember to remove the `{ seed: ... }` option once you have fixed the bug, so the property returns to randomized testing on future runs.

---

## Next steps

- All CLI flags including `-s`: [CLI and Configuration Reference](../reference/cli.md)
- How the seed controls generation and shrinking: [About property-based testing](../explanation/property-based-testing.md)
- Keep CI from losing counterexamples: [How to run tests in CI](ci.md)
