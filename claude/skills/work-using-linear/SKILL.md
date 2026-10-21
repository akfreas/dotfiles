---
name: work-using-linear
description: >-
  Execute a Linear project or ticket end-to-end the "Linear way": derive
  execution order from the project description, run a read-only preflight
  that checks whether each ticket is already done, has drifted from the code,
  or duplicates other tickets (comment and ask before proceeding if so), work tickets and sub-issues
  strictly sequentially while respecting blocked-by relations, keep every
  issue's state accurate in Linear as the single source of truth, commit per
  sub-issue via /modular-commits with the ticket ID in the commit body, comment
  the session ID, session link and hostname on each code-complete issue, post a
  brief project update with a session link after each chunk, and on any
  blocker or ambiguity comment on the issue, tag Alex Freas, and STOP. Invoke
  when the user provides a Linear project or ticket ID/URL and asks to work
  on, execute, or implement it.
---

# Work Using Linear

Execute a Linear project (or a single ticket and its sub-issues) with Linear as the single source of truth. Anyone looking only at Linear — issue states, comments, project updates — must be able to tell exactly what has been done, what is in progress, and what is left, without reading the chat transcript.

## Non-negotiable rules

1. **Sequential, never parallel.** One ticket at a time, one sub-issue at a time, in dependency order. Do not fan out subagents to work multiple tickets concurrently, and do not start ticket N+1 before ticket N is done, tested, committed, and marked Done.
2. **Linear state is updated in real time.** Mark an issue In Progress the moment work on it starts, Done the moment it is finished — never batch state changes at the end. A parent issue becomes Done only after all its sub-issues are Done.
3. **Tests gate progress.** Run the ticket's automated test plan (or the nearest equivalent) before marking it Done, and fix failures before moving on. At chunk boundaries (a parent issue completed), run the full test suite of the affected package/target.
4. **Blockers stop the work.** If anything is ambiguous, contradictory, or broken in a way the ticket didn't anticipate: write a comment on the issue describing the blocker, tag Alex Freas so he is notified, and STOP working entirely. Do not power through on a guessed or degraded implementation — a human in the loop beats momentum.
5. **Preflight before any work.** Run the read-only preflight (§2) before touching code. If it finds the ticket already done, obsolete, wildly out of date, or duplicated, comment and ask the user before proceeding.

## Procedure

### 1. Orient from the project down

