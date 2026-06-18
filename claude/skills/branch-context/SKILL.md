---
name: branch-context
description: >-
  Reconstruct what the current branch is about by reading the commit log between
  HEAD and a base branch (default `main`), the diff stat, and the PR description
  and review comments if a PR exists. Read-only and context-cheap by design: it
  reads commit subjects/bodies and the file-level shape of the diff, not the diff
  content itself, and does not rely on chat transcripts. Use at the start of work
  on an existing branch, or whenever the user asks "what are we working on", "what
  is this branch", "catch up on this branch", or "get context before we continue".
---

# Branch Context

Use this skill to orient yourself on an existing branch before doing work on it. It answers one question — *what was being done between this branch and its base?* — from the git history and the PR, never from prior chat transcripts (which may belong to a different branch).

The design priority is **signal per token**. The cheap tier reads commit messages and the *shape* of the diff (which files changed, by how much), not the diff content. That is almost always enough to understand the intent of a branch. Reading actual diff hunks is an escalation that requires the user's go-ahead, because it can blow up the context window.

## When to use

Trigger phrasings include:
- "check the commit log between HEAD and main to get context"
- "what are we working on in this branch?"
- "catch me up on this branch" / "get context before we continue"
- "what does this branch do?" / "what's the PR about?"

Do **not** use this to review code quality, find bugs, or summarize a diff line-by-line — that is `/code-review`'s job and needs the actual diff.

## Argument handling — the base branch

The skill compares HEAD against a base ref. Default base is **`main`**.

- No argument → base is `main`.
- An argument names the base (`develop`, `origin/main`, `upstream/release-2.4`, a commit hash) → use it.
- Prefer the remote-tracking form when it exists: if `git rev-parse --verify origin/<base>` succeeds, use `origin/<base>` (it is usually fresher than the local branch). Otherwise fall back to the local `<base>`. State which you used in your first line of output so the user can correct you.

This skill is **read-only and does not `git fetch`**. The comparison reflects whatever local state exists. If `origin/<base>` looks stale and accuracy matters, tell the user they can `git fetch origin <base>` themselves and re-invoke — do not fetch on their behalf.

## Read-only contract

Every command in this skill is a read. No `fetch`, `pull`, `merge`, `rebase`, `checkout`, `commit`, `push`, or file edits. If the procedure ever seems to need a write, stop and report instead.

## Procedure

### 1. Resolve base and branch (parallel, read-only)

Run together:

- `git rev-parse --abbrev-ref HEAD` — current branch name (`HEAD` if detached).
- `git rev-parse --verify origin/<base>` and `git rev-parse --verify <base>` — pick the base ref per **Argument handling**.
- `git merge-base --is-ancestor <base> HEAD; echo $?` — sanity that the branch descends from the base.

Handle these cases before going further:

- **On the base branch** (current branch resolves to the same ref as the base, or `<base>..HEAD` is empty) → there is nothing branch-specific to summarize. Say so and stop; offer to summarize recent commits on the base instead if the user wants.
- **Base ref does not resolve** → report it and ask the user for the correct base. Do not guess a different branch.
- **Detached HEAD** → proceed; just note the branch name is unavailable and rely on commits + PR.

The branch name itself is context — if it encodes a ticket or feature slug (e.g. `feature/PASG-123-zoom-gesture`), note it.

### 2. Gather the cheap tier (parallel, read-only)

Run together:

- `git log <base>..HEAD --no-merges --pretty=format:'%h %s%n%b' --abbrev-commit` — the commit subjects **and bodies** for commits on this branch only. This is the primary signal; bodies often carry the "why."
- `git diff <base>...HEAD --stat` — the file-level **shape** of the change: which files and directories were touched and by how much. The triple-dot `...` compares against the merge-base, so it excludes work the base picked up independently. Do **not** read the diff content — the stat is enough to see the center of gravity (the files with the largest churn are usually the heart of the work).
- `git log <base>..HEAD --no-merges --format='%an' | sort -u` — authors, cheaply, in case the branch is shared.

