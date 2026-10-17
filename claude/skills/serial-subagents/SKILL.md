---
name: serial-subagents
description: >-
  Execute a long-horizon, multi-step task by delegating it to subagents one at a time, strictly
  serially — the orchestrator keeps a durable checklist, hands each subagent a bespoke prompt
  carrying exactly the context it needs, then acts on the report before moving to the next unit.
  The main thread holds orchestration only: no diffs, no test output, no file reads. The point is
  context isolation and a fresh context per unit of work, NOT parallelism. Use when the user says
  "use a subagent for each task", "one subagent at a time", "don't blow up the context", "work
  overnight on this", "delegate each one by one", or hands over a long task list / plan / ticket
  sequence that will not fit in one context window.
---

# Serial Subagents

One subagent alive at a time: do the work, report, move on.

The goal is **context containment**, not speed. Each unit of work gets a fresh, uncluttered context window sized to exactly that unit; the main thread stays small enough to run the whole job to completion without compaction. Fanning out concurrently defeats this — it floods the main thread with interleaved reports.

The orchestrator's context is a **ledger, not a workspace**. It holds the checklist, the reports, and the handoff notes between units. Diffs, test output, log files, and source reads belong in subagent contexts and must never be pulled into the main thread.

## Non-negotiable rules

1. **Exactly one subagent running at a time.** Never launch the next before the current one has reported. Never batch two units into one agent because "it's in the same file anyway".
2. **The plan lives on disk, not in your context.** Before delegating anything, the checklist exists as a durable artifact — a plan file, a ticket, a scratchpad markdown. If the session died right now, a fresh context must be able to pick up from that artifact alone. If you find yourself writing a long plan *into* a subagent prompt, that plan belongs in the durable record first; point the subagent at it.
3. **You own state; subagents own work.** Ticket states, checklist updates, cross-task decisions, branch/PR management, and anything the user must be told belong to the orchestrator. Subagents implement, test, and commit their own scope — nothing else.
4. **Blockers stop the chain.** A subagent that hits a wall reports and stops rather than improvising. When it does, you stop too — surface it to the user instead of launching the next unit on top of a broken foundation.
5. **All commits go through `/modular-commits`.** Every subagent MUST use the `modular-commits` skill for committing. No exceptions — not `git commit`, not a one-liner shortcut, not "it's just one file". The subagent prompt MUST explicitly instruct: "Commit exclusively via `/modular-commits` — never run `git commit` directly." If a subagent's report shows commits that were not made through the skill, treat it as a failed unit and redo it.

## Procedure

### 1. Decompose before delegating

Break the work into units that are each a **complete, verifiable deliverable** — something that ends with tests green and a commit, not "investigate X a bit". Order them by real dependency. Write the list down (plan file, ticket sequence, or a checklist in the durable record) and show it to the user before starting if they haven't already given you one.

A good unit: one ticket, one sub-issue, one file's worth of a mechanical sweep, one phase of a plan, one hypothesis to test. If a unit needs more than roughly a full context window, split it.

### 2. Gather the carry-forward context yourself

Before writing the prompt, the orchestrator — not the subagent — establishes what the next unit needs to know: what the previous unit actually produced (signatures, file paths, commit hashes), which environment traps apply, what is reserved. Doing this once in the main thread is cheap; making each fresh subagent rediscover it is exactly the waste this strategy exists to avoid.

Most of this arrives for free in the previous subagent's report, which is why the final-report contract matters. Read anything else selectively — never `cat` a large transcript or log into the main thread; parse it with a script and print only what you need.

### 3. Write a bespoke work prompt

Each prompt is written from scratch for its unit. Not a template fill, not "continue where the last one left off". A fresh context knows *nothing* — every one of these sections earns its place:

- **Where to work.** Absolute path to the repo/worktree. What it must NOT touch: other checkouts, the browser, Jira/Linear, `main`, files you are holding open, the device rig, ports.
- **Read first.** `AGENTS.md`, `CLAUDE.md`, the testing guide, the plan doc — named explicitly, with "in full" where it matters.
- **The spec, verbatim.** Paste the ticket or plan section as authoritative text. A paraphrased acceptance criterion is already drift. State plainly: *this is the authority; build every criterion and nothing beyond it.*
- **Carry-forward from the previous unit.** "PASGAI-190 is already committed as 2814427; `services/sharepoint_graph.py` now exposes `GraphSearchHit` and `search_hits(...)` — read it for exact signatures." This is the single highest-value paragraph in the prompt.
- **Operational traps.** The commands that actually work, the ones that look right and aren't, the known-failing baseline it should not try to fix, environment quirks. It cannot discover these cheaply and will waste half its context finding them.
- **Scope fence and non-goals.** What is deliberately out of scope, and what belongs to a later unit.
- **Definition of done.** Tests to run and the expected result, lint, and — **mandatory** — commit exclusively via `/modular-commits` (invoke the skill, do not run `git commit` directly; commit only its own files; tests green *before* committing), do not push.
- **Blocker protocol.** If the prescribed approach doesn't work, stop and report — do not improvise, especially anything that changes persisted data, deletes tests, or weakens an assertion. Out-of-scope bugs get reported, not fixed inline.
- **The final-report contract.** Its last message is all that survives. Specify the shape: files changed; commit hashes and subjects; the exact test result line; lint result; one line per acceptance criterion naming the test that proves it; the public API/handoff surface the next unit will consume; deviations and open concerns.

Use `general-purpose` for work that mutates the repo, `Explore` for read-only investigation.

### 4. Act on the report

When the subagent reports:

- **Success** — check the box, update the durable record (ticket state, checklist, plan file), note the handoff surface for the next unit, and go to §2 for the next one.
- **Partial success / concerns** — record the concerns in the durable record. File genuinely out-of-scope defects as their own tickets rather than fixing them inline. Decide whether the next unit can proceed or whether the concern must be resolved first.
- **Blocker** — do not fix it yourself. Either compose a remediation work prompt (§3) for a fresh subagent or surface it to the user. **If a unit fails twice, stop and surface it to the user** — two failed rounds means the plan is wrong, not the execution.

If a subagent was killed or crashed, its transcript still exists at `~/.claude/projects/<project>/<session-id>/subagents/agent-*.jsonl`. Mine it (selectively, with a script, or by delegating the mining) before redoing the work.

### 5. Report at boundaries

At natural chunk boundaries — a parent ticket done, a phase complete — post the short status the project convention calls for and give the user a brief progress note: what shipped and its state. Keep it to that; the commits, tickets, and reports carry the detail.

## Working unattended

This strategy is what makes overnight and multi-hour runs viable. When the user says they can't intervene: keep the loop going unit by unit, keep the durable record current after *every* report (not at the end), and reserve stopping for a genuine blocker, a second failed attempt, or something needing a human decision or physical action. On stopping, leave the record in a state a fresh session can resume from.

## Anti-patterns

- Launching two subagents "since these are independent" — that is a different strategy; this one is serial by definition. Read-only fan-out for a broad search is a separate call the user makes explicitly.
- Reading the diff or re-running the tests in the main thread. That is the subagent's job, and doing it yourself is how the orchestration context dies at 60% through the task list.
- Doing the unit yourself in the main thread because delegating feels like overhead. The overhead is the point.
- A prompt that restates a plan which exists nowhere else.
- Summarizing a spec into the prompt instead of pasting it.
