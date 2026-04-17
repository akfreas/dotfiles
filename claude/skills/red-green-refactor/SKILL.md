---
name: red-green-refactor
description: >-
  Take a red-green-refactor (TDD) approach to fixing bugs or adding behavior:
  failing test first, smallest change to pass, then refactor with tests green.
---

# Red–Green–Refactor (TDD)

Use this workflow when the task is a **behavior change or bugfix** and tests exist or can be added. The cycle is **one small behavior at a time**, not a big-bang implementation.

## When to apply

- Fixing a defect: reproduce it as an automated test first when possible.
- Adding behavior: express the new rule as a test before production code.
- Refactoring: tests should already pass; change structure without changing behavior (tests stay green; optional characterization tests if coverage is thin).

## The cycle

### 1. Red — failing test

- Write **one** test that describes the **next** desired behavior (or the bug).
- Run tests and confirm this test **fails** for the right reason (assertion/message), not for environment or typos.
- Prefer **narrow** tests (one behavior, clear name) over a test that tries to cover a whole flow at once.

### 2. Green — minimal code

- Implement the **smallest** change that makes the new test pass.
- Do **not** optimize, deduplicate, or “clean up” yet if that is not required to pass the test.
- Run the full relevant test suite; **all** tests should pass before moving on.

### 3. Refactor — improve with safety net

- Improve names, structure, and duplication **without changing behavior**.
- Keep tests green after each small refactor step; if something breaks, revert that step.
- Prefer several tiny refactors over one large risky edit.

## Practices that keep the cycle honest

- **Repeat** red → green → refactor for each new behavior or test case; do not stack many untested changes.
- **Fast feedback**: run tests often; slow suites make people skip steps.
- **Automate**: the failing test must be runnable the same way every time.
- **Refactor after green**, not instead of green: passing tests first, then design cleanup.

## Anti-patterns to avoid

- Writing production code before a failing test for the new behavior.
- Writing a passing test that does not actually assert the bug or requirement.
- **Skipping refactor** and leaving duplication or unclear names “because it works.”
- Making the green step too large (multiple behaviors at once).

## Agent checklist

1. Identify or add a test that captures the bug or new rule.
2. Confirm **red** (expected failure).
3. Implement **minimal** fix or feature to get **green**.
4. **Refactor** if duplication or unclear structure appeared; re-run tests.
5. Summarize what the test now guarantees and what changed in code.
