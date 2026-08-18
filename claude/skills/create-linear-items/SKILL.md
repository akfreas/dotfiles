---
name: create-linear-items
description: Create a Linear project and/or a set of tickets from a plan, feature idea, or bug report — investigated against the codebase, researched where knowledge is missing, structured with parents/subtasks/dependencies, and always associated to a project. Use when the user invokes /create-linear-items, asks to "create tickets", "break this plan into Linear issues", "make a Linear project for X", or "add tickets to <project>".
---

# Create Linear items

Turn a plan (usually a doc in the repo), a feature description, or a bug into well-formed Linear work items. Two modes, chosen by context:

- **New project mode:** the work doesn't belong to any existing project → create a project, fill its summary + description, then create the tickets inside it.
- **Existing project mode:** the user mentions or links a project → add tickets to it, then post a project comment listing what was added and the suggested sequence.

**ALL WORK MUST BE ASSOCIATED TO A PROJECT UP THE CHAIN.** Never create an orphan ticket. If no project is mentioned and none is clearly implied, either find the right one (`list_projects`, ask if ambiguous) or create one. Sub-issues inherit association through their parent, but set the project on every issue you create anyway.

## Workflow

Run phases 1–3 before writing a single ticket. The quality of the tickets is decided here, not in the prose.

### 1. Resolve the target

- Identify the team (`list_teams`) and project. For an existing project, `get_project` to read its current description and scope.
- Pitfall: `list_issues` filtered by project **slug** can return empty — use the project **UUID** from `get_project`.
- List the project's existing issues. **Add, don't modify:** never edit or close pre-existing issues unless explicitly asked. If a planned ticket overlaps an existing issue, do not silently link it — flag the overlap in your final summary for the user to resolve.
- Check the repo's `AGENTS.md`/`CLAUDE.md` for ticket-writing conventions; repo-specific rules override this skill's defaults where they conflict.

### 2. Investigate the codebase

Every ticket must be anchored in what actually exists. Before writing:

- Read the source plan/doc end-to-end if one is given.
- Deeply read the files the work will touch — not just grep hits. Understand the existing patterns (concurrency model, error handling, test fixtures) so tickets can say "follow the pattern at `path:line`" instead of inventing one.
- Verify every `path:line` reference you plan to cite. A wrong anchor is worse than none — an LLM executor will trust it.
- Identify existing test files/targets and the exact command to run them, so test plans are executable as written.

### 3. Research knowledge gaps

If the task involves external APIs, platform behavior, third-party libraries, or anything you're not certain of, invoke `/perplexity-research` (tool: `mcp__perplexity-mcp__perplexity_search_web`) before writing the affected tickets. Put the relevant source links directly in the ticket that needs them (a `## References` section or inline). Don't research what the codebase already answers.

### 4. Design the breakdown

- **One parent issue per chunk of work**, sequenced the way the source plan sequences them.
- **Subtasks only when there are ≥2.** A chunk that would produce a single sub-issue gets the Steps/Acceptance criteria/Test plan sections inline on the parent instead.
- **No repeated information.** Each work item contains only information new at its level; a reader gets broader context from the parent (sub-issue → parent issue → project). Parent = problem/design/overall test plan/done-when. Sub-issue = steps/acceptance criteria/its test plan. Project = goal/benefits/sequence.
- **Dependencies are real Linear `blocked by` relations** (`blockedBy` on `save_issue`), between parents and between sub-issues. Also state the blocker in the description's first line ("Blocked by ENC-27.") so it survives copy/paste. Identify what is genuinely parallel — don't fabricate a linear chain.
- **Every item carries an automated test plan**: exact test file path, named test functions with one-line intent, and the run command. No ticket ships on manual verification alone. If work persists a format (file layout, hash, serialization), require committed golden vectors with a "do not regenerate — revert instead" note.
- **Labels:** fetch existing workspace labels (`list_issue_labels`) and assign the best fit (engineering/design/bug/research/etc.). Use existing labels only — never create new ones; leave unlabeled and mention it in the summary if nothing fits.
- **Titles:** imperative and outcome-focused ("Implement readStamp/writeStamp with modification-date preservation"), no session codenames or numbering the reader can't decode.
- **Explicit non-goals** on every parent ("no call sites changed yet", "iCloud stamping is a later chunk") — this is what keeps an LLM executor from scope-creeping.
- Defaults: state Backlog; no priority, estimate, assignee, or due date unless asked. No enforced size rule — let the plan's natural chunking decide granularity.

