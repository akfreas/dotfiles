---
name: local-first-then-ci
description: >-
  Workflow for changes that need CI validation: get every locally-runnable check
  green first, then push and enter the monitor → fix → push loop until CI is green.
---

# Local-first, then CI iteration

Use this workflow when a change needs to pass CI before it can ship — tests, lint, typecheck, build, or any check that has both a fast local equivalent and a slower CI counterpart.

## The strategy

CI cycles are slow and expensive. Local cycles are fast and free. The cheaper loop catches the cheaper bugs; only push to CI once the cheap bugs are gone.

There are two phases. Do not start phase 2 until phase 1 is fully green.

## Phase 1 — Get local green

1. **Identify the relevant local check.** Read the workflow file (`.github/workflows/*.yaml`) and find the exact script CI runs. Prefer running that same script locally (e.g., `pnpm lint`, `pnpm test:unit`, `pnpm build`). Match scope: if CI runs the suite, run the suite — not just one file.
2. **Run it. Capture failures.** Read the actual error, not a summary.
3. **Fix root causes, not symptoms.** Do not skip, mock around, retry-loop, or disable the failing check to make it pass. If a test is wrong, fix the test; if the code is wrong, fix the code. (This matches the user's standing rule: no hack workarounds.)
4. **Re-run after each fix.** Confirm that change made the failure go away and didn't introduce a new one.
5. **Repeat until every locally-runnable check is green.** Do not push speculatively just to "see what CI says."

Only move to phase 2 once everything that *can* be validated locally has been.

## Phase 2 — Push and monitor

1. **Commit and push** the branch.
2. **Find the run:** `gh run list --branch <branch> --limit 1`.
3. **Watch non-blockingly.** Either:
   - run `gh run watch <run-id>` as a background task, or
   - poll periodically with `gh run list` / `gh run view <run-id>`.
   Do not foreground-block waiting for a 10-minute CI run.
4. **On green: do not trust the green.** A green status only means the job exited 0 — it does not mean every test passed. Before reporting success, thoroughly read the logs of the target test suite to confirm tests actually ran and actually passed. See [Verifying a "green" run](#verifying-a-green-run) below.
5. **On red:**
   - Fetch failed logs: `gh run view <run-id> --log-failed`. Read them, don't skim.
   - Classify: is this a real defect, a CI-only environment difference (ordering, timing, platform, missing setup), or flake?
   - **Reproduce locally if possible**, even for CI-only failures — often a flag, env var, or `CI=true` is enough.
   - Fix root cause. Re-run the relevant local check to confirm it's actually fixed before pushing.
   - Commit, push, return to step 2.
6. Loop until CI is **verified** green (see below — green status is not enough).

## Verifying a "green" run

A green check mark in `gh run list` is not proof the tests passed. Test runners, shell pipelines, and CI configurations can silently swallow failures. Before declaring a CI run successful, **pull the full logs of the target test job and read them**, looking for the failure modes below.

### Fetch the logs

- Identify the job that runs the suite: `gh run view <run-id>` (note the job name).
- Pull its full log, not just failed steps: `gh run view <run-id> --job <job-id> --log`.
- For large logs, save to a file and search: `gh run view <run-id> --job <job-id> --log > /tmp/ci.log` then grep.

### What to look for

1. **The test summary line.** Find the test runner's own pass/fail/skip counts (e.g., `Tests: 42 passed, 3 skipped`, `BUILD SUCCESSFUL in Xs`, `OK (n tests)`, `PASS · FAIL · TOTAL`). Confirm the **expected number of tests actually ran**. A suite that runs 0 tests and exits 0 is the most common silent failure.
2. **Skipped / ignored / pending tests.** A test marked `@Ignore`, `it.skip`, `xdescribe`, `pending`, `[skipped]`, `SKIP`, or filtered out by a tag/pattern is not a passing test. Count them and confirm each one is intentional.
3. **Error / exception / stack trace strings even when the step succeeded.** Grep the log for `Error`, `Exception`, `FAIL`, `failed`, `Caused by`, `Traceback`, `panic`, `assertion`, `Timeout`. A runner can log a thrown error and still exit 0 if the error happened outside the pass/fail accounting (setup, teardown, post-step).
4. **"No tests found" / empty discovery.** `No tests ran`, `0 tests executed`, `No tests found for given includes`, `collected 0 items`. Often caused by a path glob or filter that matches nothing.
5. **Build/compile errors that didn't fail the step.** Some toolchains print compile errors but still hand control to a later "summary" step that exits 0. Check for `error:`, `unresolved reference`, `cannot find symbol`, `compilation failed`.
6. **Timeouts and process kills.** `Timed out after`, `killed`, `OOMKilled`, `process exited with`, `Received SIGTERM`. CI may treat a timeout as a soft fail or hide it inside an outer "always" step.
7. **`continue-on-error` / `if: always()` / `|| true` / `set +e`.** Inspect the workflow YAML for any step that explicitly swallows failures. If found, treat its output as advisory and verify the underlying tool's own exit reporting from the logs.
8. **Conditional / matrix jobs that were skipped.** A matrix entry that was skipped is reported as success at the workflow level. Confirm every matrix entry you expected to run actually ran.
9. **Retries that eventually passed.** Flaky retries that finally turned green are still flake — note them as follow-up, don't silently accept.
10. **Artifact / report uploads that say "no files matched".** A test reporter that found no JUnit XML often means tests never executed. `No files were found with the provided path`.

### Decision

- **Tests actually ran, count matches expectation, no swallowed errors, skips are intentional →** verified green. Report and stop.
- **Anything else →** treat as red. Diagnose, fix root cause (do not "fix" by suppressing the warning), and push again.

## Anti-patterns

- **Push-and-pray:** pushing before local checks pass, hoping CI will tell you what's wrong. Burns CI minutes, lengthens feedback by 10-100×.
- **Hack workarounds:** disabling a test, adding retries, sleeping past a race, or `continue-on-error` to make red turn green. Hides the underlying bug; will resurface worse.
- **Speculative fixes:** changing code before reading the failed log. Each speculative push costs a full CI cycle.
- **Foreground-polling CI:** blocking the session for minutes on a run that the harness can notify you about, or that you can check on demand.
- **Skipping local re-run after a fix:** "the fix is obvious, just push it." It's not obvious; push only after the local check passes again.
- **Trusting the green check.** Status green ≠ tests passed. Always confirm from the test runner's own summary in the logs that the expected tests actually ran and actually passed.
- **Grepping only for `FAIL`.** Many silent failures don't print `FAIL` — they print `Error`, `0 tests ran`, `No tests found`, or nothing at all and exit 0. Look for the *positive* signal (expected pass count) too.

## Agent checklist

1. Locate the CI script in `.github/workflows/`; identify its local equivalent.
2. Run the local check; collect failures.
3. Fix root cause; re-run; repeat until locally green.
4. Push.
5. Watch the CI run (in background or by polling on demand).
6. On failure: pull `--log-failed`, diagnose, reproduce locally where possible, fix root cause, re-run locally, push again.
7. **On green: pull the full target-suite log, find the test runner's pass/skip/total summary, confirm the expected number of tests ran, and grep for swallowed errors / "no tests found" / unexpected skips.** Only declare success once the logs actually prove tests passed.
8. Loop steps 5–7 until verified green.
