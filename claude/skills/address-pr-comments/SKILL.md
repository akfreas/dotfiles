---
name: address-pr-comments
description: >-
  Pull Bugbot / reviewer comments on the current PR into a checklist — inline
  review comments and main-conversation comments alike — then work them one at a
  time: react 👀 when starting, judge each as real or false positive, cherry-pick
  the proposed autofix or write modular commits, then drop the reaction and
  resolve the thread only if it was actually addressed. Reports findings as a table.
---

# Address PR Comments

Use this skill when the user asks to look at PR comments — typically from Cursor Bugbot or a similar automated reviewer — and either dismiss them, cherry-pick proposed autofixes, or hand-write fixes. The skill is iterative: run it again every time a new Bugbot pass adds findings (each pass creates a new `cursor/<topic>-<hash>` branch on the remote).

Every comment becomes a checklist item, and each item carries a visible lifecycle on GitHub: 👀 while you're working it, no reaction and a resolved thread once the fix is committed.

## When to use

- The user references PR comments, Bugbot findings, or a `cursor/*` autofix branch.
- The user asks "are these real?" / "address the comments" / "look at the new findings".
- You see a new Bugbot review since the last skill invocation in this conversation.

## Inputs

The user may name a PR number, a cursor branch, or neither. Resolve in this order:

1. Explicit PR number → use it.
2. Explicit cursor branch → look up the PR with `gh pr list --search "head:<branch>"` OR follow the autofix branch's `compare/<base>...<branch>` link in the review body.
3. Neither → derive the PR for the current branch: `gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --json number --jq '.[0].number'`. If nothing, ask the user.

Set these once and reuse them in every command below:

```
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
PR=<number>
```

## Procedure

### 1. Fetch and discover

Run in parallel:

- `git fetch origin` — pick up any new `cursor/*` branches the Bugbot pipeline pushed since last time.
- `gh pr view $PR --json reviews,headRefName,baseRefName` — review summary including the latest Bugbot body and its autofix branch reference.
- **Inline comments** — `gh api repos/$REPO/pulls/$PR/comments --paginate --jq '.[] | {id, path, line: .original_line, user: .user.login, created_at, body}'`. The bodies are large — strip everything before `<!-- DESCRIPTION END -->` and after `<!-- BUGBOT_BUG_ID` for a clean read.
- **Main-conversation comments** — `gh api repos/$REPO/issues/$PR/comments --paginate --jq '.[] | {id, user: .user.login, created_at, body}'`. These are a *separate* endpoint from the inline ones and are easy to miss; a human reviewer's most important note is often here rather than on a line.
- **Review threads** (needed for resolution, and to see what's already resolved):

```
gh api graphql -f query='
query($owner:String!,$repo:String!,$pr:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$pr){
      reviewThreads(first:100){
        nodes{
          id isResolved isOutdated path line
          comments(first:20){ nodes{ databaseId author{login} body } }
        }
      }
    }
  }
}' -f owner=<owner> -f repo=<repo> -F pr=$PR
```

The thread's `id` (a `PRRT_…` node id) is what resolves it; `comments.nodes[].databaseId` is what maps a thread back to an inline comment id.

Identify which findings are **new since the last pass** by filtering on `created_at`, and skip threads where `isResolved` is already `true`. The conversation almost always has a prior timestamp to compare against — use it.

### 2. Build the checklist

Before touching any code, turn the fetched comments into a checklist and show it to the user. **One item per comment**, drawn from all three sources:

- each inline review comment (`pulls/$PR/comments`),
- each main-conversation comment (`issues/$PR/comments`),
- any review body (`gh pr view --json reviews`) that raises actionable feedback not repeated in an inline comment.

Record the checklist in the session todo list *and* in a durable scratch file (`pr-<PR>-comments.md` in the scratchpad directory) so a fresh context can pick it up. Each item holds:

| field | meaning |
|---|---|
| `kind` | `inline`, `main`, or `review-body` |
| `comment_id` | the REST id used for reactions |
| `thread_id` | the `PRRT_…` node id — inline only |
| `location` | `path:line`, or `—` for main comments |
| `title` | short summary + severity |
| `state` | `pending` → `in-progress` → `done` / `dismissed` |

Filtering rules:

- Skip resolved threads and comments already handled in an earlier pass in this conversation.
- Do **not** merge two comments into one item even when they describe the same underlying bug — each has its own reaction and its own thread. Fix once, then close both items.
- Bot self-corrections ("Bugbot Autofix determined this is a false positive") attach to the item they correct; they are not their own item.

Work the checklist **strictly one item at a time**, start to finish, before opening the next. Do not batch the reactions.

### 3. Identify the autofix branch (if any)

Bugbot review bodies contain a line like:

```
compare/<base>...cursor/<topic>-<hash>?expand=1
```

That `cursor/...` is the autofix branch. Fetch it:

```
git fetch origin cursor/<topic>-<hash>
git log --oneline -5 origin/cursor/<topic>-<hash>
```

The latest commit on that branch is the proposed autofix. Read it with `git show <sha>` and the per-file diff before judging.

### 4. Open the item — react 👀

The moment you start work on a checklist item (before reading the cited code), mark it `in-progress` and put the eyes on it. Capture the returned reaction id — you need it to remove the reaction later.

Inline comment:

```
RID=$(gh api -X POST repos/$REPO/pulls/comments/<comment_id>/reactions -f content=eyes --jq .id)
```

Main-conversation comment:

```
RID=$(gh api -X POST repos/$REPO/issues/comments/<comment_id>/reactions -f content=eyes --jq .id)
```

Store `RID` alongside the item in the scratch file. Review-body items have no reaction target — note that and carry on.

If a re-run finds a stale 👀 from an interrupted session, reuse its id (`gh api repos/$REPO/pulls/comments/<comment_id>/reactions --jq '.[] | select(.content=="eyes" and .user.login=="'"$(gh api user --jq .login)"'") | .id'`) rather than posting a second one.

### 5. Verify the finding against the actual code

**Do not trust descriptions blindly.** Bugbot occasionally mislabels things — sometimes it even self-acknowledges false positives in a follow-up comment on the same line. For each finding:

1. Open the file at the cited line range.
2. Verify the code matches the description's claim.
3. Trace the runtime path the description describes. If it doesn't actually fire (e.g. the cited branch is unreachable, or the condition never occurs for this app's config), call it a false positive.
4. Check for a self-correction comment from `cursor` on the same line — those start with "Bugbot Autofix determined this is a false positive" and explain why.

