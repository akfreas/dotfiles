---
name: work-using-linear-with-pr
description: >-
  Wraps work-using-linear and finishes with a pull request. Requires a Linear
  ticket or project, creates a dedicated branch and git worktree named after
  that ticket or project, updates the branch with main before any work begins,
  works the item step by step via work-using-linear with a /modular-commits
  commit at every boundary, pulls main again and resolves conflicts, then
  opens a PR with the create-pr skill. Invoke when the user provides a Linear ticket or project
  and asks to work it "with a PR", "and open a PR", or invokes
  /work-using-linear-with-pr.
---

# Work Using Linear — With PR

This skill layers a worktree and a pull request onto the `/work-using-linear` workflow. Invoke the `work-using-linear` skill and follow it — everything here builds on it. Where this skill says otherwise, this skill wins.

## Input is required

A Linear ticket (ID like `ENC-32` or an issue URL) or a Linear project (name or URL) **must** be provided. If neither was given, stop and ask the user for one — do not pick a ticket or project yourself, and do not start any work until you have it.

## Overrides to work-using-linear

1. **Work in a new branch inside a new git worktree** — this replaces work-using-linear §2 "Set up git". Never work in the main checkout.
2. **A PR is opened at the end** — this replaces work-using-linear's "never push or open a PR unless the user asks". Invoking this skill is that ask.

## 1. Create the branch and worktree

Resolve the ticket or project in Linear first (work-using-linear §1), then derive a slug that contains the ticket or project name:

- **Ticket:** use the issue's `gitBranchName` from Linear (it already contains the ticket ID and title, e.g. `enc-32-key-picker`). If it is missing, build `<ticket-id>-<short-title>` in lowercase kebab case, e.g. `enc-32-key-picker`.
- **Project:** the project name in lowercase kebab case, e.g. `secure-sharing-v2`.

Then, from the main checkout:

```bash
MAIN=$(git rev-parse --show-toplevel)
SLUG=<slug from above, with any "/" replaced by "-">
BRANCH=<gitBranchName for a ticket, or $SLUG for a project>
git -C "$MAIN" fetch origin
git -C "$MAIN" worktree add -b "$BRANCH" "$MAIN/../$(basename "$MAIN")-$SLUG" origin/main
```

Use the repository's default branch in place of `origin/main` if it is not `main`. If the branch or worktree already exists (a resumed run), reuse it instead of creating a new one: `git worktree list` shows where it is checked out.

`cd` into the worktree and do **all** remaining work there — every file edit, test run, and commit.

**Preflight: update the branch with `main` before any work begins.** This matters most for a reused branch, but run it every time:

```bash
git fetch origin
git merge origin/main
```

Merge rather than rebase, so a branch that was already pushed never needs a force-push. If the merge conflicts, resolve them as described in §3 and commit the merge before touching the first ticket. Then state the worktree path and branch name to the user and start work.

## 2. Work step by step

Follow work-using-linear §3–§5 exactly: one ticket and one sub-issue at a time, Linear states updated in real time, tests gating each step, and the blocker protocol on any ambiguity.

**Commit at every boundary via `/modular-commits`.** A boundary is each completed sub-issue, and each completed ticket that has no sub-issues. Never run `git commit` directly, and never let uncommitted work for a finished step carry into the next one. Keep work-using-linear's override: the ticket ID goes in the commit body, never the subject line.

If the blocker protocol fires, STOP as work-using-linear says — **do not open a PR** for partially completed work. Report the worktree path and branch alongside the blocker so the run can be resumed.

## 3. Open the PR

When every ticket in scope is Done and the final test run is green (work-using-linear §6):

1. Confirm the worktree is clean (`git status`) — everything is committed.
2. Pull `main` again: `git fetch origin && git merge origin/main`. If there are conflicts, resolve each one by reading both sides and keeping the intent of both `main`'s change and the ticket's change. If a conflict can't be resolved without guessing at that intent, treat it as a blocker (work-using-linear §5) and do not open the PR. After resolving, run the full test suite again and fix any failures. Then commit the merge with `git commit --no-edit`: this is the one commit that doesn't go through `/modular-commits`, because it records a merge rather than authored work. Fixes needed after the merge do go through `/modular-commits`.
3. From inside the worktree, invoke the `create-pr` skill. It pushes the branch and opens the PR with its own defaults; pass along any base branch, title, or draft preference the user gave.
4. Post the final Linear project update (work-using-linear §6) and include the PR URL in it. For a single ticket, also add a comment with the PR URL on the ticket.

## 4. Report

Tell the user: the PR URL, the branch, the worktree path, the tickets completed, and anything left open (manual verification, review/merge). Leave the worktree in place — the user removes it after the PR merges.

## Anti-patterns

- Starting work without a ticket or project from the user.
- Editing files or committing in the main checkout instead of the worktree.
- A branch or worktree name that doesn't contain the ticket or project name.
- Starting the first ticket on a branch that hasn't been updated with `main`.
- Opening the PR without pulling `main` again, or without rerunning tests after a merge that changed anything.
- One big commit at the end instead of one per boundary.
- Opening a PR after a blocker stopped the work.
