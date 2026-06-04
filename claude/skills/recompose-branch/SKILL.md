---
name: recompose-branch
description: >-
  Rewrite the current branch's history so the commits only describe the diff between
  the branch and its base (default origin/main), not the iteration that produced it.
  Soft-resets onto the base while preserving every working-tree change, then re-commits
  via the modular-commits procedure. Use when the user asks to recompose, restack,
  compact, tidy, clean up, flatten, or rewrite branch history — typically before
  opening or refreshing a PR.
---

# Recompose Branch History

Use this skill when the user wants the branch's commit history to read as "what is being applied" rather than "how we got here." It collapses the back-and-forth of an iterative branch into a small set of modular commits derived from the final diff against the base.

Triggers include phrasings like:
- "reset to origin/main and remake the commits"
- "recompose this branch"
- "rewrite history so the commits tell a clean story"
- "compact / restack / tidy the branch before the PR"
- "make /modular-commits from the branch diff"

## Allowed write operations — strict allowlist

This skill is intentionally narrow. The **only** write operations permitted are:

- `git branch pre-recompose/<current-branch> HEAD` — **single exception**, used exactly once per invocation to create the recovery branch. Any other use of `git branch` (rename, delete, force-update, different name) is banned.
- `git reset <base>` (mixed mode — the default — to move HEAD)
- `git commit …` (to recreate history)
- `git add <path>` (and `git add -p`) — only because it is the staging mechanism that `git commit` consumes; never `git add -A` / `git add .`

Every other write operation is **banned in this skill**, including (non-exhaustive):

- `git push` (any form, any remote, any flags)
- `git fetch` / `git pull` (no network writes to local refs)
- `git tag …` (no new refs other than the one allowed backup branch)
- `git branch …` for any purpose other than the single backup-branch creation above (no rename, no `-f`, no delete, no second backup in the same invocation)
- `git stash` / `git stash pop` (no surprise rescues of dirty state)
- `git rebase` / `git cherry-pick` / `git revert` / `git merge` / `git mv` / `git rm`
- `git checkout <branch>` / `git switch <branch>` (no branch changes)
- `git config …`
- Any direct file edits, `rm`, `mv`, `touch`, etc.

All **read** operations are fine (`git status`, `git diff`, `git log`, `git rev-parse`, `git rev-list`, `git show`, `git config --get …`, etc.).

If the procedure below seems to require a banned write, **stop and report to the user** rather than substituting another command.

## What this skill does

1. Resolves a **base ref** (default `origin/main`; the user may pass another, e.g. `origin/develop`, `main`, `upstream/release`).
2. Verifies the working tree is safe to touch.
3. Creates a recovery branch `pre-recompose/<current-branch>` pointing at the current tip, so the long history is trivially restorable with `git reset --hard pre-recompose/<branch>`.
4. Runs `git reset --mixed <base>` — branch HEAD moves to base, all branch changes appear as **unstaged** working-tree edits.
5. Hands off to the **modular-commits** procedure to re-commit the diff as small, focused commits.
6. Leaves the branch unpushed. The `pre-recompose/<branch>` ref stays in place; the user deletes it manually when they no longer need it.

The result: the same final tree as before, but the commit log only contains commits that map cleanly to chunks of the branch-vs-base diff.

## Argument handling

The skill may be invoked with an optional argument naming the base ref.

- No argument → `origin/main`.
- Single token → use as-is (`main`, `origin/develop`, `upstream/release-2.4`).
- If the token has no `/`, treat as a local branch. If the user clearly means the remote-tracking ref ("reset to origin main"), prefer `origin/<token>`.

Do not silently rewrite a user-specified base. If it is ambiguous, ask.

## Pre-flight checks

All read-only. Run before the reset. Any failure → stop and report; do **not** proceed.

