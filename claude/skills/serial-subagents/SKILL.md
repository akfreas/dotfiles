---
name: serial-subagents
description: >-
  Execute a long-horizon, multi-step task by delegating it to subagents one at a time, strictly
  serially — the orchestrator keeps a durable checklist, hands each subagent a bespoke prompt
  carrying exactly the context it needs, then hands the finished work to a separate adversarial
  verifier subagent that tries to disprove it and reports a verdict back up. The main thread
  holds orchestration only: no diffs, no test output, no file reads. The point is context
  isolation and a fresh context per unit of work, NOT parallelism. Use when the user says "use a
  subagent for each task", "one subagent at a time", "don't blow up the context", "work overnight
  on this", "delegate each one by one", or hands over a long task list / plan / ticket sequence
  that will not fit in one context window.
---

# Serial Subagents

One subagent alive at a time: build it, then verify it in a fresh adversarial context, then move on.

The goal is **context containment**, not speed. Each unit of work gets a fresh, uncluttered context window sized to exactly that unit; the main thread stays small enough to run the whole job to completion without compaction. Fanning out concurrently defeats this — it floods the main thread with interleaved reports and makes verification impossible.

The orchestrator's context is a **ledger, not a workspace**. It holds the checklist, the verdicts, and the handoff notes between units. Diffs, test output, log files, and source reads belong in subagent contexts and must never be pulled into the main thread.

## Non-negotiable rules

1. **Exactly one subagent running at a time** — worker or verifier, they take the same slot. Never launch the next before the current one has reported. Never batch two units into one agent because "it's in the same file anyway".
2. **The plan lives on disk, not in your context.** Before delegating anything, the checklist exists as a durable artifact — a plan file, a ticket, a scratchpad markdown. If the session died right now, a fresh context must be able to pick up from that artifact alone. If you find yourself writing a long plan *into* a subagent prompt, that plan belongs in the durable record first; point the subagent at it.
3. **You own state; subagents own work.** Ticket states, checklist updates, cross-task decisions, branch/PR management, and anything the user must be told belong to the orchestrator. Subagents implement, test, and commit their own scope — nothing else.
4. **Every unit is verified by a separate adversarial subagent** — never by the agent that built it, and never by you in the main thread. A worker checking its own work is worthless, and an orchestrator reading diffs is burning the context this whole strategy exists to protect. You act on the verdict, not on the evidence.
5. **Blockers stop the chain.** A subagent that hits a wall reports and stops rather than improvising. When it does, you stop too — surface it to the user instead of launching the next unit on top of a broken foundation.

## Procedure

Each unit runs the same three beats: **work → adversarial verify → act on the verdict.**

### 1. Decompose before delegating

Break the work into units that are each a **complete, verifiable deliverable** — something that ends with tests green and a commit, not "investigate X a bit". Order them by real dependency. Write the list down (plan file, ticket sequence, or a checklist in the durable record) and show it to the user before starting if they haven't already given you one.

A good unit: one ticket, one sub-issue, one file's worth of a mechanical sweep, one phase of a plan, one hypothesis to test. If a unit needs more than roughly a full context window, split it.

### 2. Gather the carry-forward context yourself

Before writing the prompt, the orchestrator — not the subagent — establishes what the next unit needs to know: what the previous unit actually produced (signatures, file paths, commit hashes), which environment traps apply, what is reserved. Doing this once in the main thread is cheap; making each fresh subagent rediscover it is exactly the waste this strategy exists to avoid.

Most of this arrives for free in the previous verifier's report (§4), which is precisely why the verifier is required to hand up a handoff surface. Read anything else selectively — never `cat` a large transcript or log into the main thread; parse it with a script and print only what you need.

### 3. Write a bespoke work prompt

Each prompt is written from scratch for its unit. Not a template fill, not "continue where the last one left off". A fresh context knows *nothing* — every one of these sections earns its place:

- **Where to work.** Absolute path to the repo/worktree. What it must NOT touch: other checkouts, the browser, Jira/Linear, `main`, files you are holding open, the device rig, ports.
- **Read first.** `AGENTS.md`, `CLAUDE.md`, the testing guide, the plan doc — named explicitly, with "in full" where it matters.
- **The spec, verbatim.** Paste the ticket or plan section as authoritative text. A paraphrased acceptance criterion is already drift. State plainly: *this is the authority; build every criterion and nothing beyond it.*
- **Carry-forward from the previous unit.** "PASGAI-190 is already committed as 2814427; `services/sharepoint_graph.py` now exposes `GraphSearchHit` and `search_hits(...)` — read it for exact signatures." This is the single highest-value paragraph in the prompt.
- **Operational traps.** The commands that actually work, the ones that look right and aren't, the known-failing baseline it should not try to fix, environment quirks. It cannot discover these cheaply and will waste half its context finding them.
- **Scope fence and non-goals.** What is deliberately out of scope, and what belongs to a later unit.
- **Definition of done.** Tests to run and the expected result, lint, `/modular-commits` (commit only its own files, tests green *before* committing), do not push.
- **Blocker protocol.** If the prescribed approach doesn't work, stop and report — do not improvise, especially anything that changes persisted data, deletes tests, or weakens an assertion. Out-of-scope bugs get reported, not fixed inline.
- **Notice that its work will be adversarially audited.** Say so plainly: a separate agent will attempt to disprove every claim, so unverified or partial claims will be caught.
- **The final-report contract.** Its last message is all that survives. Specify the shape: files changed; commit hashes and subjects; the exact test result line; lint result; one line per acceptance criterion naming the test that proves it; the public API/handoff surface the next unit will consume; deviations and open concerns.

