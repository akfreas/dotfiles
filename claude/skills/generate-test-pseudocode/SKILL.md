---
name: generate-test-pseudocode
description: >-
  Generate or update platform-agnostic pseudocode docs for a test suite so the
  same behavior can be verified across SDKs/platforms. Idempotent: creates
  missing files, reconciles drifted ones, leaves correct ones alone.
---

# Generate test pseudocode

Use this skill when the user wants a **platform-agnostic written contract** for what a test suite verifies — typically because the same behavior is implemented and tested across multiple SDKs / platforms and they want one-to-one parity between suites.

The output is reference documentation, not executable. It captures **what each test does**, not **how it does it in this framework**.

## Scope

The user must indicate a target: a single test file, a test directory, or "all test suites in <area>". If unclear, ask before scanning. Treat both **test files** and **shared helper / utility files** that those tests import as in scope — helpers get pseudocode too, because tests link to them.

This skill is **idempotent**. Running it twice on the same scope should:

- Create pseudocode files that don't exist.
- Update pseudocode files where the source has drifted (test added, removed, renamed; test ID, expected text, timeout, scroll distance, regex, or ordering changed; helper signature, default, or step changed).
- Leave correct files untouched. Do not churn pure formatting.

## File layout and naming

Place each pseudocode file **next to its source** with the same base name and `-pseudocode.md` suffix:

- `e2e/login.test.ts` → `e2e/login-pseudocode.md`
- `e2e/helpers.js` → `e2e/helpers-pseudocode.md`

If a test imports a helper, the test pseudocode **links** to the helper pseudocode by relative path with the helper's function name as the anchor:

`Reset profile state — see [clearProfileState](./helpers-pseudocode.md#clearprofilestate).`

GitHub renders anchors as lowercase-with-hyphens. Use the function name verbatim, lowercased.

## What pseudocode keeps vs. strips

**Keep** (these are the semantic contract every implementation must honor):

- Every test / element identifier (test IDs, accessibility labels, role+name pairs, selectors as identifier strings).
- Every exact expected text / value asserted on.
- Every timeout, polling interval, sleep, scroll distance, retry count, regex pattern — verbatim in milliseconds / units.
- Ordering of actions and the nesting of describe / context blocks.
- The conditions under which an action fires (fast path vs. fallback, conditional taps).
- Returns and throws of helpers, and what happens on failure (swallow vs. propagate).

**Strip** (framework-specific surface):

- Test runner imports and matcher syntax (`element(by.id(...))`, `screen.getByTestId(...)`, `expect(...).toBeVisible()`, `cy.get(...)`, `findElement(...)`, `assertThat(...)`, etc.).
- Lifecycle hooks expressed as syntax (`beforeAll`, `beforeEach`, `@BeforeEach`, etc.) — describe them by purpose: "Before all tests:", "Before each test:".
- Device / driver commands (`device.launchApp`, `browser.url`, `driver.find_element`, ADB shell, `device.sendToHome`).
- Library-specific waits, retries, and chaining DSL — describe the behavior in plain English ("wait until visible (default timeout)", "poll every 200 ms until the predicate matches or 3000 ms have elapsed").
- Language-level types and imports.

The rule of thumb: another engineer reading the pseudocode in a completely different framework should be able to implement an equivalent test without referring to the original.

## Output structure

### Test file template

```
# <file name> — <short title from the top-level describe block>

## Goal
2–4 sentences explaining what behavior of the system under test this file verifies and why it matters. Be concrete about the feature.

## Constants (if any are declared in the file)
- `NAME = value` — meaning.

## Test setup
- **Before all tests:** step-by-step.
- **Before each test / after each test (if present):** step-by-step.

## Local helpers (if the file defines any non-exported helpers used by its own tests)
### helperName(args)
Steps...

## Tests

Preserve the describe / context nesting.

### Group: "<describe name>"

#### "<exact test name>"

**Verifies:** one sentence.

**Steps:**
1. ...
2. ...
```

