---
name: address-pr-comments
description: >-
  Address reviewer / Bugbot comments on a PR one at a time: check the PR out
  into its own git worktree, build a one-item-per-comment checklist from inline,
  main-conversation and review-body comments, then hand each comment to a single
  fresh subagent that investigates the claim, writes a short plan file into the
  worktree, fixes it, runs every test suite the project has (unit, integration,
  UI when relevant), makes modular commits and pushes if authorized. One
  subagent at a time so the main thread stays small and every prompt is
  reviewable. Main thread handles 👀 reactions, thread resolution and the
  findings table.
---

# Address PR Comments

Use this skill when the user asks to address, fix, or triage the comments on a PR, whether they come from a human reviewer, Claude's own review, or an automated reviewer such as Cursor Bugbot. It is iterative: run it again whenever a new review lands.

The shape is fixed: **the PR lives in a worktree, every comment is one checklist item, and every item is worked by exactly one subagent at a time.** The main thread never edits code. It discovers comments, prepares the worktree and toolchain, writes each subagent's prompt (so the user can review what the agent was told), collects the report, and updates GitHub. This is not the `serial-subagents` skill; do not load it. There is no orchestrator checklist hand-off, no verifier agent, and no parallelism. Just one worker per comment, run to completion, then the next.

## Inputs

Resolve the PR in this order:

1. Explicit PR number → use it.
2. Explicit branch → `gh pr list --search "head:<branch>" --json number --jq '.[0].number'`.
3. Neither → `gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --json number --jq '.[0].number'`. If nothing, ask.

Set once and reuse:

```
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
PR=<number>
HEAD_BRANCH=$(gh pr view $PR --json headRefName --jq .headRefName)
```

Also settle two policies up front, from the user's words, and write them into the checklist file so every subagent prompt states them:

- **Push policy.** `push-per-comment` when the user said to push (for example "fix, test, then push") or has an ongoing iteration cycle on this PR; otherwise `commit-only`, and ask once at the end.
- **Scope of comments.** All open threads by default. If the user names specific comments, only those.

## Procedure

### 1. Discover the comments (main thread)

Run in parallel:

- `git fetch origin` (also picks up any `cursor/*` autofix branches).
- `gh pr view $PR --json title,body,reviews,headRefName,baseRefName,headRefOid`.
- Inline comments: `gh api repos/$REPO/pulls/$PR/comments --paginate --jq '.[] | select(.in_reply_to_id == null) | {id, path, line: (.line // .original_line), user: .user.login, created_at, body}'`. Replies (`in_reply_to_id != null`) belong to their parent item; read them for context, they are not items.
- Main-conversation comments: `gh api repos/$REPO/issues/$PR/comments --paginate --jq '.[] | {id, user: .user.login, created_at, body}'`. This is a separate endpoint and is easy to miss; a human reviewer's headline objection often lives here.
- Review threads (for resolution state and the `PRRT_…` ids):

```
gh api graphql -f query='
query($owner:String!,$repo:String!,$pr:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$pr){
      reviewThreads(first:100){
        nodes{ id isResolved isOutdated path line
          comments(first:20){ nodes{ databaseId author{login} body } } }
      }
    }
  }
}' -f owner=<owner> -f repo=<repo> -F pr=$PR
```

Skip threads where `isResolved` is true and comments already handled earlier in this conversation. For Bugbot bodies, strip everything before `<!-- DESCRIPTION END -->` and after `<!-- BUGBOT_BUG_ID`. If a review body names a `cursor/<topic>-<hash>` autofix branch, fetch it and note the head sha; it is passed to the relevant subagent as an option, not applied by the main thread.

### 2. Create the worktree and prepare the toolchain (main thread)

Never work the PR in the user's current checkout. Put it in a sibling worktree:

```
MAIN=$(git rev-parse --show-toplevel)
WT=$MAIN/../$(basename $MAIN)-pr-$PR
git worktree add "$WT" "$HEAD_BRANCH"      # add -b only if the branch is not local yet
git -C "$WT" pull --ff-only
```

Then make the project runnable inside the worktree. Environments are untracked and do not come along, so:

- Read the project's `CLAUDE.md`, `AGENTS.md`, `Makefile`, `package.json` (or equivalents) and write down the exact commands for: lint, format, unit tests, integration tests (including how their dependencies boot, for example `make dev-up`, and how to tell they are ready), and UI / frontend gates. These commands go verbatim into every subagent prompt; the subagent must not have to rediscover them.
- Provide the environment: symlink the untracked env from the main checkout (`ln -s "$MAIN/.venv" "$WT/.venv"`, same for `node_modules`) or run the project's bootstrap. Then prove the worktree's own code is what runs: from `$WT`, `.venv/bin/python -c 'import <pkg>; print(<pkg>.__file__)'` must print a path under `$WT`. If it prints the main checkout (editable installs do this), every prompt must say to export `PYTHONPATH=$WT` for Python commands.
- Confirm shared services the integration suite needs are up (for example `docker ps` for the dev database). If the project's own target refuses a stopped container, use the project's documented down/up targets and note the fix in the checklist file.