Common false-positive patterns:
- Index math on `Path.parents` — Bugbot has gotten this wrong before.
- Bugs in "dead" branches that the surrounding code prevents from being reached.
- Concerns about non-TTY behavior on a script that's only ever run interactively (still worth fixing if cheap, but not "high severity").

### 6. Decide and fix

For each finding pick one of:

- **Cherry-pick** the autofix commit as-is — the diff is small, surgical, and matches the bug. Preserves `Cursor Agent` author.
- **Cherry-pick and split** — autofix bundles unrelated fixes; split into modular commits afterward via `git reset --soft` + `git add -p`.
- **Manual fix** — autofix is wrong, over-scoped, or breaks something. Write the fix yourself.
- **Dismiss** — false positive. Note the reason in the table; do not commit anything.

Aim for **one commit per comment**. That is what makes the reaction/resolution lifecycle line up with history: a reviewer can point at exactly the commit that answered their comment. Only depart from it when a single fix genuinely closes two comments, or when the autofix legitimately spans more than one logical change (then split it, per below).

#### Commit style for skill-authored commits

Any commit **this skill writes itself** — every **manual fix**, and each commit produced when **splitting** a cherry-pick — MUST follow the `modular-commits` skill's rules:

- **No Claude attribution.** No `Co-Authored-By: Claude` trailers, no "Generated with Claude Code" footer, no `--author` override — the commit is attributed to the machine's configured git user.
- **Single-line imperative subject.** Capitalized first word, no trailing period, no `feat:`/`fix:` prefix, **no body** — match the canonical examples in the `modular-commits` skill.
- **Modular.** One logical change per commit; stage deliberately with `git add <path>` / `git add -p`, never `git add -A`.