1. **Inside a git repo.** `git rev-parse --is-inside-work-tree`.
2. **Not on the base branch.** Reject if `HEAD` resolves to the same commit as the base, or if the current branch name equals the local form of the base. Recomposing the base itself makes no sense.
3. **Clean working tree.**
   - `git status --porcelain` must report no modified or staged tracked files.
   - Untracked files are tolerated — they will not be touched by the reset — but list them so the user can confirm none should have been committed before recomposing.
   - If there are uncommitted or staged changes, **stop**. Ask the user to commit them (or stash them themselves) and re-invoke. Do not stash on their behalf — `git stash` is banned in this skill, and the whole point is deliberate commits, not surprise rescues.
4. **Base ref resolvable locally.** `git rev-parse --verify <base>` must succeed against whatever local state exists. **Do not `git fetch`** to refresh it — that is a banned write. If the user wants the comparison to reflect the current remote tip, they fetch themselves before invoking.
5. **Branch is ahead of base.** `git rev-list --count <base>..HEAD` must be ≥ 1. If 0, there is nothing to recompose — report and stop.
6. **Diff is non-empty.** `git diff --quiet <base>..HEAD` should report a difference. If the branch is ahead by N commits but the cumulative diff is empty (e.g., a change was added and then reverted), report this — the recompose would produce no commits — and ask the user whether to proceed (HEAD would end up at base with no new commits).
7. **Backup ref does not already exist.** `git rev-parse --verify pre-recompose/<current-branch>` must fail (i.e., the ref is absent). If it exists, **stop** and report — that means the branch was already recomposed previously, and overwriting the backup would discard the original long history. Ask the user to delete or rename the existing `pre-recompose/<current-branch>` ref themselves before re-invoking. Do not pass `-f` to overwrite it; that is explicitly banned.

## Procedure

1. **Resolve the base** per **Argument handling** above. Print: `Base: <base> (<short-hash>)`.

2. **Run pre-flight checks** in parallel where possible (`git status`, `git rev-parse`, `git rev-list --count`, `git diff --stat`). Abort on any failure as described.

3. **Show the plan.** Print, concisely:
   - Current branch and its tip short-hash.
   - Base and its short-hash (and a one-line reminder: "comparing against local state of this ref — `git fetch` was not run").
   - `N commits` that will be discarded, `M files changed, +X / -Y` from `git diff --stat`.
   - The backup branch name that will be created: `pre-recompose/<current-branch>`.

   No interactive confirmation is required unless something looked unusual in pre-flight (empty diff, untracked files the user might have meant to commit, etc.). In that case, surface it and ask.

4. **Create the backup branch.** `git branch pre-recompose/<current-branch> HEAD`.
   - This is the single allowed `git branch` invocation in the skill — exact name, no flags, no `-f`.
   - Print the name so it appears in the transcript: `Backup: pre-recompose/<current-branch> -> <short-hash>`.
   - If creation fails for any reason (e.g., the pre-flight ref-existence check raced and the ref now exists), **stop**. Do not retry with `-f`, do not pick a different name.

5. **Reset to the base.** `git reset --mixed <base>`.
   - `--mixed` (the default) moves HEAD and resets the index to match base, but leaves the working tree alone. All branch changes now appear as **unstaged** edits — exactly the starting state that **modular-commits** expects.
   - Do **not** use `--hard` (destroys the working tree) or `--soft` (leaves everything staged, defeating deliberate staging).

6. **Hand off to modular-commits.** Follow the [modular-commits](../modular-commits/SKILL.md) procedure from step 1 (Inspect state). All its rules apply verbatim:
   - Single-line imperative subject. No body. No Claude attribution.
   - Stage deliberately with `git add <path>` (or `-p`). Never `git add -A` / `git add .`.
   - One logical change per commit.
   - Use the canonical commit-message style from that skill — do not infer from the just-discarded branch history.

