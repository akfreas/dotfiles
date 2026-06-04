---
name: address-pr-comments
description: >-
  Pull Bugbot / reviewer comments on the current PR, judge each one as real or
  false positive, and either cherry-pick the proposed autofix, split it into
  modular commits, or write a manual fix. Reports findings as a table.
---

# Address PR Comments

Use this skill when the user asks to look at PR comments — typically from Cursor Bugbot or a similar automated reviewer — and either dismiss them, cherry-pick proposed autofixes, or hand-write fixes. The skill is iterative: run it again every time a new Bugbot pass adds findings (each pass creates a new `cursor/<topic>-<hash>` branch on the remote).

## When to use

- The user references PR comments, Bugbot findings, or a `cursor/*` autofix branch.
- The user asks "are these real?" / "address the comments" / "look at the new findings".
- You see a new Bugbot review since the last skill invocation in this conversation.

## Inputs

The user may name a PR number, a cursor branch, or neither. Resolve in this order:

1. Explicit PR number → use it.
2. Explicit cursor branch → look up the PR with `gh pr list --search "head:<branch>"` OR follow the autofix branch's `compare/<base>...<branch>` link in the review body.
3. Neither → derive the PR for the current branch: `gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --json number --jq '.[0].number'`. If nothing, ask the user.

## Procedure

### 1. Fetch and discover

Run in parallel:

- `git fetch origin` — pick up any new `cursor/*` branches the Bugbot pipeline pushed since last time.
- `gh pr view <PR> --json reviews,headRefName,baseRefName` — review summary including the latest Bugbot body and its autofix branch reference.
- `gh api repos/<owner>/<repo>/pulls/<PR>/comments --paginate` — the inline per-finding comments (the table source). Pipe through `jq` to extract `{id, path, original_line, body}`. The bodies are large — strip everything before `<!-- DESCRIPTION END -->` and after `<!-- BUGBOT_BUG_ID` for a clean read.

Identify which findings are **new since the last pass** by filtering on `created_at`. The conversation almost always has a prior timestamp to compare against — use it.

### 2. Identify the autofix branch (if any)

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

### 3. Verify each finding against the actual code

**Do not trust descriptions blindly.** Bugbot occasionally mislabels things — sometimes it even self-acknowledges false positives in a follow-up comment on the same line. For each finding:

1. Open the file at the cited line range.
2. Verify the code matches the description's claim.
3. Trace the runtime path the description describes. If it doesn't actually fire (e.g. the cited branch is unreachable, or the condition never occurs for this app's config), call it a false positive.
4. Check for a self-correction comment from `cursor` on the same line — those start with "Bugbot Autofix determined this is a false positive" and explain why.

Common false-positive patterns:
- Index math on `Path.parents` — Bugbot has gotten this wrong before.
- Bugs in "dead" branches that the surrounding code prevents from being reached.
- Concerns about non-TTY behavior on a script that's only ever run interactively (still worth fixing if cheap, but not "high severity").

### 4. Decide per finding

For each finding pick one of:

- **Cherry-pick** the autofix commit as-is — the diff is small, surgical, and matches the bug. Preserves `Cursor Agent` author.
- **Cherry-pick and split** — autofix bundles unrelated fixes; split into modular commits afterward via `git reset --soft` + `git add -p`.
- **Manual fix** — autofix is wrong, over-scoped, or breaks something. Write the fix yourself.
- **Dismiss** — false positive. Note the reason in the table; do not commit anything.

### 5. Cherry-pick mechanics

```
git cherry-pick <sha>                  # clean apply
git cherry-pick --no-commit <sha>      # if you anticipate splitting
```

If it conflicts (very common when prior commits renumber things like preflight `[N/M]` labels):

1. Resolve the conflict markers, preserving HEAD's structural choices (numbering, ordering) and folding in the autofix's behavioral changes.
2. `git add <files>`.
3. `git commit --author="Cursor Agent <cursoragent@cursor.com>" -m "$(git show <sha> --pretty=format:'%s%n%n%b' --no-patch)"` — preserves the original author and message body.