- Resolve the input: a project URL/name → `mcp__linear-server__get_project`; an issue ID (e.g. `ENC-32`) → `mcp__linear-server__get_issue`, then fetch its project and siblings if it has any.
- Read the **project description first** — it usually contains a "Sequence of work" or equivalent narrative plus links to a plan document. That narrative is the primary ordering signal. If it references a plan doc in the repo, read it (check other branches with `git log --all` if it isn't on the current branch).
- List all project issues (`mcp__linear-server__list_issues` with the project) and fetch **full descriptions** with `get_issue` — list output truncates them. Map the structure: parent issues (chunks), their sub-issues (executable pieces), and blocked-by relations, which also appear as "Blocked by …" in the first line of sub-issue descriptions. Skip issues in Canceled state.
- Derive the execution order: project narrative order for chunks; within a chunk, dependency order for sub-issues; a chunk that is "parallel-safe" per the description is still executed sequentially, in narrative order.
- Tickets follow a template (Steps / Acceptance criteria / Automated test plan). Treat those sections as the spec: exact file paths, function signatures, named test functions, and the command to run them.

### 2. Preflight: is this ticket still worth doing?

Before any work begins, investigate every ticket in scope against the current codebase and Linear. This step is **read-only**: no file edits, no branches, no commits, no Linear state changes. The only write allowed is the preflight comment described below. Run `git fetch origin` first so the investigation sees the latest `origin/main`.

Check three things:

1. **Already done or partially done.** Search for earlier work: `git log --all --grep=<ticket ID>`, `git log --all -S <key symbol>` for the functions or types the ticket introduces, and `gh pr list --state all --search <ticket ID>`. Then read the code the ticket targets and check each acceptance criterion against `origin/main`: is it already met, partly met, or not met?
2. **Drift between the ticket and the code.** Verify every file path, symbol, `path:line` anchor, and API the ticket names still exists and behaves as described. For a bug, check whether the described condition can still happen in the current code. Note where the ticket's implementation plan no longer fits how the code is structured now.
3. **Duplicate and related tickets.** Search Linear with `mcp__linear-server__list_issues` using the ticket's key terms (title words, symbols, feature names), across every state including Done and Canceled, and read the ticket's existing relations. Look for tickets that are straight duplicates, that overlap in scope, or that already delivered part of this one.

**Write one preflight comment** with `mcp__linear-server__save_comment` on the ticket, or on the project when working a project. Additionally, when working a project, any individual ticket that hits a stop condition or has duplicates gets its own comment. Each comment is **one paragraph only**: no headings, no lists, no preamble. Lead with the verdict (proceed, already done, partially done, out of date, or duplicate), then give only the evidence that supports it: commit SHAs, PR numbers, file paths, ticket IDs. Three to five sentences at most.

**Then decide:**

- **Stop and ask** if the ticket has already been done, describes a condition that doesn't or couldn't exist anymore, or prescribes a plan wildly out of date with the code. Post the comment, then ask the user with `AskUserQuestion`: "Should I proceed?" followed by the concrete reasons to proceed and the reasons not to. Do not start work until the user answers.
- **Comment and ask** if there are related or duplicate tickets, pending or completed. The comment names those tickets and how they relate. Then ask the user with `AskUserQuestion` whether to proceed given that research.
- **Proceed** only if none of the above apply. Still post the comment so the reasoning is on record.

Minor drift (a moved line, a renamed helper) is not a stop condition: note it in the comment and follow the code as it is now.

### 3. Set up git

- Create one feature branch off `main` for the whole project, named after the project (or use the issue's `gitBranchName` when working a single ticket). If required context (e.g. the plan doc) exists only on another branch, cherry-pick that commit rather than rebasing onto that branch.
- Never push or open a PR unless the user asks.

### 4. Execute each sub-issue

For each sub-issue, in order:

1. Mark it In Progress (`mcp__linear-server__save_issue` with `state: In Progress`). Also mark the parent In Progress when its first sub-issue starts.
2. Read the referenced code before writing any — verify that cited `path:line` anchors still hold, and follow the existing patterns they point to. If the ticket's assumptions don't match reality (missing API, moved file, wrong line semantics), that is a blocker — see rule 4.
3. Implement exactly the ticket's scope. Respect explicit non-goals ("no stamping in this sub-issue", "no call sites changed yet"). Small mechanical deviations are fine; anything that changes the ticket's design is a blocker.
4. Run the ticket's test plan and fix failures. Persisted-format work gets golden vectors computed independently (e.g. a Python reference implementation) rather than generated from the code under test.
5. Commit via the `/modular-commits` skill, with one override to its defaults: put the ticket ID (e.g. `ENC-38`) in the commit's **extended description** (body, via a second `-m`), never in the subject line.
6. Post a provenance comment on the sub-issue (see below).
7. Mark the sub-issue Done.

A ticket worked without sub-issues follows the same steps, provenance comment included.

#### Provenance comment

Once an issue is code complete (implemented, tested, committed), comment on it with `mcp__linear-server__save_comment` recording where the work happened, so the session can be found and inspected later:

- **Session ID:** the value of `$CLAUDE_CODE_SESSION_ID`.
- **Session link:** the `https://claude.ai/code/session_…` URL from the harness environment, if one is available. If there isn't one, omit the line rather than inventing a URL.
- **Host:** the output of `hostname`. Transcripts only exist on the machine the session ran on, so this tells you which computer to look on.

Get the values in one command: `echo "$CLAUDE_CODE_SESSION_ID"; hostname`. Keep the comment to just these lines under a short heading such as `Code complete — provenance`, with real newlines in the body:

```
Code complete — provenance
Session: 554ca5f0-ab7d-4f1a-b461-f5d599aec4b8
Link: https://claude.ai/code/session_…
Host: Alex-F-MacBook-Pro.local
```

### 5. Close each chunk

When a parent issue's sub-issues are all Done:

- Run the full test suite for the affected package; fix anything broken before proceeding.
- Mark the parent Done.
- Post a **brief** project update via `mcp__linear-server__save_status_update` (type `project`, health `onTrack` unless something is off): 2–4 sentences on what the chunk delivered and its verification state, plus a link to this Claude Code session (the `https://claude.ai/code/session_…` URL from the harness environment; if unavailable, include the session ID). Do not restate ticket contents or list files — the commits and tickets carry the detail.

### 6. Blocker protocol

Triggers: ambiguous or contradictory ticket instructions; ticket references code that doesn't exist or behaves differently than described; a test that can't pass without deviating from the ticket's design; a discovered design flaw; missing access/credentials; anything where proceeding would mean guessing.

When triggered:

1. Write a comment on the affected issue with `mcp__linear-server__save_comment`: what was attempted, what blocked it, and the concrete question or decision needed. Use real newlines in the body, not `\n` escapes.
2. Tag Alex Freas so he is notified: look up his `displayName` via `mcp__linear-server__list_users` (query "Alex Freas"), then mention him in the comment body as `@<displayName>` — the mention format documented by `save_comment`. A plain-text name without the `@displayName` mention is not sufficient.
3. STOP. Do not continue to later tickets, do not implement a workaround, do not mark anything Done. Summarize the blocker to the user and end the turn. Committed work for already-completed sub-issues stays; half-done work for the blocked ticket stays uncommitted.

### 7. Wrap up

When every issue is Done: run the full suite once more, post a final short project update (same link rules), and report to the user — including anything that intentionally remains open (manual verification steps, review/merge).

## Anti-patterns

- Starting work before the preflight, or editing anything during it.
- A preflight comment longer than one paragraph, or padded with explanation.
- Implementing a ticket that is already done or obsolete without asking.
- Working two tickets "while I'm in the file anyway".
- Batch-updating Linear states after the code is done.
- Marking a parent Done while a sub-issue is open, or vice versa.
- Marking an issue Done without its provenance comment.
- Long, narrative project updates that duplicate ticket descriptions.
- Silently deviating from a ticket's design because the described approach didn't work — that's a blocker, not a judgment call.
- Continuing past a blocker on other tickets "to stay productive": downstream tickets usually depend on the blocked decision.