The **cherry-pick (as-is)** path is the one documented exception: it keeps the `Cursor Agent <cursoragent@cursor.com>` author **and** the original commit's bullet body (see §7). The no-body / machine-author rules apply only to commits this skill authors.

### 7. Cherry-pick mechanics

```
git cherry-pick <sha>                  # clean apply
git cherry-pick --no-commit <sha>      # if you anticipate splitting
```

When splitting (`--no-commit`, or `git reset --soft` after a clean apply), the resulting commits are **skill-authored** — re-stage with `git add -p` and write each one in the `modular-commits` style: single-line imperative subject, no body, no Claude attribution, machine git user. Do not carry the autofix's author or bullet body onto split commits.

If it conflicts (very common when prior commits renumber things like preflight `[N/M]` labels):

1. Resolve the conflict markers, preserving HEAD's structural choices (numbering, ordering) and folding in the autofix's behavioral changes.
2. `git add <files>`.
3. `git commit --author="Cursor Agent <cursoragent@cursor.com>" -m "$(git show <sha> --pretty=format:'%s%n%n%b' --no-patch)"` — preserves the original author and message body.

**Do not** strip the bullet body from autofix commit messages when cherry-picking — they document the fix scope and are valuable history. This is the one exception to the `modular-commits` skill's "no body" rule.

### 8. Verify the fix

After every cherry-pick or manual fix, before closing the item:

- Parse Python files: `python -c "import ast; ast.parse(open('<file>').read())"`.
- Run the script's dry-run mode if it has one (e.g. `release.py --dry-run --skip-preflights`).
- Run the dedicated venv smoke test that other scripts in the area use, if any.

An item is **successfully addressed** only when a commit exists on the branch that changes the cited code *and* this verification passed. Anything less — a partial fix, a fix you couldn't verify, a change deferred to a follow-up — is not addressed.

### 9. Close the item — drop 👀, then resolve

Once the commit(s) for this comment are made:

1. **Always remove the reaction**, whatever the outcome. A leftover 👀 reads as "still in progress" to everyone watching the PR.

```
gh api -X DELETE repos/$REPO/pulls/comments/<comment_id>/reactions/$RID     # inline
gh api -X DELETE repos/$REPO/issues/comments/<comment_id>/reactions/$RID    # main conversation
```

2. **Resolve the thread if and only if the comment was successfully addressed** per §8:

```
gh api graphql -f query='
mutation($t:ID!){ resolveReviewThread(input:{threadId:$t}){ thread{ isResolved } } }' -f t=<thread_id>
```

Do **not** resolve when the verdict was `FALSE POSITIVE`, when the fix is partial or deferred, or when you're unsure. Reply to the thread with the reasoning instead (`gh api repos/$REPO/pulls/$PR/comments -f body='…' -F in_reply_to=<comment_id>`) and leave it open for the human to close.

**Resolution applies to inline review threads only** — those are the ones carrying a *Resolve conversation* button. Main-conversation comments have no thread behind them and are closed out by the reaction removal plus their row in the report; say so explicitly rather than leaving the user to wonder why they weren't resolved. (GitHub's *Hide comment → Resolved* — `minimizeComment` with the `RESOLVED` classifier — does work on them, but it collapses the comment out of view, so don't reach for it unless the user asks.)

3. Mark the checklist item `done` / `dismissed` in the scratch file and the todo list, then open the next item at §4.

### 10. Push (only when the user asks, or when this is part of an ongoing PR-iteration cycle)

`git push origin <branch>`. Don't push without confirmation if the user hasn't established that this is an ongoing review-iteration cycle on the current PR.

Note that resolving threads and reacting are **outward-facing writes on the PR** — they're part of this skill's normal operation once the user has asked you to address comments, but don't run them speculatively on a PR the user only asked you to read.

## Output format

Always emit a table with these exact columns:

```
| # | Source | Finding | Verdict | Thread | Why |
|---|---|---|---|---|---|
```