Use `general-purpose` for work that mutates the repo, `Explore` for read-only investigation.

### 4. Verify in a separate adversarial subagent

When the worker reports, **do not read its diff and do not run its tests.** Launch one verifier subagent (`general-purpose` — it needs to run tests and mutate temporarily) whose job is to falsify the work. Its prompt:

- **Frame it as an audit, not a review.** "A previous agent claims to have completed the following. Your job is to disprove it. Assume the claims are overstated until the repository proves otherwise. A finding of 'everything checks out' is only credible if you show the evidence you used to try to break it."
- **Give it the spec verbatim** — the same authoritative ticket/plan text the worker got. The verdict is judged against the spec, never against the worker's summary.
- **Give it the worker's claims as a numbered list of assertions to falsify**, stripped of narrative. Not "the agent did a nice job on X" — "Claim 3: `search_hits()` applies the folder constraint in the KQL query, proven by `test_search_hits_scopes_by_path`."
- **Tell it what to actually do:** read the real diff (`git show`, `git diff <base>...HEAD`); re-run the full test command itself and quote the exact result line; confirm no files were touched outside the unit's scope and nothing reserved was modified; confirm no test was deleted, skipped, or weakened (`git diff` the test files specifically); and check that each acceptance criterion is proven by a test that would actually fail if the behavior regressed.
- **Mandate mutation-verification** for anything correctness- or data-critical: break the implementation, confirm the named test goes red, restore it. Then require it to prove the tree is clean — `git status --porcelain` and `git diff` empty at the end, matching what it found at the start. The verifier must never leave a change behind or create a commit.
- **Look for the classic dodges:** a test asserting on a value the test itself supplied; an assertion loosened to make it pass; a criterion "met" by a test that never exercises the new path; work committed with tests red; scope creep committed alongside.
- **The verdict contract.** Its last message is all you will see, so specify it exactly: an overall `PASS` / `FAIL` / `PASS WITH CONCERNS`; a per-claim line marked `CONFIRMED` / `REFUTED` / `UNPROVEN` with the one-line evidence for each; the exact test-suite and lint result lines it observed itself; the commit hashes it verified; **the handoff surface the next unit needs** (public signatures, file paths, anything the next worker must build on); and any out-of-scope defects it noticed, described but not fixed.

The verifier is a fresh context that never saw the worker's reasoning — that independence is the whole value. Never reuse the worker agent, never continue it via `SendMessage` to "double-check", and never soften the framing to "confirm this looks right".

### 5. Act on the verdict

The orchestrator now works from the verdict alone:

- **PASS** — check the box, update the durable record (ticket state, checklist, plan file), note the handoff surface for the next unit, and go to §2 for the next one.
- **PASS WITH CONCERNS** — record the concerns in the durable record. File genuinely out-of-scope defects as their own tickets rather than fixing them inline.
- **FAIL** — do not fix it yourself. Compose a remediation work prompt (§3) carrying the verifier's refuted claims **verbatim** as the spec for what must change, then verify that remediation with a fresh verifier. **If a unit fails verification twice, stop and surface it to the user** — two failed rounds means the plan is wrong, not the execution, and grinding on it unattended wastes the night.

If a subagent was killed or crashed, its transcript still exists at `~/.claude/projects/<project>/<session-id>/subagents/agent-*.jsonl`. Mine it (selectively, with a script, or by delegating the mining) before redoing the work.

### 6. Report at boundaries

At natural chunk boundaries — a parent ticket done, a phase complete — post the short status the project convention calls for and give the user a brief progress note: what shipped and its verification state. Keep it to that; the commits, tickets, and verdicts carry the detail.

## Working unattended

This strategy is what makes overnight and multi-hour runs viable. When the user says they can't intervene: keep the loop going unit by unit, keep the durable record current after *every* verdict (not at the end), and reserve stopping for a genuine blocker, a second failed verification, or something needing a human decision or physical action. On stopping, leave the record in a state a fresh session can resume from.

## Anti-patterns

- Launching two subagents "since these are independent" — that is a different strategy; this one is serial by definition. Read-only fan-out for a broad search is a separate call the user makes explicitly.
- Reading the diff or re-running the tests in the main thread. That is the verifier's job, and doing it yourself is how the orchestration context dies at 60% through the task list.
- Skipping the verifier on "small" or "obviously fine" units. The cheap ones cost one short subagent; the expensive miss costs a night.
- Asking the verifier to "confirm" rather than to falsify, or handing it the worker's summary instead of the spec.
- Letting the worker verify itself, or continuing the worker agent to audit its own output.
- Doing the unit yourself in the main thread because delegating feels like overhead. The overhead is the point.
- A prompt that restates a plan which exists nowhere else.
- Summarizing a spec into the prompt instead of pasting it.
- Checking the box off a worker's report rather than a verifier's verdict.
