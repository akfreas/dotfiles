---
name: create-pr
description: >-
  Create a GitHub PR from the current branch. The user supplies the base
  branch, title, and a short lead-in description; the skill validates the
  description against the actual diff, drafts the body from commit messages
  in a strict concise format, gets the user's approval, then opens the PR
  via `gh`.
---

# Create PR

Use this skill when the user asks to open a pull request. The user MUST supply three things — do not invent them:

1. **Base branch** (e.g. `main`, `develop`).
2. **PR title** — the user writes this themselves so they think about what the changeset actually is. Do not propose one.
3. **Short description** — one or two sentences that lead the PR body.

If any of the three are missing from the user's request, ask for them with `AskUserQuestion` (or plain prose if richer back-and-forth is needed). Do not guess.

## Base-branch convention

When the user says a branch name like `main` or `develop`, they mean `origin/main` / `origin/develop` — the remote tip, not the local branch. Every `git` command in this skill that takes a base reference MUST use `origin/<name>`. Resolve the user's input that way without asking, but tell them once in your first status update so they can correct you if they meant something else (e.g. an upstream other than `origin`, or a local branch deliberately).

Before using the remote ref, run `git fetch origin <base>` so `origin/<base>` is up to date. Do not pull. Do not merge. Do not rebase. The fetch is read-only.

## Procedure

### 1. Collect inputs

If the user did not give all three required inputs, ask for the missing ones. Never auto-fill the title — bounce it back to the user.

### 2. Refresh the base ref, then check for divergence

Run:

- `git fetch origin <base>` — update `origin/<base>` locally. Read-only.
- `git rev-list --left-right --count origin/<base>...HEAD` — output is `<behind>\t<ahead>`: commits on `origin/<base>` not on HEAD, then commits on HEAD not on `origin/<base>`.

Interpret:

- `ahead == 0` → branch has no new commits. Stop and tell the user.
- `behind > 0` → `origin/<base>` has commits the branch doesn't. **STOP.** Do not open the PR. Report the count and the list (`git log --oneline HEAD..origin/<base>`) so the user can rebase or merge themselves. Do not pull, merge, or rebase on their behalf. Do not offer to.
- `behind == 0 && ahead > 0` → proceed.

### 3. Gather commit context

Run in parallel:

- `git rev-parse --abbrev-ref HEAD` — current branch.
- `git log origin/<base>..HEAD --pretty=format:'%h %s%n%n%b' --no-merges` — commits this PR will include, with bodies.
- `git diff origin/<base>...HEAD --stat` — high-level shape of the diff. Use this as one input when validating the user's description (step 4).

### 4. Validate the user's short description against the actual diff

Read the commits and the diff stat. Judge whether the user's lead description is an honest summary of what's actually changing. If it isn't, reject it — do not silently use it.

Rejection reasons (non-exhaustive — name the specific one):

- **Not descriptive enough** — the diff covers materially more than the description claims (e.g. description says "fix typo" but the diff also adds a new endpoint).
- **Unrelated changes in PR** — commits include work that doesn't belong with the stated description (orphan refactor, drive-by edits to a different module). Tell the user which commits look unrelated so they can decide whether to drop them or rewrite the description.
- **Wrong direction** — description describes the opposite of what the diff does, or names the wrong subsystem.
- **Vague to the point of useless** — "various improvements", "misc fixes", "cleanup" with no anchor.

When rejecting, state the reason in one sentence, cite the evidence (commit subjects, file counts, or named symbols from the diff), and ask the user to either (a) rewrite the description or (b) reduce the PR scope so the description fits. Do not draft a replacement description for them — they wrote the title and lead for a reason.

If the description is fine, say so in one short line and move on.

### 5. Draft the body

The body MUST follow this exact shape:

```
<short description provided by user>

<optional bug/limitation block — only if this PR fixes a bug or removes a limitation>
- <problem 1>
- <problem N>

Changes
- <change 1>
- <change 2>
- <change N>
```

The bug/limitation block is omitted entirely for pure feature PRs. When present, it sits between the lead description and `Changes`, separated by blank lines. There is no header word for it — just the bullets.

`Changes` is the literal word `Changes` on its own line, followed by bullets. No colon.

#### Hard rules for the body

**Do not:**
- Use bold, italic, headers, or any formatting other than backticks for code/identifiers.
- Reference file paths. Refer to classes, functions, or other named code symbols instead.
- Write verbose statements about what changed. Mirror the terseness of the commit messages.
- Use corporate-dev-speak. Banned words/phrases (non-exhaustive): `lands`, `landed` (for merged/shipped), `leverage`, `surface` (as a verb), `flag` (as a verb), `loop in`, `align on`, `sync up`, `circle back`, `drive`, `unblock`, `action` (as a verb), `operationalize`.
- Add a "Test plan" section, a "Summary" header, a "Generated with Claude Code" footer, or any trailers.
- Add emojis.

**Do:**
- Be concise. Match the prose register of the commits.
- Focus on the real problem the changeset solves. If the user wants the technical detail, they can read the commits.
- Use backticks around class names, function names, and other identifiers.
- Group related commits into single bullets when they describe one logical change. Do not just list every commit verbatim.

#### Gold-standard examples

Bug fix:

```
The checklist analysis was getting cut off because of a limitation on the query page size, which meant that it looked like some rows were simply not there.

- `getDealChecklistAnalysisForDeals` fetched analysis records for 50 deals at once without pagination
- Supabase PostgREST defaults to max 1000 rows per query; with ~40 records/deal, batches of 50 deals return ~2000 rows but only the first 1000 were returned
- Deals beyond the 1000-row cutoff had their analysis silently dropped, making them appear unanalyzed in the checklist grid

Changes
- Added pagination within each batch query using `.range()` with `DEFAULT_PAGE_SIZE=1000`, fetching all pages until results are exhausted
```

Feature:

```
Add the ability to pinch-to-zoom using gestures on the camera, much like the system camera.

- Added gesture recognizer to `CameraView` that hooks into camera controls model
- As camera is zooming, the `CameraZoomControlIndicator` for the zoom level also update
```

### 6. Get explicit approval

Show the user the full drafted body in a fenced block, then ask for approval with `AskUserQuestion`. Options, in this exact order (the first is the default when the user presses enter):

1. **Open as draft** — default. Opens the PR with `--draft`.
2. **Open as ready** — opens the PR without `--draft`.
3. **Edit** — revise the body.
4. **Cancel** — abort.

Do not call `gh pr create` before the user picks one of the open options. If they pick edit, revise and re-show. Loop until they approve or cancel.

### 7. Create the PR

Once approved, push the branch if it has no upstream (`git push -u origin <branch>`), then:

```
gh pr create [--draft] --base <base> --title "<user-supplied title>" --body "$(cat <<'EOF'
<approved body>
EOF
)"
```

Include `--draft` if the user picked "Open as draft" (the default), omit it if they picked "Open as ready".

Note: `gh pr create --base` takes the bare branch name (e.g. `main`), not `origin/main`. The `origin/` prefix is for local `git` commands only.

Use a HEREDOC for the body — never inline it as a single `--body` string, since the body contains newlines and backticks.

Return the PR URL `gh` prints.

## Notes

- The user's three inputs are sacred: do not paraphrase the title or the lead description without asking. If the lead description fails validation in step 4, reject it — do not rewrite it.
- Never push to `main`/`master`. If the current branch is the base branch, stop and tell the user.
- Do not skip hooks, do not force-push.
- Do not pull, merge, or rebase to resolve divergence in step 2 — that's the user's call.
- If `gh pr create` fails (auth, no remote, etc.), report the error verbatim — do not invent fallback flows.