Create `$WT/.pr-comments/` for the checklist, prompts and per-comment plans, and exclude it from git so a stray add cannot commit it: `echo '.pr-comments/' >> "$MAIN/.git/info/exclude"` (the exclude file is shared by all worktrees).

### 3. Build the checklist (main thread)

Write `$WT/.pr-comments/checklist.md` and show it to the user before any subagent starts. One item per comment, from all three sources. Fields:

| field | meaning |
|---|---|
| `n` | sequential number in this pass |
| `kind` | `inline`, `main`, or `review-body` |
| `comment_id` | REST id (reactions, replies) |
| `thread_id` | `PRRT_…` node id, inline only |
| `location` | `path:line` or `—` |
| `title` | short summary plus severity if the reviewer gave one |
| `state` | `pending` → `in-progress` → `done` / `dismissed` / `blocked` |
| `reaction_id` | the 👀 reaction id while in progress |
| `commit` | sha(s) once landed |

Rules: one item per comment even when two comments describe the same bug (fix once, close both); bot self-corrections attach to the item they correct; order items so that ones touching the same files run consecutively, since a later subagent must start from the earlier one's commit. If one item's fix already closed another (the earlier report says so), verify that claim from the commit before marking the second one done without an agent.

### 4. Work each item with one subagent (main thread orchestrates, subagent executes)

For each `pending` item, in order:

1. Mark it `in-progress` and put 👀 on the comment. Store the reaction id in the checklist.

```
RID=$(gh api -X POST repos/$REPO/pulls/comments/<comment_id>/reactions -f content=eyes --jq .id)    # inline
RID=$(gh api -X POST repos/$REPO/issues/comments/<comment_id>/reactions -f content=eyes --jq .id)   # main conversation
```

2. Write the subagent prompt from the template in **Subagent prompt** below. Fill every placeholder; paste the comment body verbatim; include the reply chain if there is one. Save it to `$WT/.pr-comments/<n>-<slug>.prompt.md` so the user can review what the agent was given.

3. Launch **one** `general-purpose` subagent with that prompt and wait for it. Do not launch the next item's agent until this one has returned. Do not read or edit the worktree yourself while it runs.

4. Read the report. Then, in the main thread:
   - Remove the 👀 on every outcome: `gh api -X DELETE repos/$REPO/pulls/comments/<comment_id>/reactions/$RID` (or the `issues/comments` form).
   - **Fixed and verified** (a commit exists and every suite the agent was told to run reported exit 0): resolve the inline thread with `gh api graphql -f query='mutation($t:ID!){ resolveReviewThread(input:{threadId:$t}){ thread{ isResolved } } }' -f t=<thread_id>`. Main-conversation comments have no thread; their row in the table closes them.
   - **False positive** or **blocked**: do not resolve. Reply on the thread with the agent's reasoning: `gh api repos/$REPO/pulls/$PR/comments -f body='…' -F in_reply_to=<comment_id>`.
   - Record `state`, `commit` and a one-line outcome in the checklist. If the agent reported a suite it could not get green, the item is `blocked`; stop and surface it rather than starting the next item.

5. Next item.

### 5. Wrap up (main thread)

- If the push policy was `commit-only`, ask once whether to push, then `git -C "$WT" push origin $HEAD_BRANCH`.
- Emit the findings table (below).
- Leave the worktree in place and print its path; remove it (`git worktree remove "$WT"`) only when the user says the PR is done.

## Subagent prompt

Every subagent gets a self-contained brief; it knows nothing about this conversation. The template is the contract. Keep the section headings so the user can diff prompts across items.

