# Tutorials

Tutorials are learning-oriented guides that walk you through a concrete task from start to finish.

---

## For test authors

Do these in order — each one builds on the previous.

| Tutorial | Description |
|---|---|
| [Writing your first test suite](user/first-test.md) | Create a source module, import it from a test file, and run the suite with `-l`. **Start here.** |
| [Writing your first mock](user/first-mock.md) | Use dependency injection to pass a mock proxy directly to your code — no config file needed. |
| [Writing flexible assertions with combinators](user/first-combinators.md) | Use `contains`, `any_order`, `truthy`, `regex`, and `not` to assert what matters without over-specifying what doesn't. |
| [Writing your first property test](user/first-property-test.md) | Write a property test that checks a function for all values in a range and watch the framework find and shrink a counterexample. |

---

## For contributors

Complete the test-author tutorials first, then:

| Tutorial | Description |
|---|---|
| [Contributing your first patch](contributor/first-patch.md) | Clone the repo, extend the framework, and verify your change against the regression suite. |