If `<base>..HEAD` is large (say >40 commits), don't dump it all — read the most recent ~25 and the stat, and note that the branch is long.

### 3. Check for a PR

A PR may not exist yet — always check, never assume.

- `gh pr view --json number,title,body,state,url,headRefName,reviewDecision` — the PR for the current branch.
  - If it errors with "no pull requests found" (or `gh` isn't installed / there's no GitHub remote) → there is no PR yet (or no GitHub). Say so plainly and continue with git-only context. Do not treat this as a failure.
  - If it returns a PR → its **title and body are first-class context**; weight them alongside the commits. The body often states intent more clearly than any single commit.

Then read the review conversation:

- `gh pr view --comments` — the PR's comment and review threads. Skim for decisions, requested changes, and open questions that explain *why* the branch looks the way it does or what is still unresolved. Only do this when a PR exists.

### 4. Synthesize a briefing

Produce a tight summary for the user (a handful of lines, not a wall of text):

- **What this branch does** — one or two sentences, drawn from the commits + PR, in plain language.
- **Where the work lives** — the main files/areas touched, from the diff stat (name the directories/symbols, not every file).
- **Branch state** — commit count ahead of base, PR status (none / open / draft / merged) and its review decision if any, plus any unresolved threads worth knowing.
- **Open threads / caveats** — anything the commits or PR comments flag as incomplete, plus a note if the base ref might be stale (no fetch was run).

Keep it honest: if the commits are a grab-bag with no single coherent story, say that rather than inventing one. If the picture is still fuzzy after the cheap tier, go to step 5 — do not paper over the gap.

### 5. Escalation — reading actual diffs (ask first)

The cheap tier is usually sufficient. When it is **not** — a commit subject is opaque, the intent of a heavily-churned file is unclear, or the user needs deeper detail — reading real diff content is the next step, but it can be expensive. **Ask the user before reading any diff hunks.**

When asking, be specific about scope so the cost is bounded: name the one or two commits or files you'd read (e.g. "read the diff of `CameraView.swift` from commit `a1b2c3d`?"), not "read the whole diff." Once approved:

- Prefer the narrowest read that answers the question: `git show <hash> -- <path>` for a single file in a single commit, or `git diff <base>...HEAD -- <path>` for one file across the branch.
- Never read the entire `git diff <base>...HEAD` unless the user explicitly asks for it — that is what risks the context window.

## Edge cases

- **No commits ahead of base** → branch matches base; nothing to summarize. Report and stop.
- **`gh` absent or not a GitHub repo** → skip the PR steps, say so, deliver git-only context.
- **Stale local base** → comparison may include commits already merged upstream; note that no fetch was run and the user can refresh and re-invoke.
- **Huge branch** → cap the commit log read and say you capped it; lead with the diff stat for shape.
- **Merge commits in the log** → excluded via `--no-merges`; they rarely carry branch intent.

## Anti-patterns

- Reading `git diff <base>...HEAD` (full content) up front "to be thorough." That is exactly the context blow-up this skill avoids. Stat first; hunks only on request.
- Using chat transcripts or memory to describe the branch. The whole point is to derive context from the branch's own history, which may be unrelated to the current conversation.
- Assuming a PR exists, or treating "no PR found" as an error. Absence of a PR is a normal, expected outcome — report it and move on.
- Fetching, pulling, or otherwise mutating state to get a "cleaner" comparison. Read-only, always; the user refreshes refs themselves.
- Inventing a tidy narrative for a branch whose commits don't have one. Report the mess accurately.
- Escalating to diff hunks silently. Always ask, and always scope the request to specific commits/files.

## Quick checklist

- [ ] Base resolved (default `main`, `origin/<base>` preferred when present); said which was used; no fetch
- [ ] Handled on-base / detached / unresolved-base before gathering
- [ ] Cheap tier only: commit subjects+bodies, diff `--stat`, authors — no diff content
- [ ] PR checked; absence reported as normal; description + review comments read when present
- [ ] Briefing covers what / where / state / open threads, honestly
- [ ] Any diff-hunk read was asked-for and scoped to named commits/files
