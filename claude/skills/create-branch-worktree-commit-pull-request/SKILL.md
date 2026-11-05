---
name: create-branch-worktree-commit-pull-request
description: Get changes into a PR in one shot. Creates a new branch (named by the user or inferred from the session's scope of work) in a new git worktree via `git worktree add` and works there by absolute path without moving the session's working directory, then either (1) sweeps the uncommitted changes under the current directory into the worktree, or (2) does the work described in the invocation prompt inside the worktree — and in both cases commits via /modular-commits and opens a PR via /create-pr against `main` or the branch the user names. Use when the user invokes /create-branch-worktree-commit-pull-request, or asks to "put these changes on a new branch and open a PR", "sweep my changes into a PR", or "do X in a worktree and open a PR".
---

# Create Branch, Worktree, Commit, Pull Request

Two modes, one protocol:

1. **Sweep mode** — the invocation has no work instructions. Move the uncommitted changes under the current directory onto a new branch in a new worktree, commit them modularly, and open a PR.
2. **Task mode** — the invocation includes instructions for changes to make. Set up the branch and worktree, do the work there, commit modularly, and open a PR.

If there are both uncommitted changes in the current directory *and* work instructions, carry the changes over (§3) and then do the work on top of them (§4). Everything ends up in the same PR.

The skill is fire-and-forget: the user invokes it and reviews the PR later. Run it end to end without the user's intervention. Only stop to ask when something below explicitly says to, or when a genuine question or something important comes up (ambiguous instructions, unrelated changes in the sweep, a conflict, failing tests). Never ask the user to change directories, switch sessions or approve a worktree switch.

## 1. Gather inputs

From the user's request, pick up:

| Input | Default |
| --- | --- |
| Branch name | inferred from the scope of work (see below) |
| Base branch | the repo's default branch on `origin` (usually `origin/main`) |
| Work instructions | none → sweep mode |
| PR overrides (title, description, draft) | none — passed through to `create-pr` |

**Inferring a branch name.** Derive a short lowercase kebab-case slug (2–5 words) that names what the change does, e.g. `fix-login-redirect` or `add-export-csv`. Base it on, in order: the work instructions; what has been discussed and done earlier in this session; the content of the uncommitted diff (`git diff --stat`, `git status`). If the user gave a branch name, use it verbatim. If the name already exists locally or on `origin`, append `-2`, `-3`, … rather than reusing someone else's branch — unless the user named it explicitly, in which case ask.

**Resolving the base.** A bare name like `main` or `develop` means `origin/<name>`. Find the default branch with `git symbolic-ref --short refs/remotes/origin/HEAD` (strip the `origin/` prefix) if the user didn't name one. If the named base doesn't exist on `origin`, ask.

## 2. Create the branch and worktree

```bash
START=$(pwd)                                   # the directory the user is in
MAIN=$(git rev-parse --show-toplevel)
REL=$(git rev-parse --show-prefix)             # START relative to repo root ("" at the root)
BRANCH=<branch name>
SLUG=${BRANCH//\//-}
BASE=origin/<base>
WT="$MAIN/../$(basename "$MAIN")-$SLUG"
git -C "$MAIN" fetch origin
git -C "$MAIN" worktree add -b "$BRANCH" "$WT" "$BASE"
```

If the worktree path already exists, pick a new suffix rather than reusing it.

**Do not switch the session into the worktree.** Do not call `EnterWorktree` / `ExitWorktree`, do not use Claude Code's native worktree creation, and do not try to change the session's working directory — those prompt the user and break the fire-and-forget flow. The session's pwd stays where it is; the worktree is addressed by absolute path instead:

- **Shell state does not persist between Bash calls**, so the variables above are gone after this step. Resolve `$WT`, `$START`, `$MAIN` and `$BRANCH` to literal absolute paths/names once and write those literals into every later command.
- **Git:** always `git -C <WT> …`. Never a bare `git` that would act on the original checkout.
- **File reads and edits:** absolute paths under `<WT>` with the Read/Edit/Write tools.
- **Other commands** (tests, lint, build, package managers): prefer the tool's own directory flag (`npm --prefix`, `yarn --cwd`, `make -C`, `xcodebuild -project <WT>/…`, `swift test --package-path`); otherwise run them in a subshell, `(cd <WT> && …)`, so the session's directory never changes.
- **Sub-skills and subagents** (`modular-commits`, `create-pr`, any Agent): tell them the worktree's absolute path and that every git and file operation must target it via `git -C` and absolute paths.

From here on, **all** work happens in the worktree: every file edit, test run, and commit. Never touch the original checkout again except in §3 to move changes out of it. Tell the user the branch name and worktree path in a single line and keep going — no confirmation needed.

## 3. Carry over uncommitted changes (if any)

Check for changes **under the current directory only** — not elsewhere in the repo:

```bash
git -C "$START" status --porcelain -- .
```

If empty, skip this section. Otherwise, before moving anything, confirm the changes belong to this scope of work: if the diff obviously mixes in unrelated work the session never touched (e.g. edited dotfiles alongside the feature), list the files and ask which to include. Otherwise move all of them.

Move them by stashing in the original checkout and applying in the worktree. The stash is shared across worktrees of the same repo:

```bash
git -C "$START" stash push --include-untracked -m "cbwcpr: $BRANCH" -- .
STASH=$(git -C "$START" rev-parse stash@{0})
git -C "$WT" stash apply --index "$STASH" || git -C "$WT" stash apply "$STASH"
```

- On success, drop the stash entry: find its index with `git stash list` (the one whose message is `cbwcpr: $BRANCH`) and `git stash drop stash@{N}`. Verify with `git -C "$WT" status` that the same files now show as changed in the worktree, and `git -C "$START" status -- .` that they are gone from the original checkout.
- If the apply conflicts (usually because the original checkout's `HEAD` has commits that aren't in the base), **stop**: reset the worktree (`git -C "$WT" checkout -- . && git -C "$WT" clean -fd`), put the changes back where they were (`git -C "$START" stash pop`), and tell the user which files conflicted and that their changes are back in the original checkout untouched. Suggest basing on the current branch instead if that's what they meant.

Never use `git stash pop` in the worktree and never drop the stash before the apply has succeeded — the stash is the only copy of the user's work during the move.

## 4. Do the work (task mode only)

Carry out the work instructions inside the worktree, applying the usual standards: read before editing, follow the repo's conventions, and run the project's relevant tests/lint/build before committing. If the instructions are ambiguous in a way that would change the result, ask before guessing. If tests fail and you can't fix them, stop and report rather than opening a PR on red.

## 5. Commit

Invoke the `modular-commits` skill against the worktree (every git command as `git -C <WT> …`) to commit **all** changes (carried-over and newly made). Never run `git commit` directly. Afterwards `git -C <WT> status` must be clean.

## 6. Open the PR

Invoke the `create-pr` skill against the worktree (every git/`gh` command run with `git -C <WT>` or from `(cd <WT> && …)`, so it picks up the worktree's branch, not the original checkout's). Pass the base branch from §1 if it isn't `main`, plus any title, description, or draft override the user gave. `create-pr` pushes the branch and opens the PR — invoking this skill is the user's authorization for that push.

## 7. Report

Tell the user: the PR URL, the branch, the worktree path, the commits made (subjects), and whether changes were carried over from the original checkout. Leave the worktree in place — the user removes it after the PR merges (`git worktree remove "$WT"`).

## Anti-patterns

- Editing files or committing in the original checkout instead of the worktree.
- Calling `EnterWorktree`, using Claude Code's native worktree flow, or asking the user to `cd` / switch the session's directory. Address the worktree by absolute path instead.
- Relying on shell variables from an earlier Bash call; they don't persist.
- Pausing for confirmation on routine steps. Ask only for genuine questions or something important.
- Sweeping changes from outside the current directory, or silently sweeping unrelated work.
- Dropping the stash before the apply succeeded, or leaving the user's changes stranded in a stash after a failure.
- Reusing an existing branch or worktree that the user didn't name.
- Committing with raw `git commit` instead of `/modular-commits`, or opening the PR with raw `gh pr create` instead of `/create-pr`.
- Opening a PR when tests are failing or the worktree isn't clean.
- Over-engineering the steps instead of following them. In sweep mode, don't build, run tests, regenerate the project (e.g. `xcodegen generate`) or add any other verification. Move the changes, commit and open the PR. Build or test only in task mode, as §4 says, or when the user asks.