Each numbered step is **one concrete action or assertion**. Do not collapse multiple actions into one step. When a step uses a helper, the step is a single line that names the helper and links to its pseudocode.

### Helper file template

```
# Overview
2–4 sentences on the purpose of the file and the rough categories of helpers (state reset, polling, text extraction, etc.).

## CONSTANT_NAME
Document any exported constants with their values and meaning.

## helperName(arg1, arg2 = default)

**Purpose:** one sentence.

**Inputs:** describe each argument and its default.

**Returns / throws:** what it returns and when it throws.

**Steps:**
1. ...
2. ...
```

If a helper internally calls another helper, link to it inline: `[otherHelper](#otherhelper)`. Do not inline another helper's logic.

## Idempotency procedure

For each source file in scope:

1. **Read the source file.**
2. **Check if the pseudocode file already exists.**
3. If **missing** → generate from scratch using the template above.
4. If **present**:
   a. Read it. Enumerate every test / function it currently documents.
   b. Cross-reference with the source: list of currently-present tests / functions, with their current contracts (test IDs touched, expected texts, timeouts, ordering).
   c. **Classify drift** for each documented item:
      - **Removed from source** — delete the section from the pseudocode.
      - **Added in source** — add a new section.
      - **Renamed** — rename the heading; preserve hand-edited body where the surrounding contract still matches.
      - **Contract changed** (test ID, expected text, timeout, regex, scroll distance, ordering, helper default) — rewrite the affected step(s) and **only** those steps.
      - **No drift** — leave alone.
   d. Apply the smallest set of edits that reconciles drift.
5. **Do not regenerate sections that are already correct.** Pseudocode may carry hand-edits and intent the user wants preserved.
6. **Do not introduce formatting churn.** Match the existing file's heading capitalization, bullet style, and code-fence usage.

If a pseudocode file is structurally broken (no top-level `# `, missing `## Goal`, etc.), reformat it once. Note this in the run summary.

## How to run

For non-trivial scopes (more than ~3 source files), **fan out one agent per source file in parallel** with the `Agent` tool. Each agent receives:

- The absolute path of one source file.
- The absolute path of the pseudocode file to create / update.
- This skill's contract (you can paraphrase or link to it).
- The list of helper names available for cross-linking, with the convention `[name](./<helper-base>-pseudocode.md#name)`.
- An instruction to read the existing pseudocode (if any) and apply the idempotency procedure above before regenerating.

When fanning out:

- Process **helper files first** if they don't yet exist, so test agents know which anchors will resolve. If helpers already exist, all agents can run in parallel.
- After all agents return, do a final pass over the parent index (if one exists; e.g. a `README.md` in the test directory) to add links to any newly created pseudocode files.

For very small scopes (1–2 files), do it inline without fan-out.

## Run summary

End the run with a concise summary:

```
Pseudocode run summary
- Created: <N> files (list)
- Updated: <N> files (list, with a one-line "what changed" for each)
- Unchanged: <N> files
- Skipped / errors: <list with reason>
```

Do not declare success without naming what was created vs. updated vs. left alone. If nothing changed, say so explicitly — that is the expected outcome of running this skill twice in a row on an unchanged tree.

## Anti-patterns

- **Regenerating an unchanged file** because it's easier than diffing. The skill is idempotent — running it on a clean tree must produce zero edits.
- **Embedding framework syntax** (`by.id(...)`, `cy.get(...)`, `await expect(...)`) in pseudocode. Strip it.
- **Dropping numeric contracts** ("waits a bit", "scrolls down"). The whole point is parity — keep the exact ms / units.
- **Inlining helper logic** into a test's pseudocode. Link, don't duplicate.
- **Renaming sections to match a new opinion** without underlying drift in the source. Don't.
- **Reformatting whole files** to align with a new template if the existing file is structurally fine. Update in place.
