---
name: split-branch-into-prs
description: >-
  Split one long-lived branch into several small, independently-reviewable
  feature branches, each committed, build-verified, and opened as its own PR.
  Unlike recompose-branch (which rewrites one branch's history in place), this
  leaves the original branch untouched and carves its cumulative diff into
  per-feature branches — independent off the base wherever possible, stacked
  only when features genuinely depend on each other. Use when the user asks to
  "split this branch into PRs", "break the branch into smaller reviewable
  chunks", "one PR per feature", "decompose / carve up this branch", or "turn
  this big branch into stacked PRs".
---

# Split a branch into per-feature branches and PRs

Use this when a branch has grown into several distinct features and the user wants each shipped as its own small, reviewable PR. The output is N new branches (one per feature), each building on its own, each opened as a PR. The original branch is never modified.

**The goal is to ensure changes are able to be reviewed in a modular way** Reviews of large PRs, when done either by a human or an LLM, are difficult to do well - bugs get missed, focus is absent, and lots of code just looks like noise when it can't easily be connected together in a topical changeset. This skill makes it easy to break changes into meaningful parts that provide not only a review trail, but an audit trail for when code is merged.

**Independent PRs are the strong default.** Each feature branch off the base, each PR targets the base, each merges in any order. This gives reviewers maximum flexibility and avoids the merge-order constraints of a stack. Only reach for stacking when features have genuine compile-time or semantic dependencies that make independence impractical.

This borrows the base-resolution and read-only pre-flight discipline from `recompose-branch`, but it does **not** rewrite the source branch. It borrows nothing else from it; PR creation defers to `create-pr`.

## Core principles

- **The source branch is read-only.** Create new branches; never reset, rebase, or force-update the original. There is no backup step because nothing destructive happens to it.
- **The final tree is the source of truth.** Every output branch is carved from the source branch's _cumulative diff vs the base_, not from its commit history (the iteration order is noise, and cherry-picking interleaved commits conflicts).
- **Each output branch must build on its own.** A PR that doesn't compile isn't reviewable. Verify every branch before committing it.
- **The split must be faithful.** The union of the output branches must reproduce the source branch's tree exactly (modulo intentionally-dropped noise). Prove it with a diff at the end.
- **Prefer independence; stack only when forced.** Independent PRs merge in any order, review in any order, and don't block each other. Only stack when feature B literally cannot compile without feature A's changes (a new type, a new interface member, shared infra that didn't exist before). Shared files alone are not reason enough to stack — partial surgery on a shared file is cheaper than the merge-order tax of a stack.
- **Only `git add` / `git commit` / `git checkout -c` / `git checkout <ref> -- <path>` / `git push` write anything** during carving. No `reset`, `rebase`, `merge`, `cherry-pick`, `revert`, or force-push. No `git add -A` / `git add .` (untracked cruft in the repo root must not leak into feature branches). `gh stack` commands that force-push (`rebase`, `sync`, `push`) are a **post-split** tool, not part of carving.

## Argument handling

Optional argument names the base ref. No argument → `origin/main`. A bare name → treat as `origin/<name>` (the remote tip), matching `create-pr`'s convention; say so once. Do not `git fetch` to refresh it unless the user asks — the comparison is against local state; `create-pr` will fetch at PR time.

## Pre-flight (all read-only; abort and report on any failure)

1. `git rev-parse --is-inside-work-tree` — inside a repo.
2. Current branch is **not** the base. Recomposing the base into itself is meaningless.
3. `git status --porcelain` — working tree clean for tracked files. Untracked files are tolerated but **list them** and make sure none leak into feature branches (never `git add -A`).
4. `git rev-parse --verify <base>` — base resolvable locally.
5. `git rev-list --count <base>..HEAD ≥ 1` and `git diff --quiet <base>..HEAD` reports a difference — the branch is actually ahead with a non-empty diff.
6. **Native stacking availability** (only matters if the topology turns out to need stacking; check it here so you know before promising anything):
   - `gh --version` → **2.0.0 or later** is required.
   - `gh extension list | grep gh-stack` → if absent, `gh extension install github/gh-stack`.
   - The repo is on GitHub.com (stacks are a GitHub.com feature) and **all branches will live in the same repository** — cross-fork stacks are not supported.
   - If any of this fails, say so once and note that stacking will fall back to degraded mode (PRs chained by `--base` alone, no native stack) if it turns out to be needed.

## Step 1 — Analyze the diff and cluster it into features

Work from the cumulative diff, `SOURCE = <the long branch>`:

- `git diff --name-status <base>..SOURCE` — every changed/added/deleted file.
- `git log --oneline <base>..SOURCE` — read commit subjects **only** for intent/labels, never to drive the split.
- For each file, decide which feature(s) touch it. Most files belong to exactly one feature (a new file, a deleted file, a module only that feature edits). These are **single-feature files**.
- Some files are edited by **multiple** features (a shared manager, the app entry point, a cross-cutting utility, an interface/protocol and its implementors, a shared strings/manifest file). For each shared file, pull its diff and attribute **each hunk** to a feature: `git diff <base>..SOURCE -- <file>` and read the `@@` hunks. A single hunk can even mix two features (e.g. two methods added back-to-back) — note that; you'll split it by hand later.

Produce a feature list: for each feature, a short name, the single-feature files it owns, and its slice of each shared file. Watch for **dependencies**: if feature B's code references a symbol that feature A introduces (a new type, a new interface member), B depends on A. Record these — they determine whether stacking is needed.

Present this clustering to the user before carving anything. If the split is non-obvious, this is worth an `AskUserQuestion` on how finely to split (e.g. keep one large cohesive feature whole vs. sub-split it).

## Step 2 — Decide the topology (independent vs stacked)

**Default to independent.** Independent PRs are easier to review, merge in any order, and don't create blocking chains. Only stack when you have a concrete reason.

### When to keep PRs independent (the default)

- A feature's files are all single-feature files — trivially independent.
- Features share files but their hunks are logically independent (e.g. two features each add a case to a switch statement, or each append to a config file). Each branch gets partial surgery on the shared file containing only its hunks. More work to carve, but the result is better for reviewers and merging.
- Features touch the same broad area but don't introduce symbols the other needs. Each branch should compile and pass tests with only its own changes applied.

### When stacking is warranted

Stack features into a chain (`base → A → B → C`) only when:

- **Compile-time dependency**: feature B imports a type, protocol, or function that feature A introduces. B literally cannot build without A's changes present.
- **Semantic dependency**: feature B's changes only make sense in the context of A (e.g. A adds a data model and B adds the UI that displays it — the UI references the model's properties).
- **Shared infrastructure**: a new utility/helper/test-double is introduced by one feature and consumed by several others. Thread it into the bottom of the chain so everything above inherits it.

Co-editing a file is **not** by itself a reason to stack. If each feature's hunks in that file are independent, carve partial versions and keep the PRs independent.

### Stack ordering (when stacking is needed)

For any file touched by several features in the same stack, exactly one branch can take that file **wholesale** (`git checkout SOURCE -- file`): the branch that sits **above all the other features that touch it**, because by then the base already contains every other feature's changes. Every branch **below** needs a hand-built partial. So: **order the stack to put the feature with the largest shared-file footprint at the top** — it gets the big files for free; the smaller features below do the cheaper partial surgery.

Dependencies also constrain order: a feature must sit above every feature it depends on. Thread a shared dependency low in the stack so everything above inherits it.

### Confirming the topology

When entanglement is real, confirm the topology with `AskUserQuestion`. Offer: "stack them (PRs chain, merge bottom-up)" vs. "maximum independence off the base (more hand-surgery, PRs merge in any order)". Recommend stacking only when the dependency is genuine. If all features are independent, skip this — just proceed.

## Step 3 — Find the build/verify command

The skill is language-agnostic; discover how this project builds and tests before carving:

- Look for the obvious: `Makefile`, `package.json` scripts, `Cargo.toml`, an Xcode scheme (`xcodebuild -list`), a `*.gradle`, a CI config that names the build/test command.
- Prefer the **cheapest command that actually compiles the changed code** for fast iteration, and a fuller one (including tests) for final verification of each branch. Compiling the test target matters when a branch adds/edits tests or changes an interface every mock must satisfy.
- **Verify results explicitly.** Grep the build output for the real success/failure marker (e.g. `BUILD SUCCEEDED` / `BUILD FAILED`, a non-zero test summary). **Never trust the exit code of a piped command** (`xcodebuild ... | grep ...` returns grep's status, not the build's) — capture output to a file and check it, or check `${PIPESTATUS[0]}`.

## Step 4 — Carve each branch

Carve with plain git. Independent branches come off the base; stacked branches come off their parent in the chain. Do **not** use `gh stack add` to create these branches: it wants to create a layer from the working tree at the moment you call it, whereas here each layer is assembled file-by-file out of `SOURCE` and must build before it exists as a commit.

For each feature, in the planned order (independents off base first, then any stacked chains base-up):

1. `git checkout -c <feature-branch> <parent>` where `<parent>` is the base for an independent feature or the branch below it in a stack.
2. **Single-feature files** — bring them in wholesale: `git checkout SOURCE -- <file>...`. Deletions: `git rm <file>`.
3. **Shared files (independent branch)** — hand-build the partial: start from the base version and apply **only this feature's hunks**. Strip out other features' additions so this branch compiles without them. Targeted edits are usually more reliable than a filtered `git apply` when hunks are mixed; the compiler is your safety net.
4. **Shared files (top-of-footprint in a stack)** — wholesale is correct here (`git checkout SOURCE -- <file>`), because the base already has every other feature's slice.
5. **Shared files (lower branch in a stack)** — hand-build the partial: start from the parent's version and apply **only this feature's hunks**. Keep each partial a strict subset of the final file so the branch above can still take it wholesale.
6. **Interface / protocol ripple** — when a feature adds a member to an interface, **every implementor in that branch** must gain it: the real implementation plus all mocks/fakes/preview doubles/test stubs. Grep for conformers/implementors; a missing stub fails the build.
7. **Shared test infrastructure** (an in-memory fake, a test double) must live in the **lowest** branch that needs it, so branches above inherit it rather than duplicating it.
8. **Project-manifest surgery** (files that must be registered outside the source tree — an Xcode `project.pbxproj`, a `.csproj`, a `CMakeLists.txt`, a bundling manifest): use the ecosystem's **proper tool**, not hand-editing. For iOS, the `xcodeproj` Ruby gem is reliable and produces minimal diffs — remove refs for deleted files, add refs for new files to the right group and target(s), then verify the reference counts. Hand-editing UUID tables is fragile; only do it to mirror exact known lines when no tool exists.
9. **Files shared with a feature you are NOT including on this branch** — do a partial, not wholesale. Example: a telemetry file that both feature X and feature Y append to; a branch that has X but not Y must take X's additions only, or it will reference a symbol Y introduces and fail to build.
10. **Build and verify** (Step 3). Fix until green — compiler errors are precise; add the missing stub, the missing manifest entry, the missing dependency file.
11. **Commit.** One commit per feature is the natural unit here (this is one-PR-per-feature, not modular-commits). Use a single-line imperative subject; no attribution trailers. Stage with `git add -u` plus explicit `git add <new-file>` paths — never `git add -A` (keeps repo-root untracked cruft out).

## Step 5 — Prove the split is faithful

Check that the union of all output branches reproduces the source. For independent-only splits, merge all branches into a temporary branch and diff against SOURCE. For mixed topologies, diff the **top of any stack** plus the independent branches against SOURCE. The only acceptable differences are cosmetic (whitespace normalization, import ordering tools). Anything else means a branch is missing content — investigate before opening PRs. State the result explicitly: "branches A + B + C reproduce the source exactly, modulo <known cosmetic delta>."

## Step 6 — Push and open PRs

### 6a. Push every branch

`git push -u origin <branch>` for each. If any branch is the base of a stacked PR above it, it must be on the remote before the PR targeting it can be created.

### 6b. Open one PR per branch

Follow the `create-pr` skill's rules for base-branch convention, title/description generation, the strict concise body format (lead sentence, optional bug/limitation bullets, `Changes` bullets, no formatting beyond backticks, no footers/trailers/emojis — see `create-pr`), and the `gh pr create` invocation with a HEREDOC body.

- **Independent branches** target the base (e.g. `main`).
- **Stacked branches** target **the branch below them**, not `main`. `gh pr create --base` takes the bare branch name. Set this correctly at creation time.
- **Batch mode:** the user has already opted into "all PRs"; you may generate titles/bodies for all branches and open them without the per-PR interactive approval loop, unless the user asked to review each. Still honor `create-pr`'s body _format_ and banned-words rules.
- **Cross-reference in the body:** for a stacked PR, the first `Changes` line may note the layer position (e.g. "Second of three stacked PRs; builds on `<parent-branch>`."). Keep it to one plain sentence.

### 6c. Register a native stack (only for stacked chains)

If Step 2 determined that some features need stacking, register the chain as a native GitHub stack so reviewers get the stack UI and merging the bottom PR auto-rebases everything above it.

For each dependent chain (bottom → top), hand the already-open PRs to `gh stack link`:

```sh
gh stack link --base <base-branch> <bottom-pr-or-branch> <middle> <top>
```

Arguments may be branch names, PR numbers, or PR URLs, ordered **bottom-first**. `link` creates or updates the stack on GitHub and fixes each PR's base to the layer below it; it writes **no local tracking state**, which is exactly right here because the branches were carved by hand.

If the user wants local `gh stack` tracking too — so they can later run `gh stack view/sync/rebase/modify` from this checkout — adopt the existing branches instead of linking:

```sh
gh stack init --base <base-branch> <bottom-branch> <middle> <top>
gh stack submit
```

Confirm with `gh stack view` (add `--json` to parse it) and report the stack as GitHub now sees it.

**Skip this step entirely for independent PRs.** They don't form a stack and should not be linked into one — doing so would serialize their merge order for no reason.

**Degraded mode.** If `gh stack` is unavailable (extension won't install, not GitHub.com, stacks not enabled for the repo — exit code 9, cross-fork branches), the chained `--base` PRs from 6b still stand on their own. Say plainly that the native stack was not created and why; do not silently drop it.

### 6d. State the merge order

- **Independent PRs** merge any time, in any order.
- **A native stack** merges **bottom-up**: merging the bottom PR makes GitHub rebase and retarget every PR above it server-side, so the next one becomes the new bottom automatically. Use `gh stack merge [<stack-number|pr-number>]` to merge one or several layers at once (`--squash` / `--merge` / `--rebase`, `-y` to skip confirmation). After merges land, `gh stack sync --prune` updates local state and deletes the merged branches.

Return every PR URL, plus the stack number/URL if one was created.

## Anti-patterns

- Rewriting or resetting the source branch. It stays put; this skill only creates new branches.
- Driving the split from commit history / cherry-picking interleaved commits. Carve from the cumulative diff instead.
- `git add -A` / `git add .` — drags untracked repo-root files into a feature branch.
- Trusting a piped build command's exit code. Check the real success marker in captured output.
- Hand-editing a project manifest's UUID tables when a proper tool exists.
- Committing a branch before it builds. Every branch is independently reviewable → independently buildable.
- Putting the small feature at the top of the stack and the big shared-file feature at the bottom — inverts the wholesale/partial work and maximizes hand-surgery.
- Skipping the faithfulness diff. It's the only proof nothing was lost.
- **Stacking features that don't depend on each other.** Independent PRs that get dragged into a stack lose the ability to merge in any order and create unnecessary blocking chains. Only stack when there's a compile-time or semantic dependency.
- Opening the PRs with `gh stack submit --auto` — auto-generated titles and draft state ignore `create-pr`'s format. Create the PRs, then link them.
- Running `gh stack rebase` / `sync` mid-carve. Those force-push; they belong after the split is proven and pushed.

## Quick checklist

- [ ] Base resolved; source branch ahead with a non-empty diff; working tree clean (untracked noted)
- [ ] Diff clustered into features; single-feature vs shared files identified; shared-file hunks attributed; dependencies recorded
- [ ] Topology chosen: **independent by default**, stacked only for genuine dependencies; confirmed with the user when entanglement is real
- [ ] Build/verify command found; success checked explicitly (not via a piped exit code)
- [ ] Each branch carved: wholesale for single-feature files, partial for shared files on independent branches, wholesale for top-of-footprint files in stacks
- [ ] Each branch builds (and its tests compile when it touches them) before committing; one commit per feature; no `git add -A`
- [ ] Faithfulness diff proves union == source
- [ ] All branches pushed; one PR per branch per `create-pr` rules; stacked PRs based on their parent branch, independent PRs based on the base
- [ ] Stacked chains (if any) registered with `gh stack link` (or `init` + `submit` for local tracking) and confirmed with `gh stack view`
- [ ] Merge order stated: independents any time, stack bottom-up via `gh stack merge`, `gh stack sync --prune` after

## `gh stack` CLI reference

Quick reference for the GitHub native stacking commands. Install with `gh extension install github/gh-stack` (requires `gh` 2.0+).

### Stack creation and management

| Command                                         | Purpose                                                          |
| ----------------------------------------------- | ---------------------------------------------------------------- |
| `gh stack init [--base <branch>] [branches...]` | Initialize a new stack, optionally adopting existing branches    |
| `gh stack add [branch] [-m "msg"] [-A\|-u]`     | Add a new branch on top of the current stack                     |
| `gh stack view [--short\|--json]`               | View the current stack (interactive in terminals)                |
| `gh stack modify [--continue\|--abort]`         | Interactively restructure (reorder, fold, drop, rename branches) |
| `gh stack unstack [stack-number] [--local]`     | Remove a stack from tracking; alias: `gh stack delete`           |

### Remote operations

| Command                                                                  | Purpose                                                                         |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| `gh stack submit [--auto] [--open]`                                      | Push all branches, create/update PRs and the stack on GitHub                    |
| `gh stack sync [--prune]`                                                | Fetch, rebase, push, sync PR state — the all-in-one updater                     |
| `gh stack rebase [--downstack\|--upstack\|--no-trunk]`                   | Cascading rebase across the stack; pauses on conflicts (`--continue`/`--abort`) |
| `gh stack push [--remote <name>]`                                        | Push active branches with per-branch `--force-with-lease`                       |
| `gh stack link [--base <branch>] <branches-or-prs...>`                   | Link existing PRs/branches into a stack on GitHub without local tracking        |
| `gh stack merge [stack-or-pr-number] [--squash\|--merge\|--rebase] [-y]` | Merge one or more stacked PRs bottom-up (all-or-nothing)                        |

### Navigation

| Command                                               | Purpose                                                            |
| ----------------------------------------------------- | ------------------------------------------------------------------ |
| `gh stack checkout [stack\|pr\|branch]`               | Check out a stack or branch (interactive picker when no argument)  |
| `gh stack switch`                                     | Interactive picker to switch between branches in the current stack |
| `gh stack up [n]` / `gh stack down [n]`               | Move up (away from trunk) or down (toward trunk) by n branches     |
| `gh stack top` / `gh stack bottom` / `gh stack trunk` | Jump to the top, bottom, or trunk branch                           |

### Key behaviors

- **`gh stack link`** is the right command for this skill's workflow: it registers already-created PRs into a stack without local tracking state, perfect for branches carved by hand.
- **`gh stack merge`** is all-or-nothing: merging a mid-stack PR merges everything below it too. Auto-merge is not supported for stacks.
- **`gh stack sync --prune`** is the cleanup command after merges land — it updates local state and deletes merged branches.
- **Exit code 9** means stacked PRs are not enabled for the repository — fall back to degraded mode (PRs chained by `--base` only).

### Environment variables

| Variable              | Values                  | Purpose                               |
| --------------------- | ----------------------- | ------------------------------------- |
| `GH_STACK_THEME`      | `auto`, `light`, `dark` | Color palette for interactive screens |
| `GH_STACK_HYPERLINKS` | `0`, `1`                | Enable/disable OSC 8 hyperlinks       |
