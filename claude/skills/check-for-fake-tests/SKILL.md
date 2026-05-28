---
name: check-for-fake-tests
description: >-
  Audit a test suite for "fake" tests — tests whose assertions can pass without
  the system under test actually doing the thing the test claims to verify.
  Reads the test code directly, anchors on the describe/it block names as the
  claimed contract, and traces every assertion back to its data source.
  One-shot: produces a remediation report you fix from and discard.
---

# Check for fake tests

Use this skill when you suspect — or want to rule out — that a test suite is verifying its own UI state instead of the behavior of the system under test (SDK, service, library, etc.). The canonical fake pattern: a button's `onPress` sets a local React state to "Yes" before calling the SDK, and the test's `waitFor(...).toHaveText('Yes')` then proves only that React re-rendered. The SDK could be a no-op and the test would still pass.

This skill produces a one-shot audit report. The output is meant to be **read, acted on, and discarded** — not maintained.

## Extracting the claimed contract

The audit anchors on what each test *claims* to verify. Extract that **before** reading the test's actions, so you don't unconsciously rationalize the verdict from whatever the actions happen to do.

The claim comes from:

1. The `it` / `test` block name — usually the strongest signal ("should NOT update variant when user identifies"). Read it literally.
2. The enclosing `describe` block name(s) — provide topical scope ("global liveUpdates enabled" → the claim is about a configuration the SDK exposes).
3. Any file-level header comment that names the feature under test.

Write down the claim in one sentence before you trace any assertion. If the claim is so vague it can't be falsified ("should render correctly"), say so in the report — that's its own kind of fakeness.

If a separate pseudocode document for the test happens to exist, you may read it as a secondary signal — but do not depend on it. The test source is the ground truth this skill operates on.

## Scope

The user must indicate target test files or a test directory. If unclear, ask. Helper / utility files do not get audited individually — they are followed through when they're called from a test.

## Verdict categories

For each test, assign exactly one verdict:

- **REAL** — every assertion in the test is fed by output from the system under test (resolved value, event stream count, observable state, server response, etc.).
- **PARTIAL** — at least one assertion is real, but at least one other is decoupled (local UI state, static label, always-rendered element).
- **FAKE** — every assertion is decoupled. The test would pass with the system-under-test calls replaced by no-ops.

Be ruthless. "The intent of the test is good" does not redeem an assertion that only reads from local state.

## Audit procedure

For one test file:

1. **Extract the claimed contract** for each test from its `describe` / `it` block names (see "Extracting the claimed contract" above). Write the claim in one sentence per test before reading the rest.
2. **Read the test source**. Note every assertion: visibility, equality, regex match, count comparison. Resist the urge to rationalize the claim against the actions you just read — the claim is fixed by step 1.
3. **For each assertion, find the render site of the element it touches.** Search the application source. Typical locations: screens, components, pages, view models. Use `rg` for the test ID / selector.
4. **Trace the asserted value to its data source.** Ask:
   - Is the displayed value bound to output from the system under test (a hook return, a subscription, an observable, an async response, an event payload)?
   - Or is the displayed value bound to a local state variable (`useState`, ViewModel field, `setText(...)` from the same handler that called the system)?
   - Is the element conditionally rendered based on system-under-test output, or always rendered?
5. **Run the counterfactual:** "If the system-under-test call inside the matching handler were replaced with a no-op (or a stub returning a constant), would this assertion still pass?"
   - **No** → the assertion is real for this test.
   - **Yes** → the assertion is fake for this test.
6. **Combine assertion verdicts into a test verdict:** all real → REAL. Some real, some fake → PARTIAL. All fake → FAKE.
7. **Sketch the smallest fix that would make a fake/partial test real.** Usually: expose a piece of the system-under-test's actual output to the test by adding a test-only element whose value reads from a hook return / subscription / observable, then assert on that element instead.

When tracing values, **cite file paths and line numbers**. Vague claims ("this looks like local state") do not survive review.

## Report layout

Write one report per test file, alongside the test, named `<test-base>-audit-results.md`:

- `e2e/login.test.ts` → `e2e/login-audit-results.md`

Structure:

```
# <test file> — audit results

## Summary
- Total tests: N
- Real: X
- Partial: Y
- Fake: Z

If there are any FAKE or PARTIAL tests, list them by name as a quick-reference up front.

## Per-test analysis

### Group: "<describe name>" (if the source nests)

#### "<exact test name>"

**Verdict:** REAL / PARTIAL / FAKE

**What the test claims to verify:** one sentence derived from the `describe` / `it` block names (see "Extracting the claimed contract"). Quote the test name verbatim if it carries the claim cleanly.

**What it actually verifies:** one to three sentences, plain.

**Trace:**
- Assertion A → source: `path/to/file.tsx:LINE` — explain where the value comes from.
- Assertion B → source: ...

**Counterfactual:** would this test still pass if the system-under-test call inside the matching handler were replaced with a no-op? Yes / No, with a one-sentence reason.

**Recommendation:** "none — test is real" for REAL, or the smallest change that would make the assertion read from system-under-test output.
```

End the report with the verdict counts so they're easy to roll up across files.

## Fan-out

For non-trivial scopes (more than ~2 test files), **fan out one agent per test file in parallel** with the `Agent` tool. Each agent receives:

- The absolute path of the test file.
- A list of likely render-site paths (screens, components, pages) and a starting search command.
- The absolute path where the audit should be written.
- This skill's verdict definitions, "Extracting the claimed contract" guidance, and audit procedure (paraphrase or link).

After all agents return, write a roll-up summary in your final user-facing message: a table of file → REAL / PARTIAL / FAKE counts, and the worst offenders sorted descending by `FAKE + 0.5 × PARTIAL`. Do not write the roll-up to disk — the per-file reports are the artifacts.

## Roll-up summary template

```
Audit roll-up
| Test file | REAL | PARTIAL | FAKE |
|---|---|---|---|
| ... | ... | ... | ... |
| Total | X | Y | Z |

Hot spots (worst → least):
1. <file> — <N> FAKE + <M> PARTIAL. <one-sentence reason from the audit>.
2. ...

Clean files: <list>.
```

## Anti-patterns

- **Reading the test actions before fixing the claim.** If you let the actions inform the claim, you'll judge the test by what it does instead of what it should do. Lock the claim from the `describe` / `it` names first.
- **Accepting an unfalsifiable claim.** "Should render correctly", "should work" — these can't be audited and shouldn't be defended. Call them out as their own kind of fake.
- **Grading on a curve.** "The test author meant well" is not a defense. If every assertion is decoupled, it's FAKE.
- **Vague traces.** "It looks like local state" without a file:line citation is unfalsifiable. Cite or don't claim.
- **Skipping the counterfactual.** It's the single most useful question; running it forces honesty on borderline assertions.
- **Treating `toBeVisible` on a label as a real assertion.** If the label is statically rendered, visibility proves only that the screen mounted.
- **Treating "count incremented after action" as real** without checking that the counter is fed by the system under test's event stream and not by `setCount(c + 1)` next to the SDK call.
- **Recommending huge rewrites.** A good recommendation is the *smallest* source-side change that exposes a real piece of system-under-test output to the test (usually a new test-only element bound to a hook / subscription return).
- **Editing tests as part of the audit.** This skill produces a report; do not modify the test code or the application source. Fixes happen in a separate follow-up.
