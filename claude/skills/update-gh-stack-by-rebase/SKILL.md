---
name: update-gh-stack-by-rebase
description: Bring a GitHub-native PR stack (`gh stack`) back to a mergeable state after its target branch moved — typically right after the bottom PR was squash-merged into the target, or after main was merged into the target. Discovers the stack from GitHub, pins each layer's own commits to its PR head, replays every layer onto its new parent with `git rebase --onto` in a temporary worktree (so pre-squash commits are never replayed), auto-resolves only provably clean conflicts and stops on anything overlapping, repairs layers that already sit on a stale base, builds, force-pushes with lease atomically, and verifies bases, commit counts and mergeability on GitHub. Use when the user says "update the stack", "rebase the stack onto <target>", "sync the stack after merging #N", "the stack has conflicts after the squash", "pull main into <target> and update the stack", or invokes /update-gh-stack-by-rebase.
---

# Update a gh stack by rebase

The workflow this skill serves: PRs in a native GitHub stack are merged one at a time, bottom first, by **squash-merging into the target branch**. A squash puts the PR's change on the target as one new commit, so every branch above it still carries the PR's original commits. GitHub can't reconcile those, and the next PR shows conflicts or a diff inflated with already-merged work. This happens after every merge. It's the normal state of the stack, not an accident, so this skill is the routine step that runs between merges.

The goal is a stack where every open PR is based on the branch directly below it (the bottom one on the target), contains exactly its own commits, and GitHub reports it mergeable. Then review and merging can continue.

## Why not `gh stack sync` / `gh stack rebase`

Past sessions tried both, and they're unreliable for this workflow:

- `gh stack sync` refuses to run if the checkout has *any* untracked file (an untracked `.claude/` was enough). On a conflict it rolls every branch back and exits 0 with nothing done. On a divergence it aborts silently in a non-interactive shell.
- Both only skip squash-merged commits ("adjusted for merged PR") when the local `.git/gh-stack` tracking still lists the merged PR. After a relink, a `gh stack checkout`, or work from another machine, it doesn't, and they replay the pre-squash commits into conflicts.
- Neither notices a layer that is *already* broken on GitHub, one sitting on an old pre-squash base and showing 48 commits instead of 3. Previous runs found such layers twice.
- They fail when a stack branch is checked out in another worktree, and they trust stale local branches.

So this skill uses `gh` for discovery and verification, and plain git for the rebase. GitHub's PR heads are the only source of truth. Local branches are always assumed to be stale copies and get reset to the PR head.

## Helper script