- **#** — sequential number (`1`, `2`, …) within this pass. Do not reuse numbers across passes; if a new pass has 2 findings, they're `A` / `B` (or `1` / `2` with a header noting "new findings").
- **Source** — `inline path:line`, `main`, or `review body`.
- **Finding** — short title + severity in parens. Match what Bugbot used (e.g. `HIGH`, `MED`).
- **Verdict** — one of: `**REAL**`, `**REAL (pre-existing)**`, `**FALSE POSITIVE**`. Bold the verdict.
- **Thread** — `resolved` or `left open` for inline threads; `n/a` for main comments and review bodies, which have no thread to resolve.
- **Why** — one or two sentences. Cite specific file:line where useful. If false positive, say what was wrong with the analysis.

After the table, list the resolution action(s) taken (cherry-pick SHA, manual commit SHA, or "dismissed"). Then a one-line summary of post-change verification (parse + dry-run + whatever else), and confirm that every 👀 reaction has been cleared.

### Example

```
| # | Source | Finding | Verdict | Thread | Why |
|---|---|---|---|---|---|
| 1 | inline `localize.py:55` | Localizer targets wrong store version (HIGH) | **REAL** | resolved | `localize.py:55-79` filters versions to live/in-review; release picks PREPARE_FOR_SUBMISSION → metadata lands on the live version. |
| 2 | inline `release.py:12` | REPO_ROOT one directory too high (MED) | **FALSE POSITIVE** | left open | Bugbot self-acknowledged. `SCRIPT_DIR.parents[3]` IS the repo root (verified via filesystem). |
| 3 | main | Please gate the push behind a confirmation | **REAL** | n/a | Added the prompt in `release.py:210`. Main-conversation comment — no thread to resolve. |

Cherry-picked `a198f39e` from `cursor/encameracore-release-issues-05f0` for #1; `7c1d044` hand-written for #3. Verified: both files parse, `--dry-run --skip-preflights` shows the same plan as before. All 👀 reactions cleared.
```

## Anti-patterns

- **Don't skip the main-conversation comments.** `pulls/$PR/comments` returns only inline ones; a reviewer's headline objection often lives in `issues/$PR/comments` and gets silently dropped.
- **Don't batch the reactions.** 👀 goes on when you open one item and comes off when its commit lands — reacting to everything up front tells the reviewer nothing.
- **Don't leave a stale 👀.** Remove it on every path, including dismissals and items you hand back to the user.
- **Don't resolve a thread you didn't actually fix.** Resolution is a claim that the code changed and was verified; false positives get a reply and stay open for a human.
- **Don't trust descriptions without reading the code.** Bugbot has been wrong; verify every "real" claim against the actual cited lines before committing a fix.
- **Don't push without asking** unless the user has clearly established an ongoing iteration cycle on the PR (multiple back-and-forth pushes already in this conversation).
- **Don't strip the autofix commit's body** when cherry-picking — preserve the bullet list so future readers understand what the commit fixed.
- **Don't rewrite the author** of a cherry-picked autofix. Keep `Cursor Agent <cursoragent@cursor.com>` as the author; you'll appear as the committer automatically.
- **Don't skip the table.** Even for one finding, render the table. Consistency matters because the user will compare across passes.
- **Don't squash multiple Bugbot passes into one commit.** Each pass is its own cherry-pick (or set of commits), so the PR history shows which findings were addressed when.

## Quick checklist

- [ ] Fetched `origin` and the `cursor/<...>` branch named in the latest review
- [ ] Pulled inline comments, main-conversation comments, and review threads (GraphQL) — filtered to those new since the last pass and not already resolved
- [ ] Built a one-item-per-comment checklist in the todo list and a durable scratch file, and showed it to the user
- [ ] Worked items one at a time: 👀 on open, verify, fix, verify, 👀 off, resolve
- [ ] Verified each finding against the actual cited code (false positives identified)
- [ ] Cherry-picked or hand-fixed per the per-finding decision, one commit per comment where possible
- [ ] Preserved `Cursor Agent` authorship on cherry-picks (with the bullet body intact)
- [ ] Skill-authored commits (manual fixes + splits) follow `modular-commits`: single-line imperative, no body, no Claude attribution, machine git user
- [ ] Parsed / dry-ran the affected scripts post-change
- [ ] Resolved only the threads that were actually addressed; replied on the rest
- [ ] No 👀 reactions left behind
- [ ] Reported findings as a Markdown table with the six columns above
- [ ] Confirmed with the user before pushing (unless already in an iteration cycle)