**Do not** strip the bullet body from autofix commit messages when cherry-picking — they document the fix scope and are valuable history. This is the one exception to the `modular-commits` skill's "no body" rule.

### 6. Verify

After every cherry-pick or manual fix:

- Parse Python files: `python -c "import ast; ast.parse(open('<file>').read())"`.
- Run the script's dry-run mode if it has one (e.g. `release.py --dry-run --skip-preflights`).
- Run the dedicated venv smoke test that other scripts in the area use, if any.

### 7. Push (only when the user asks, or when this is part of an ongoing PR-iteration cycle)

`git push origin <branch>`. Don't push without confirmation if the user hasn't established that this is an ongoing review-iteration cycle on the current PR.

## Output format

Always emit a table with these exact columns:

```
| # | Finding | Verdict | Why |
|---|---|---|---|
```

- **#** — sequential number (`1`, `2`, …) within this pass. Do not reuse numbers across passes; if a new pass has 2 findings, they're `A` / `B` (or `1` / `2` with a header noting "new findings").
- **Finding** — short title + severity in parens. Match what Bugbot used (e.g. `HIGH`, `MED`).
- **Verdict** — one of: `**REAL**`, `**REAL (pre-existing)**`, `**FALSE POSITIVE**`. Bold the verdict.
- **Why** — one or two sentences. Cite specific file:line where useful. If false positive, say what was wrong with the analysis.

After the table, list the resolution action(s) taken (cherry-pick SHA, manual commit SHA, or "dismissed"). Then a one-line summary of post-change verification (parse + dry-run + whatever else).

### Example

```
| # | Finding | Verdict | Why |
|---|---|---|---|
| 1 | Localizer targets wrong store version (HIGH) | **REAL** | `localize.py:55-79` filters versions to live/in-review; release picks PREPARE_FOR_SUBMISSION → metadata lands on the live version. |
| 2 | REPO_ROOT one directory too high (MED) | **FALSE POSITIVE** | Bugbot self-acknowledged. `SCRIPT_DIR.parents[3]` IS the repo root (verified via filesystem). |
| 3 | Git push failure uncaught (MED) | **REAL** | After tag + localize, `git push` failure crashes the driver before attach/submit. Warn-and-continue is right. |

Cherry-picked `a198f39e` from `cursor/encameracore-release-issues-05f0`. Verified: both files parse, `--dry-run --skip-preflights` shows the same plan as before.
```

## Anti-patterns

- **Don't trust descriptions without reading the code.** Bugbot has been wrong; verify every "real" claim against the actual cited lines before committing a fix.
- **Don't push without asking** unless the user has clearly established an ongoing iteration cycle on the PR (multiple back-and-forth pushes already in this conversation).
- **Don't strip the autofix commit's body** when cherry-picking — preserve the bullet list so future readers understand what the commit fixed.
- **Don't rewrite the author** of a cherry-picked autofix. Keep `Cursor Agent <cursoragent@cursor.com>` as the author; you'll appear as the committer automatically.
- **Don't skip the table.** Even for one finding, render the table. Consistency matters because the user will compare across passes.
- **Don't squash multiple Bugbot passes into one commit.** Each pass is its own cherry-pick (or set of commits), so the PR history shows which findings were addressed when.

## Quick checklist

- [ ] Fetched `origin` and the `cursor/<...>` branch named in the latest review
- [ ] Filtered comments to those new since the last pass
- [ ] Verified each finding against the actual cited code (false positives identified)
- [ ] Cherry-picked or hand-fixed per the per-finding decision
- [ ] Preserved `Cursor Agent` authorship on cherry-picks (with the bullet body intact)
- [ ] Parsed / dry-ran the affected scripts post-change
- [ ] Reported findings as a Markdown table with the four columns above
- [ ] Confirmed with the user before pushing (unless already in an iteration cycle)