### 5. Create everything in one pass

No mid-run approval checkpoints — create the full set, then report. Order of operations:

1. New project mode: `save_project` with name, `summary` (one sentence, ≤255 chars: what + why it matters), and description (template below).
2. Parent issues (batch independent `save_issue` calls in parallel; you need their IDs before subs).
3. Sub-issues with `parentId` (batch in parallel across parents; within a parent, a sub that is `blockedBy` a sibling needs that sibling's ID first).
4. Relations that couldn't be set at creation time (`blockedBy` is append-only — safe to add in a second pass).
5. Existing project mode: `save_comment` with `projectId` — list the created ticket IDs with one-line descriptions and the suggested execution sequence (what's parallel, what blocks what). If the tickets change the project's scope or sequence, also update the project description's "Sequence of work" section.

### 6. Report

End with: every created item as `ID — title` with links, the dependency graph in one glance (chains and parallel tracks), overlaps with pre-existing issues you flagged, items left unlabeled, and any judgment calls you made that the user may want to reverse.

## Templates

Linear descriptions are Markdown; write literal newlines, never `\n` escapes. Bare issue identifiers like `ENC-26` auto-link — use them freely.

### Project description

```markdown
## Goal

<What this project achieves in user/system terms, and the core mechanism. Link the source plan doc (repo path or GitHub URL).>

## Why <the approach> / Benefits

<Bulleted: why this design, what it buys, what breaks without it.>

## Sequence of work

<Numbered list of parent tickets: ID — title (blockers), sub-issue IDs. State what can run in parallel.>

## Out of scope (later projects)

<Deferred work, so nobody "helpfully" does it early.>
```

### Parent issue

```markdown
<One paragraph: which plan/phase this belongs to, plan-doc link. First line names blockers if any.>

## Problem

<Why this work exists — the failure mode or gap. Omit if fully covered by the project description; don't restate it.>

## Design

<Approach: new/modified files with exact paths, API signatures, key semantics to preserve. Cite existing code as path:line where it anchors a decision.>

## Automated test plan

<Test files with exact paths; behaviors to cover. Summary level — named test functions live on the sub-issues.>

## Done when

<Closable conditions: sub-issues done, tests green in CI, non-goals restated.>
```

### Sub-issue

```markdown
<First line: "Blocked by <ID>." if applicable. One paragraph of scope: what this delivers and must not touch. Context lives in the parent — add only what's new here.>

## Steps

<Numbered, concrete: exact paths, signatures, snippets where shape matters, existing patterns as path:line.>

## Acceptance criteria

<Observable outcomes — behavior, invariants, things that must NOT change.>

## Automated test plan

<Exact test file path, named test functions with one-line assertions, run command (e.g. `swift test --filter KeyFingerprintTests`).>

## References

<Only if research was needed: links that fill the knowledge gap.>
```

### Single-task ticket (no subtasks)

Parent template + the sub-issue's Steps/Acceptance criteria/named-test-functions sections merged in. Note in the first paragraph that it's executable as a single issue.

## Linear MCP mechanics

- `save_issue` creates when `id` is omitted; `team` + `title` required on create. Set `project` explicitly on every issue.
- `parentId` makes a sub-issue; `blockedBy`/`blocks`/`relatedTo` are append-only arrays and accept identifiers like `ENC-27`.
- To cancel a mistaken creation: set `state: "Canceled"` and rewrite the description to say why and where the content went (there is no delete).
- `save_comment` with `projectId` starts a top-level project discussion thread.
- Batch independent creates in parallel; anything needing another item's ID waits for it.