```
You are fixing one review comment on GitHub PR #<PR> (<title>) in the worktree at <WT>, branch `<HEAD_BRANCH>`. Work only in that directory. Run `git -C <WT> status -sb` first; the tree must be clean and in sync with origin<, at or after commit <sha of the previous item> if applicable>. Read <WT>/AGENTS.md and <WT>/CLAUDE.md (if present) and follow them; <toolchain notes learned in step 2: venv path, PYTHONPATH requirement, package manager>.

## The comment (verbatim)
Author: <user>  Location: <path>:<line>  Thread: <thread_id or "main conversation">
<comment body, verbatim, plus any replies in order>
<if a Bugbot autofix branch exists: "An autofix commit exists at origin/<cursor branch> (<sha>). You may cherry-pick it if, after investigation, it is exactly the right fix; keep its author and body in that case. Otherwise write the fix yourself.">

## Step 1: investigate before believing
Open the cited code and trace the path the comment describes. Confirm or refute every factual claim in it against the actual code and, where possible, by running it (a small script, a failing test, a CLI invocation). Decide: REAL, REAL (pre-existing), or FALSE POSITIVE. A comment is not right because it is confident.

## Step 2: write the plan file, however small
Write <WT>/.pr-comments/<n>-<slug>.plan.md with these headings: Claim, Evidence (what you ran and saw, with file:line), Verdict, Plan (numbered steps), Tests to add or change, Suites to run. Write it before changing any code and update it if the plan changes. The file is deliberately untracked; never `git add` it.

## Step 3: fix
If FALSE POSITIVE, stop after the plan file and report. Otherwise implement the plan. Keep to the comment's scope; note neighbouring problems in the report instead of fixing them. Add or change tests so the exact failure the comment describes is covered, and prefer tests that exercise the real entry point (CLI, HTTP, subprocess) over tests that re-implement the code under test. <project-specific constraints, e.g. "Do not touch <file> beyond X; item <m> owns it.">

## Step 4: run everything
Run, in this order, and fix anything that fails (never skip, deselect, or ignore a failing test):
- format and lint: <exact commands>
- unit: <exact command>; this project <does / does not> print a pytest summary line, so check the exit code
- integration: <exact command, plus how to boot its dependencies and how to tell they are ready>
- UI / frontend gate: <exact command>; run only if your change touched <paths>, and say so explicitly in the report if you skipped it and why
Return only after every applicable suite has run. Report exact exit codes.

## Step 5: commit
Commit with the git CLI as the machine's configured git user. One logical change per commit; split the fix from unrelated cleanup. Stage with explicit `git add <path>`, never `git add -A`. Message: one line, imperative mood, capitalized first word, no trailing period, no prefix, no body, no trailers, no Co-Authored-By, no "Generated with" line. Do not pass --author, --amend, or --no-verify. (Exception: a cherry-picked autofix keeps its original author and body.) Verify with `git log -n 3 --pretty=fuller`.

## Step 6: push
<"Push with `git push origin <HEAD_BRANCH>` (plain, no force) and confirm `git status -sb` shows the branch in sync." | "Do not push. Leave the commits on the branch.">

## Report back
Return, in this order: Verdict; commit hashes and subjects (or "no commit" for a false positive); files changed; the plan file path; every suite you ran with its exit code and anything you fixed to get it green; anything you deliberately left out or noticed but did not touch; and, if blocked, exactly what is blocking. Do not post anything to GitHub other than the push.
```

## Output format

Always emit this table, even for one item:

```
| # | Source | Finding | Verdict | Thread | Commit | Why |
|---|---|---|---|---|---|---|
```

- **Source**: `inline path:line`, `main`, or `review body`.
- **Finding**: short title plus severity if the reviewer gave one.
- **Verdict**: `**REAL**`, `**REAL (pre-existing)**`, `**FALSE POSITIVE**`, or `**BLOCKED**`.
- **Thread**: `resolved`, `left open`, or `n/a` (main comments and review bodies).
- **Commit**: short sha(s), or `—`.
- **Why**: one or two sentences with file:line where useful; for a false positive, what was wrong with the claim.

After the table: the suites that ran per item with exit codes, the worktree path, whether the branch was pushed, and confirmation that every 👀 was cleared.

## Anti-patterns

- Working in the user's checkout instead of the worktree, or running the worktree's tests against the main checkout's package because the editable install was not checked.
- Launching more than one subagent at once, or starting the next item before the current agent has returned. Later items depend on earlier commits.
- Fixing anything in the main thread. If the agent comes back blocked, surface it; do not finish it yourself.
- Prompts that say "run the tests" without the exact commands. Discover them once in step 2 and paste them.
- Trusting the comment without the investigation step, or trusting the subagent's "tests pass" without exit codes in its report.
- Batching 👀 reactions, leaving a stale 👀, or resolving a thread whose fix was partial, unverified, or a false positive.
- Skipping `issues/$PR/comments`; the main-conversation comments are a separate endpoint.
- Committing `.pr-comments/`, pushing when the policy was `commit-only`, force-pushing, or adding Claude attribution to commits.

## Quick checklist

- [ ] PR resolved; push policy and comment scope settled with the user
- [ ] Inline, main-conversation, and review-body comments fetched; resolved threads skipped
- [ ] Worktree created at `<repo>-pr-<PR>`, env provided, package import verified to come from the worktree, services for integration tests up
- [ ] Exact lint / unit / integration / UI commands written down once and pasted into every prompt
- [ ] Checklist file written and shown to the user; `.pr-comments/` excluded from git
- [ ] Per item: 👀 on, prompt saved to `.pr-comments/`, one subagent launched and awaited, 👀 off, resolve or reply, checklist updated
- [ ] Every subagent wrote its plan file before editing and reported exit codes for every suite
- [ ] Commits follow the single-line imperative style with no attribution trailers
- [ ] Table emitted; worktree path reported; pushed only per the agreed policy