7. **Emit the final summary.** Combine the modular-commits tree-style output with a short footer:
   - "Backup branch: `pre-recompose/<current-branch>` — restore the long history with `git reset --hard pre-recompose/<current-branch>`. Delete it yourself (`git branch -D pre-recompose/<current-branch>`) once you no longer need it."
   - Whether the branch has an upstream (read-only check: `git rev-parse --verify @{u}` or `git config --get branch.<name>.remote`). If yes, surface: "Branch has an upstream; the recomposed history diverges from it. Publishing would require a force-push, which this skill does not perform — run `git push --force-with-lease` yourself if/when you want to update the remote." If no, say "Branch has no upstream — a normal `git push -u …` (run by you) will publish the recomposed history."

## Safety rules (reinforcement of the allowlist)

- **Never push.** Any form, any remote, any flag. Not even after the user says they like the result — they push themselves.
- **Never fetch.** The base is compared against local state. The user fetches before invoking if they want fresh state.
- **Only one ref creation.** Exactly `git branch pre-recompose/<current-branch> HEAD`, once. No tags, no `update-ref`, no second backup, no `-f` overwrite, no rename.
- **Never operate on the base branch itself.** Pre-flight catches this; do not bypass.
- **Never `--hard` reset.** The working tree is the source of truth for the new commits; destroying it would destroy the change set.
- **Never bypass hooks.** No `--no-verify`. If a pre-commit hook fails during step 5, fix the underlying issue, re-stage, commit again — same as modular-commits.
- **Never edit `.git/` or config.** Read-only access to git internals only.

## Recovery (read-only guidance for the user)

If the user wants to undo the recomposition, the primary path is the backup branch — the skill does not run these:

```
git reset --hard pre-recompose/<current-branch>   # restores the long history
```

Fallback (if the backup branch has already been deleted):

```
git reflog                       # find the pre-reset HEAD entry (often HEAD@{N})
git reset --hard <reflog-hash>   # restores the prior branch tip
```

Immediately after the reset in step 5, the prior tip is typically `HEAD@{1}` in the reflog.

## Anti-patterns

- Forcing the backup with `git branch -f pre-recompose/<branch>` because the ref already exists. Banned — that would discard the original long history the prior recomposition was meant to preserve. Pre-flight catches this; surface it to the user instead.
- Inventing a different backup name (e.g., suffixing a timestamp) when `pre-recompose/<branch>` is taken. The name is fixed; uniqueness is the user's problem to resolve.
- Skipping the backup branch because "the reflog is enough." It isn't — the reflog expires (default 90 days) and is harder for the user to navigate. The backup branch is mandatory.
- Running `git fetch` because the comparison "should be against current remote." Banned. The user fetches first if they care.
- Auto-stashing dirty changes "to be helpful." Banned, and surprise stashes lose work. Stop and let the user decide.
- Force-pushing the recomposed branch — even after the user expresses satisfaction. Banned. They push themselves.
- Reading the just-discarded commit messages to draft the new ones. The new commits describe the **final diff**, not the iteration. Use `git diff --staged` / `git status` against the post-reset state, exactly as modular-commits prescribes.
- Bundling unrelated edits into one commit because the diff happens to span many files. The modular-commits rules still apply.
- Renaming the skill's reset target without telling the user (e.g., they said `main`, you used `origin/main`). Ask if ambiguous; otherwise use exactly what they said.

## Quick checklist

- [ ] Base ref resolved against **local** state (no fetch)
- [ ] Working tree clean (untracked files acknowledged)
- [ ] Branch is ahead of base with a non-empty cumulative diff
- [ ] `pre-recompose/<current-branch>` did not already exist; created via `git branch pre-recompose/<current-branch> HEAD`
- [ ] `git reset --mixed <base>` performed (the only `git reset` in this skill)
- [ ] modular-commits procedure followed end-to-end on the resulting unstaged diff (only `git add` + `git commit` writes)
- [ ] Final summary names the backup branch and (if upstream exists) the force-push that the **user** must run
- [ ] No push, no fetch, no tag creation, no second/`-f` branch, no stash, no `--hard`, no `--no-verify`, no attribution trailers
