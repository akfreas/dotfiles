---
name: stack-github-prs
description: >-
  Create, grow, update and merge stacked pull requests using GitHub's native
  stacking (the `gh stack` CLI extension), so dependent PRs are linked by
  GitHub itself — each PR based on the branch below it, a stack map in every
  PR header, and bottom-up atomic merges — instead of being "linked" by
  mentioning other PR numbers in descriptions. Use when the user asks to
  "stack PRs", "make a stacked PR", "put this on top of #123", "add a PR to the
  stack", "link these PRs into a stack", "rebase / sync the stack", or "merge
  the stack", or whenever work is being split into PRs that genuinely depend
  on each other.
---

# Stack GitHub PRs (native stacking)

A stack is a chain of PRs where each PR's base is the head branch of the PR below it: `main ← A ← B ← C`. GitHub has a native feature for this: it records the stack as an object, shows a stack icon and stack map in each PR header, lets reviewers jump between layers, shows each layer's diff only, and merges the stack bottom-up atomically. This skill drives that feature through the `gh stack` CLI extension.

Reference docs: [Creating stacked pull requests](https://docs.github.com/en/pull-requests/how-tos/create-pull-requests/creating-stacked-pull-requests) and [Stacked PRs CLI commands](https://docs.github.com/en/pull-requests/reference/stacked-prs-cli-commands). `gh stack <command> --help` is authoritative for flags on the installed version.

## The anti-pattern this skill exists to prevent

**Do not "link" PRs by mentioning them in each other.** Opening PRs independently and then writing "Depends on #41", "Stacked on top of #41", "Part 2 of 3: #41 → #42 → #43" in descriptions or comments is not a stack. GitHub doesn't know the PRs are related: there's no stack map, no correct per-layer diff if the bases are wrong, no atomic bottom-up merge, no automatic retargeting when the bottom merges, and the prose goes stale the moment the stack changes.

Rules that follow from this:

- The **only** linking mechanism is the native stack (`gh stack init`/`add`/`submit`, `gh stack link`, or **Create stack** on GitHub.com). Never substitute PR-body text, comments, or task lists for it.
- PR bodies describe **that layer's change only**. Don't add "Depends on #N" lines, stack tables, or navigation lists of sibling PRs; the stack map in the header already shows them and stays correct.
- Setting each PR's `--base` to the branch below is necessary but **not sufficient**. A chain of based PRs with no stack object is still unlinked; register it as a stack.
- If native stacking is unavailable (see pre-flight), **stop and tell the user why**. Do not fall back to mention-linking.

## When to stack (and when not to)

Stack only when a layer genuinely depends on the one below it: it won't compile, or its change is meaningless without the lower layer's new type, interface, migration, or infra. Changes that are merely related, or that touch the same files without depending on each other, should be **independent PRs off the base**: they review and merge in any order. Don't link independent PRs into a stack; that just serializes their merge order. If the work is one big branch that needs carving into PRs first, use `split-branch-into-prs`, which hands its stacked chains to this skill's linking step.

## Pre-flight (read-only; abort and report on failure)

1. `gh auth status` — authenticated.
2. `gh extension list | grep gh-stack` — if missing, `gh extension install github/gh-stack` (needs gh 2.0+, git 2.36+).
3. The repo is on GitHub.com and **every branch in the stack lives in the same repository**. Cross-fork stacks are not supported; if the user works from a fork, say so and stop.
4. Resolve the trunk: the repo's default branch unless the user names another (pass it as `--base`).
5. `git status --porcelain` — a clean working tree. `gh stack` won't stash for you, and `rebase`/`sync` refuse to touch dirty worktrees.
6. `gh stack view --short` — tells you whether the current branch is already in a tracked stack (exit code 2 means it isn't).

If any `gh stack` command exits **9**, stacked PRs are not enabled for this repository. Report that to the user (an admin has to enable it) and stop. Don't build a mention-linked chain instead.

## Non-interactive use (important for Claude)

`gh stack` has TUIs (`submit` editor, `modify`, `switch`, `checkout` picker, `sync` divergence prompt) that need a real terminal. From the Bash tool, assume no terminal:

- `gh stack submit` behaves as `--auto`: generated titles, and new PRs are created as **drafts unless you pass `--open`**. Pass `--open` unless the user asked for drafts, then fix titles/bodies with `gh pr edit` (see step 4).
- `gh stack merge` needs `--yes` plus an explicit method (`--squash` / `--merge` / `--rebase`), otherwise it uses the last-used method silently.
- `gh stack sync` **aborts on divergence** in a non-interactive terminal (exit 0, nothing pushed). Read its output; "Stack synced" vs "Branches synced" vs an abort message mean different things.
- `gh stack modify` and `gh stack switch` are interactive only. Ask the user to run them with `! gh stack modify` if a restructure is needed, or do the equivalent with `unstack` + `init` + `submit`.

## Workflow A — build a new stack from scratch

Use when the work hasn't been written yet, or is being written layer by layer now.

1. **Start the stack** from an up-to-date trunk: `gh stack init [--base <trunk>] <first-branch>`. This creates and checks out the first branch on top of trunk (and enables `git rerere`).
2. **Commit the layer.** Stage explicit paths and commit following `modular-commits`. Avoid `git add -A`/`.` and `gh stack add -A` — untracked cruft must not leak into a layer.
3. **Add the next layer** from the top of the stack: `gh stack add <next-branch>`. It must be run from the topmost branch; it creates the new branch on top of the current one and checks it out. Commit that layer's work. Repeat per layer.
4. **Push and open the PRs:** `gh stack submit --open`. This pushes every branch, opens a PR per branch with the base set to the branch below, and creates the stack object on GitHub. Then, for each PR, replace the auto-generated title/body with a real one using the `create-pr` conventions, scoped to that layer's diff (`git diff <parent>...<branch>`): `gh pr edit <n> --title … --body-file …`. No cross-PR references in the body (see the anti-pattern above).
5. **Verify** (see below).

## Workflow B — the branches (or PRs) already exist

Use when the branches were built by hand (e.g. by `split-branch-into-prs`), or the user has open PRs that should become a stack.

- **Link without local tracking** (preferred when the branches were carved manually or by another tool): `gh stack link [--base <trunk>] [--open] <bottom> <middle> <top>`. Arguments are bottom-first and may be branch names, PR numbers, or PR URLs. It pushes branches, opens missing PRs with chained bases, corrects wrong bases on existing PRs, and creates or extends the stack. It's additive: it never removes PRs from a stack.
- **Adopt with local tracking** (when the user wants to keep using `gh stack sync/rebase/view` from this checkout): `gh stack init [--base <trunk>] <bottom> <middle> <top>` adopts the existing branches in that order, then `gh stack submit --open`.
- **Grow an existing stack:** from the top branch of a tracked stack, `gh stack add <new-branch>`, commit, `gh stack submit --open`. For an untracked stack, `gh stack link <stack-number> <new-branch-or-pr> …` appends to the top (the stack number is the one shown in GitHub's stack UI or `gh stack view --json`).
- **GitHub.com UI equivalent** (if the user prefers the browser): open the next PR with its base set to the previous PR's branch and choose **Create stack**; for already-chained open PRs, accept the "turn into a stack" banner; to add to a stack, use the stack icon → **Add to stack** in any PR header.

## Updating a stack after changes

- **Edited a lower layer** (e.g. addressing review on the bottom PR): commit on that branch, then `gh stack rebase` (cascades every layer above onto its updated parent; `--upstack` limits it to the current branch and above), then `gh stack push` to force-with-lease the rewritten branches. Or use `gh stack sync`, which fetches, rebases, pushes atomically and re-links in one go.
- **Rebase conflict** (exit 3): resolve the listed files, `git add`, `gh stack rebase --continue`; or `gh stack rebase --abort` to restore every branch. `sync` restores all branches on conflict and tells you to run `gh stack rebase` yourself.
- **Trunk moved** (a lower PR was squash-merged into the target, or main was merged into it): use the `update-gh-stack-by-rebase` skill. `gh stack sync` can't drop pre-squash commits reliably and misses layers already broken on GitHub.
- These commands rewrite and force-push branches. That is expected for a stack, but confirm with the user first if anyone else pushes to these branches.

## Merging

Stacks merge **bottom-up**. `gh stack merge --yes --squash` (or `--merge`/`--rebase`) merges the whole stack atomically: all or nothing. `gh stack merge <pr-number> --yes --squash` merges everything up to and including that PR. Branch protection and rules still apply and can't be bypassed; with a merge queue the stack is enqueued instead. Merging is outward-facing and irreversible: only do it when the user asked. Afterwards, `gh stack sync --prune` updates local state and deletes the merged branches.

## Verify

Don't report success until GitHub shows a real stack:

- `gh stack view --json` (tracked stacks) lists every branch in the expected bottom-to-top order with its PR.
- For each PR, `gh pr view <n> --json baseRefName,headRefName,isDraft,url`: the bottom PR's base is the trunk, every other PR's base is the head branch of the PR directly below, and draft state matches what the user asked for.
- Each PR's diff contains only its own layer (`gh pr diff <n> --name-only` doesn't include files from layers below).
- No PR body or comment you wrote contains "Depends on #", "Stacked on #", or a list of sibling PRs.

## Report

Give the user the stack bottom-to-top: position, PR number + URL, branch, base, draft/ready. Name the trunk. Say how it was linked (`submit`, `link`, or `init` + `submit`) and whether local tracking exists. If something blocked native stacking (exit 9, forks, missing extension), say so plainly and that no PRs were mention-linked as a substitute.
