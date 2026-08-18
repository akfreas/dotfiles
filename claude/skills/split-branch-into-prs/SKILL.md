---
name: split-branch-into-prs
description: >-
  Split one long-lived branch into several small, independently-reviewable
  feature branches, each committed, build-verified, and opened as its own PR.
  Unlike recompose-branch (which rewrites one branch's history in place), this
  leaves the original branch untouched and carves its cumulative diff into
  per-feature branches — independent off the base where changes are cleanly
  separable, stacked where they share files. Use when the user asks to "split
  this branch into PRs", "break the branch into smaller reviewable chunks", "one
  PR per feature", "decompose / carve up this branch", or "turn this big branch
  into stacked PRs".
---

# Split a branch into per-feature branches and PRs

Use this when a branch has grown into several distinct features and the user wants each shipped as its own small, reviewable PR. The output is N new branches (one per feature), each building on its own, each opened as a PR. The original branch is never modified.

This borrows the base-resolution and read-only pre-flight discipline from `recompose-branch`, but it does **not** rewrite the source branch. It borrows nothing else from it; PR creation defers to `create-pr`.

## Core principles

- **The source branch is read-only.** Create new branches; never reset, rebase, or force-update the original. There is no backup step because nothing destructive happens to it.
- **The final tree is the source of truth.** Every output branch is carved from the source branch's *cumulative diff vs the base*, not from its commit history (the iteration order is noise, and cherry-picking interleaved commits conflicts).
- **Each output branch must build on its own.** A PR that doesn't compile isn't reviewable. Verify every branch before committing it.
- **The split must be faithful.** The union of the output branches must reproduce the source branch's tree exactly (modulo intentionally-dropped noise). Prove it with a diff at the end.
- **Only `git add` / `git commit` / `git checkout -c` / `git checkout <ref> -- <path>` / `git push` write anything.** No `reset`, `rebase`, `merge`, `cherry-pick`, `revert`, or force-push. No `git add -A` / `git add .` (untracked cruft in the repo root must not leak into feature branches).

## Argument handling

Optional argument names the base ref. No argument → `origin/main`. A bare name → treat as `origin/<name>` (the remote tip), matching `create-pr`'s convention; say so once. Do not `git fetch` to refresh it unless the user asks — the comparison is against local state; `create-pr` will fetch at PR time.

## Pre-flight (all read-only; abort and report on any failure)

1. `git rev-parse --is-inside-work-tree` — inside a repo.
2. Current branch is **not** the base. Recomposing the base into itself is meaningless.
3. `git status --porcelain` — working tree clean for tracked files. Untracked files are tolerated but **list them** and make sure none leak into feature branches (never `git add -A`).
4. `git rev-parse --verify <base>` — base resolvable locally.
5. `git rev-list --count <base>..HEAD ≥ 1` and `git diff --quiet <base>..HEAD` reports a difference — the branch is actually ahead with a non-empty diff.

## Step 1 — Analyze the diff and cluster it into features

Work from the cumulative diff, `SOURCE = <the long branch>`:

- `git diff --name-status <base>..SOURCE` — every changed/added/deleted file.
- `git log --oneline <base>..SOURCE` — read commit subjects **only** for intent/labels, never to drive the split.
- For each file, decide which feature(s) touch it. Most files belong to exactly one feature (a new file, a deleted file, a module only that feature edits). These are **single-feature files**.
- Some files are edited by **multiple** features (a shared manager, the app entry point, a cross-cutting utility, an interface/protocol and its implementors, a shared strings/manifest file). For each shared file, pull its diff and attribute **each hunk** to a feature: `git diff <base>..SOURCE -- <file>` and read the `@@` hunks. A single hunk can even mix two features (e.g. two methods added back-to-back) — note that; you'll split it by hand later.

Produce a feature list: for each feature, a short name, the single-feature files it owns, and its slice of each shared file. Watch for **dependencies**: if feature B's code references a symbol that feature A introduces (a new type, a new interface member), B depends on A. Record these — they force ordering.

Present this clustering to the user before carving anything. If the split is non-obvious, this is worth an `AskUserQuestion` on how finely to split (e.g. keep one large cohesive feature whole vs. sub-split it).

## Step 2 — Decide the topology (independent vs. stacked)

Two shapes, usually mixed:

- **Independent** — a feature whose files are all single-feature (or whose shared-file hunks don't depend on another feature) branches directly off the base and its PR targets the base. Cleanest; prefer it wherever the feature genuinely stands alone.
- **Stacked** — features that co-edit the same files, or depend on each other's symbols, form a chain: `base → A → B → C`, each branch based on the previous, each PR targeting the branch below it.

The key insight that makes stacking cheap:

> For any file touched by several features, exactly one branch can take that file **wholesale** (a plain `git checkout SOURCE -- file`): the branch that sits **above all the other features that touch it** in the stack, because by then the base already contains every other feature's changes to that file, so the final version *is* correct. Every branch **below** that point needs a hand-built partial version of the file. So: **order the stack to put the feature with the largest shared-file footprint at the top** — it gets the big files for free; the smaller features below do the cheaper partial surgery.

Dependencies also constrain order: a feature must sit above every feature it depends on. Thread a shared dependency (e.g. an identity/util module several features need) low in the stack so everything above inherits it.

When entanglement is real, confirm the topology with `AskUserQuestion` — it determines each PR's base branch, which the user cares about. Offer: "stack them (cheapest, PRs chain)" vs. "maximum independence off the base (more hand-surgery stripping other features out)". Recommend stacking for heavily-shared files.

## Step 3 — Find the build/verify command

The skill is language-agnostic; discover how this project builds and tests before carving:

- Look for the obvious: `Makefile`, `package.json` scripts, `Cargo.toml`, an Xcode scheme (`xcodebuild -list`), a `*.gradle`, a CI config that names the build/test command.
- Prefer the **cheapest command that actually compiles the changed code** for fast iteration, and a fuller one (including tests) for final verification of each branch. Compiling the test target matters when a branch adds/edits tests or changes an interface every mock must satisfy.
- **Verify results explicitly.** Grep the build output for the real success/failure marker (e.g. `BUILD SUCCEEDED` / `BUILD FAILED`, a non-zero test summary). **Never trust the exit code of a piped command** (`xcodebuild ... | grep ...` returns grep's status, not the build's) — capture output to a file and check it, or check `${PIPESTATUS[0]}`.

## Step 4 — Carve each branch (build the stack base-up)

For each feature, in dependency/stack order (independents off base; stacked ones off their parent branch):

1. `git checkout -c <feature-branch> <parent>` where `<parent>` is the base for an independent feature or the branch below it in the stack.
2. **Single-feature files** — bring them in wholesale: `git checkout SOURCE -- <file>...`. Deletions: `git rm <file>`.
3. **Shared files, top-of-their-footprint branch** — wholesale is correct here too (`git checkout SOURCE -- <file>`), because the base already has every other feature's slice.
4. **Shared files, a lower branch** — hand-build the partial: start from the parent's version and apply **only this feature's hunks**. Targeted edits are usually more reliable than a filtered `git apply` when hunks are mixed; the compiler is your safety net. Keep each partial a strict subset of the final file so the branch above can still take it wholesale.
5. **Interface / protocol ripple** — when a feature adds a member to an interface, **every implementor in that branch** must gain it: the real implementation plus all mocks/fakes/preview doubles/test stubs. Grep for conformers/implementors; a missing stub fails the build.
6. **Shared test infrastructure** (an in-memory fake, a test double) must live in the **lowest** branch that needs it, so branches above inherit it rather than duplicating it.
7. **Project-manifest surgery** (files that must be registered outside the source tree — an Xcode `project.pbxproj`, a `.csproj`, a `CMakeLists.txt`, a bundling manifest): use the ecosystem's **proper tool**, not hand-editing. For iOS, the `xcodeproj` Ruby gem is reliable and produces minimal diffs — remove refs for deleted files, add refs for new files to the right group and target(s), then verify the reference counts. Hand-editing UUID tables is fragile; only do it to mirror exact known lines when no tool exists.
8. **Files shared with a feature you are NOT including on this branch** — do a partial, not wholesale. Example: a telemetry file that both feature X and feature Y append to; a branch that has X but not Y must take X's additions only, or it will reference a symbol Y introduces and fail to build.
9. **Build and verify** (Step 3). Fix until green — compiler errors are precise; add the missing stub, the missing manifest entry, the missing dependency file.
10. **Commit.** One commit per feature is the natural unit here (this is one-PR-per-feature, not modular-commits). Use a single-line imperative subject; no attribution trailers. Stage with `git add -u` plus explicit `git add <new-file>` paths — never `git add -A` (keeps repo-root untracked cruft out).

## Step 5 — Prove the split is faithful

Diff the **top of the stack** against the source branch: `git diff <top-branch> SOURCE --name-only`. The only files that may differ are those owned by the **independent** branches (which aren't in the stack) and any hunks you intentionally routed elsewhere (e.g. a telemetry file's other-feature hunk). Anything else differing means a branch is missing content — investigate before opening PRs. State the result explicitly: "branches A + B + <stack-top> reproduce the source exactly, modulo <known cosmetic delta>."

## Step 6 — Push and open one PR per branch

Push every branch first (`git push -u origin <branch>` for each) — stacked PRs need their base branch present on the remote before the PR can target it.

Then open one PR per branch **following the `create-pr` skill's rules** for base-branch convention, title/description generation, the strict concise body format (lead sentence, optional bug/limitation bullets, `Changes` bullets, no formatting beyond backticks, no footers/trailers/emojis — see `create-pr`), and the `gh pr create` invocation with a HEREDOC body. Deviations from `create-pr` for this skill:

- **Base per branch:** independent branches target the base (e.g. `main`); each stacked branch targets **the branch below it**, not `main`. `gh pr create --base` takes the bare branch name.
- **Batch mode:** the user has already opted into "all PRs"; you may generate titles/bodies for all branches and open them without the per-PR interactive approval loop, unless the user asked to review each. Still honor `create-pr`'s body *format* and banned-words rules.
- **State the merge order** in the summary: independents merge any time; the stack merges bottom-up, and each merge auto-retargets the next PR's base to the base branch.

Return every PR URL.

## Anti-patterns

- Rewriting or resetting the source branch. It stays put; this skill only creates new branches.
- Driving the split from commit history / cherry-picking interleaved commits. Carve from the cumulative diff instead.
- `git add -A` / `git add .` — drags untracked repo-root files into a feature branch.
- Trusting a piped build command's exit code. Check the real success marker in captured output.
- Hand-editing a project manifest's UUID tables when a proper tool exists.
- Committing a branch before it builds. Every branch is independently reviewable → independently buildable.
- Putting the small feature at the top of the stack and the big shared-file feature at the bottom — inverts the wholesale/partial work and maximizes hand-surgery.
- Skipping the faithfulness diff. It's the only proof nothing was lost.

## Quick checklist

- [ ] Base resolved; source branch ahead with a non-empty diff; working tree clean (untracked noted)
- [ ] Diff clustered into features; single-feature vs shared files identified; shared-file hunks attributed; dependencies recorded
- [ ] Topology chosen (independent vs stacked), largest-shared-file feature near the top, dependencies respected, confirmed with the user when entanglement is real
- [ ] Build/verify command found; success checked explicitly (not via a piped exit code)
- [ ] Each branch carved base-up: wholesale for single-feature + top-of-footprint files, partial for lower shared files, interface ripple handled, shared infra placed low, manifest surgery via a real tool
- [ ] Each branch builds (and its tests compile when it touches them) before committing; one commit per feature; no `git add -A`
- [ ] Faithfulness diff proves union == source
- [ ] All branches pushed; one PR per branch per `create-pr` rules; stacked PRs based on their parent branch; merge order stated
