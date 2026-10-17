---
name: serial-subagents-adversarial
description: >-
  Extends serial-subagents with adversarial verification: after each work subagent completes, a
  separate adversarial verifier subagent is launched to falsify the worker's claims against the
  original spec. The orchestrator acts on the verifier's verdict, not the worker's report. Use
  when correctness is critical: data migrations, security-sensitive code, public API contracts,
  anything where a subtle bug costs more than the extra subagent.
---

# Serial Subagents — Adversarial Verification

This skill layers **adversarial verification** onto the `/serial-subagents` workflow. Read and follow that skill first — everything here builds on it.

The change: each unit runs **work → adversarial verify → act on the verdict** instead of work → act on the report. A worker checking its own output is worthless, and an orchestrator reading diffs is burning the context the whole strategy exists to protect.

## Additional rules (on top of serial-subagents rules)

1. **Every unit is verified by a separate adversarial subagent** — never by the agent that built it, and never by you in the main thread.
2. **The worker and the verifier share the same slot** — still exactly one subagent alive at a time. The verifier launches only after the worker has reported.
3. **The orchestrator acts on verdicts, not on worker reports.** You do not read diffs, re-run tests, or eyeball code. The verifier does that in its own context.
4. **All commits go through `/modular-commits`.** Every work subagent MUST use the `modular-commits` skill for committing. No exceptions — not `git commit`, not a one-liner shortcut, not "it's just one file". The work prompt MUST explicitly instruct: "Commit exclusively via `/modular-commits` — never run `git commit` directly." If a worker's report or the verifier's audit shows commits that were not made through the skill, treat it as a FAIL verdict regardless of correctness.

## Work prompt addition

Add this to every work prompt you write per `/serial-subagents` §3:

- **Notice that its work will be adversarially audited.** Say so plainly: a separate agent will attempt to disprove every claim, so unverified or partial claims will be caught.

## Verification procedure

When the worker reports, **do not read its diff and do not run its tests.** Launch one verifier subagent (`general-purpose` — it needs to run tests and mutate temporarily) whose job is to falsify the work. Its prompt:

- **Frame it as an audit, not a review.** "A previous agent claims to have completed the following. Your job is to disprove it. Assume the claims are overstated until the repository proves otherwise. A finding of 'everything checks out' is only credible if you show the evidence you used to try to break it."
- **Give it the spec verbatim** — the same authoritative ticket/plan text the worker got. The verdict is judged against the spec, never against the worker's summary.
- **Give it the worker's claims as a numbered list of assertions to falsify**, stripped of narrative. Not "the agent did a nice job on X" — "Claim 3: `search_hits()` applies the folder constraint in the KQL query, proven by `test_search_hits_scopes_by_path`."
- **Tell it what to actually do:** read the real diff (`git show`, `git diff <base>...HEAD`); re-run the full test command itself and quote the exact result line; confirm no files were touched outside the unit's scope and nothing reserved was modified; confirm no test was deleted, skipped, or weakened (`git diff` the test files specifically); and check that each acceptance criterion is proven by a test that would actually fail if the behavior regressed.
- **Mandate mutation-verification** for anything correctness- or data-critical: break the implementation, confirm the named test goes red, restore it. Then require it to prove the tree is clean — `git status --porcelain` and `git diff` empty at the end, matching what it found at the start. The verifier must never leave a change behind or create a commit.
- **Look for the classic dodges:** a test asserting on a value the test itself supplied; an assertion loosened to make it pass; a criterion "met" by a test that never exercises the new path; work committed with tests red; scope creep committed alongside.
- **Verify commits used `/modular-commits`.** Check that every commit follows the modular-commits style (single-line imperative message, no extended body, no co-author trailers). If any commit looks like a raw `git commit` (extended description, wrong style), mark it as a REFUTED claim.
- **The verdict contract.** Its last message is all you will see, so specify it exactly: an overall `PASS` / `FAIL` / `PASS WITH CONCERNS`; a per-claim line marked `CONFIRMED` / `REFUTED` / `UNPROVEN` with the one-line evidence for each; the exact test-suite and lint result lines it observed itself; the commit hashes it verified; **the handoff surface the next unit needs** (public signatures, file paths, anything the next worker must build on); and any out-of-scope defects it noticed, described but not fixed.

The verifier is a fresh context that never saw the worker's reasoning — that independence is the whole value. Never reuse the worker agent, never continue it via `SendMessage` to "double-check", and never soften the framing to "confirm this looks right".

## Acting on the verdict

Replace `/serial-subagents` §4 with this:

- **PASS** — check the box, update the durable record (ticket state, checklist, plan file), note the handoff surface for the next unit, and proceed to the next unit.
- **PASS WITH CONCERNS** — record the concerns in the durable record. File genuinely out-of-scope defects as their own tickets rather than fixing them inline.
- **FAIL** — do not fix it yourself. Compose a remediation work prompt carrying the verifier's refuted claims **verbatim** as the spec for what must change, then verify that remediation with a fresh verifier. **If a unit fails verification twice, stop and surface it to the user** — two failed rounds means the plan is wrong, not the execution, and grinding on it unattended wastes the night.

## Additional anti-patterns

- Skipping the verifier on "small" or "obviously fine" units. The cheap ones cost one short subagent; the expensive miss costs a night.
- Asking the verifier to "confirm" rather than to falsify, or handing it the worker's summary instead of the spec.
- Letting the worker verify itself, or continuing the worker agent to audit its own output.
- Checking the box off a worker's report rather than a verifier's verdict.