`scripts/stack_rebase.py` (in this skill's directory) does the mechanical parts deterministically. Run every subcommand from inside the temporary worktree (step 2).

- `plan --out <plan.json> [<PR#|branch>]` fetches, walks open PRs down to the target and up to the top, and records each layer's PR head SHA and **cut**: the commit its own work starts after. For the bottom layer, the cut is whichever is closest to the layer: its merge-base with the target, or the head of a merged PR into the target. For the other layers, the cut is the parent PR's head. If a layer doesn't contain its parent's head, it's flagged **BROKEN**. Its own commits are then guessed as the trailing commits that aren't patch- or subject-equivalent to the parent or to recently merged PRs. The step is read-only apart from `git fetch`.
- `apply --plan <plan.json>` runs, for each layer bottom-up, `git rebase --onto <new parent> <cut> <branch>` with rerere and diff3 conflict markers. The bottom layer's new parent is `origin/<target>`; each later layer's is the just-rebased branch below. It resolves clean conflicts itself (see step 4) and logs every resolution to `<plan.json>.resolutions.log`. On a conflict that isn't clean, it stops with exit 3 and leaves the rebase in progress. Re-running it continues an in-progress rebase once the conflict is resolved and staged, then skips layers already done (tracked in `<plan.json>.state.json`). So it is resumable.
- `push --plan <plan.json> [--dry-run]` runs one `git push --atomic` with `--force-with-lease=<branch>:<PR head at plan time>` for every changed layer. Either all branches update or none do. If someone pushed in the meantime, the lease fails.
- `verify --plan <plan.json>` re-fetches and checks each layer on GitHub. It waits up to a minute for `mergeable` to leave `UNKNOWN`. Each layer must be open, based on the layer below (or the target), with GitHub's head equal to the rebased branch, containing its base's head, carrying exactly its planned number of own commits, and not `CONFLICTING`. It exits non-zero if any layer fails.

## Procedure

### 1. Pre-flight

- `gh auth status`, and `gh extension list | grep gh-stack`.
- Identify the stack from what the user gave you (a PR number, URL or branch), or else from the current branch. The **target** is the bottom open PR's base. Never rewrite the target branch itself.
- If the user also asked to bring another branch into the target ("pull main into X first"), do that first. Run `git worktree add --detach <scratchpad>/trunk-merge origin/<target>`, then `git merge --no-edit origin/main`, then `git push origin HEAD:<target>` (a plain push, no force), then remove that worktree. Merge rather than rebase, because the target is shared. If the merge conflicts in a way that isn't mechanical, stop and ask.

### 2. Work in a temporary worktree

Don't run anything in the user's checkout. It usually has untracked or uncommitted files, and a stack branch checked out.

```bash
WT=<scratchpad>/stack-rebase
git worktree add --detach "$WT" origin/<target>
cd "$WT"
```

### 3. Plan and review it

```bash
python3 <skill-dir>/scripts/stack_rebase.py plan <PR#> --out <scratchpad>/stack-plan.json
```

Read the output before applying:

- **The bottom layer's `own` count should equal the PR's real size.** If `github=` is larger right after a squash merge, the difference is the pre-squash commits, and the cut drops them. That's expected. If `own` equals `github=` right after a squash merge, check it anyway: when the merged PR gained commits after the bottom branched off it, its final head isn't in the bottom layer and the plan falls back to the merge-base, counting the merged PR's original commits as the layer's own. Compare `git log <cut>..<PR head>` with `gh pr view <merged#> --json commits` and re-plan with `--cut <PR#>=<last merged-PR commit in the layer>`.
- **BROKEN layers:** check the guessed own commits against the PR (`gh pr view <n>` title and body; `gh pr view <n> --json commits` from before the breakage if it helps). If the guess is wrong, re-plan with `--cut <PR#>=<sha>`, where `<sha>` is the last commit that is *not* the layer's own. Don't apply a plan you haven't checked for BROKEN layers.
- **"checked out in worktree X":** git can't rewrite a branch that another worktree holds. Run `git -C X checkout --detach`. That leaves the files untouched at the same commit. Tell the user it was detached. Don't delete worktrees unless the user asks.
- **"contains merge commits":** the rebase will flatten them. That's fine if the merge only brought in the target; otherwise ask.
- **A note that the bottom PR's base is a merged branch:** GitHub didn't retarget it. Apply and push as normal, then fix the base in step 7.

### 4. Apply, resolving conflicts

```bash
python3 <skill-dir>/scripts/stack_rebase.py apply --plan <scratchpad>/stack-plan.json
```

**Conflicts are resolved automatically only when the resolution is provably clean.** `apply` reads each conflict hunk as target / common base / incoming commit, and resolves a hunk only if it is one of these:

- **Identical:** both sides made the same change (ignoring whitespace and blank lines).
- **One-sided:** one side equals the base, so only the other side really changed it. Take that side.
- **Additive:** the base is empty (both sides only inserted lines at the same spot), and the two insertions declare no common name (`func`, `class`, `struct`, `enum`, `case`, `let`, `var`, `def`, `function`, `const`, `type`…). Keep the target's lines and then the incoming lines. Import lines both sides added are kept once.

All of a step's conflicted files must qualify, or none is touched. Recorded rerere resolutions are replayed and logged. **Everything else stops the run (exit 3):**

- both sides changed the same base lines;
- both sides add a declaration with the same name (overlapping functionality);
- delete/modify, rename or add/add conflicts;
- binary files;
- malformed markers.

In this workflow, the typical stop is the squash-merged PR having moved or restructured code that a later commit edits. For example, a type moved to another file.

**When `apply` stops, first decide whether it is a real collision.** Many stops are not, and you resolve those yourself without asking:

- **Rename + edit:** the target renamed an identifier, type, file or doc term (e.g. `shouldAbandon` → `shouldStop`, "slice" → "background task run"), and the incoming side only kept the old name while adding or editing lines around it. Take the target's new names and keep every incoming addition, rewriting old names inside the incoming lines to the new ones.
- **Moved code + edit:** the target moved code that the incoming commit edits, and the edit applies unchanged at the new location.
- **Both sides added unrelated lines** that `apply` refused for a reason other than a shared declaration name.

Edit the files, `git add` them, re-run `apply`, and record each one for the report (PR, commit, file, what you did).

**Stop and report only on a real collision:** both sides changed the behaviour of the same code differently, both declare the same thing with different meanings, one side deleted code the other relies on, or you can't tell what the combined result should mean. Report it and wait. Include the PR, the commit, the file, the reason, and the target/base/incoming excerpt `apply` printed; propose a resolution if you can see one. The rebase stays in progress in the temporary worktree, and nothing has been pushed. If the user tells you how to resolve it, edit the files, `git add` them, and re-run `apply`. It finishes the in-progress rebase and continues up the stack. If the user wants to abandon the update, run `git rebase --abort` and remove the worktree.

`apply` warns when a layer ends with a different commit count than planned. That usually means a commit became empty because its change is already on the target. Mention it in the report.

### 5. Build

Every layer must build, because layers merge one at a time. Build them in parallel, one subagent per layer, with **at most 3 build subagents running at once**: launch the bottom three together, and start the next layer's subagent each time one reports. More concurrent builds compete for CPU and are slower overall. Give each subagent the layer's PR number and branch, and have it: create its own detached worktree at `origin/<branch>` under the scratchpad, run any project setup the docs require (e.g. `xcodegen generate`), run the project's documented build command (CLAUDE.md / AGENTS.md) with its own build directory (e.g. its own `-derivedDataPath`) so the builds don't collide, and report OK or FAIL with the errors (file, line, message). Subagents only report: they don't fix, commit or push, and they remove their worktree when done. If the project documents no build command, say that you didn't build. You can push before the builds return; a failure gets fixed on top afterwards.

A textually additive resolution can still collide semantically: two overloads, or a `switch` that now misses a case. When a layer fails, apply the same test as in step 4. A leftover pre-rename identifier (a line that merged cleanly but still uses a name the target renamed) you fix yourself, in the lowest layer that fails, as a new commit on that layer, then rebase the layers above onto it; a real collision you report, the same way as an `apply` stop.

**Anti-pattern: making every commit compile.** Don't build commit by commit, and don't rewrite history to move a fix into the commit that introduced the error. Per-commit compilability doesn't matter; per-layer does. Don't build layers one after another in the main thread either, and don't launch a subagent for every layer at once: keep three running.

### 6. Push

```bash
python3 <skill-dir>/scripts/stack_rebase.py push --plan <scratchpad>/stack-plan.json --dry-run
python3 <skill-dir>/scripts/stack_rebase.py push --plan <scratchpad>/stack-plan.json
```

Invoking this skill authorises force-with-lease pushes of the stack's branches, but never of the target. If the lease is rejected, someone pushed to a stack branch after you planned. Re-plan from step 3; don't use plain force.

### 7. Verify on GitHub

```bash
python3 <skill-dir>/scripts/stack_rebase.py verify --plan <scratchpad>/stack-plan.json
```

The bases are untouched by a rebase, so the native stack object stays as it was. Only relink if a base is actually wrong (the bottom PR isn't based on the target, or a layer isn't based on the one below):

- `gh pr edit --base` is refused while a PR is in a stack.
- Run `gh stack unstack <stack#>`, then `gh stack link --base <target> <every open PR, bottom → top>`. **Always pass `--base`**: without it, `link` silently re-bases the bottom PR onto the repo default branch. Also pass **every** open PR, because `link` refuses to update a stack if any existing PR would be dropped.
- The stack number changes on every relink. Report the new one.

`mergeStateStatus` of `BLOCKED` (reviews pending) or `UNSTABLE` (checks running or failing) still counts as mergeable from the stack's point of view. Report them as-is. Only `CONFLICTING` / `DIRTY` mean the update failed.

### 8. Clean up

Run `git worktree remove "$WT"` (if it refuses, the worktree is dirty: look at what's there, don't force it). Local branches now match GitHub. If the user drives this stack with `gh stack` commands locally, the local tracking in `.git/gh-stack` is stale. `gh stack unstack --local` followed by `gh stack checkout <top PR#>` re-imports it from GitHub without touching the remote. Only do this if they use it, and mention it either way.

## Report

- The target branch and the commit the stack now sits on, and what triggered the update (e.g. "#503 squash-merged").
- A table, bottom to top: PR number, branch, own commits, the GitHub commit count before → after, and the `mergeable` / `mergeStateStatus` after.
- Every BROKEN layer you repaired and how you confirmed its own commits.
- Each auto-resolved conflict from the resolutions log (PR, commit, file, kind), and each conflict resolved by the user's instruction.
- Each layer's build result from the subagents, or that you didn't build. Say whether tests ran.
- Anything you changed outside the stack branches: detached worktrees, a relink with the new stack number, local tracking left stale or re-imported.
