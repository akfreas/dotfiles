---
name: create-pr
description: >-
  Create a GitHub PR from the current branch. The skill picks the base branch
  via a prompt (default `origin/main`, with manual entry), generates a PR title
  and short lead-in description from the commits and diff, lets the user accept
  them or supply their own, drafts the body in a strict concise format, gets the
  user's approval, then opens the PR via `gh`.
---

# Create PR

Use this skill when the user asks to open a pull request. The skill is interactive: it proposes a base branch, a title, and a short description, and lets the user accept each or override it. Three things drive the PR — do not silently invent the final values, prompt for them:

1. **Base branch** — proposed as `origin/main` by default, with manual entry.
2. **PR title** — generated from the commits and diff, with the option to enter one.
3. **Short description** — one or two sentences that lead the PR body, generated, with the option to enter one.

## Base-branch convention

When a branch name like `main` or `develop` is in play, it means `origin/main` / `origin/develop` — the remote tip, not the local branch. Every `git` command in this skill that takes a base reference MUST use `origin/<name>`. If the user types a bare name when entering one manually, resolve it to `origin/<name>` and say so once in your first status update so they can correct you if they meant an upstream other than `origin` or a local branch deliberately.

Before using the remote ref, run `git fetch origin <base>` so `origin/<base>` is up to date. Do not pull. Do not merge. Do not rebase. The fetch is read-only.

## Procedure

### 1. Choose the base branch

Ask with `AskUserQuestion`. Header `Base branch`. Options, in this order:

1. **`origin/main` (Recommended)** — the usual base.
2. **`origin/develop`** — include only if the repo actually has a `develop` branch (check `git branch -r`); otherwise omit it.

The user can always pick "Other" to type a base branch manually. Resolve whatever they enter per the base-branch convention above (`origin/<name>`).

If the user already named a base branch explicitly in their request, skip this prompt and use it.

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
- `git diff origin/<base>...HEAD --stat` — high-level shape of the diff.

### 4. Generate a title and short description

From the commits and the diff stat, write:

- A **title** — a single concise line naming what the changeset actually is. Imperative mood, no trailing period, no PR number, no type prefix unless the repo's existing titles use one.
- A **short description** — one or two sentences that honestly summarize what's changing, suitable as the lead of the PR body.

Make these reflect the *whole* diff, not just the first commit. If the commits include unrelated work (orphan refactor, drive-by edits to a different module), do not paper over it — note it to the user so they can decide whether to drop those commits or widen the description. If the diff is genuinely grab-bag and no honest one-line summary exists, say so rather than inventing a tidy story.

### 5. Offer the title and description, let the user override

Show the generated title and short description, then ask with `AskUserQuestion`. Header `Title & desc`. Options, in this order:

1. **Use generated (Recommended)** — accept both as shown.
2. **Edit description only** — keep the title, supply a new description.
3. **Edit title only** — keep the description, supply a new title.

The user can pick "Other" to provide both their own title and description. If they choose any edit/override path, collect the new text conversationally (or via the "Other" free-text box), then re-show the final title and description in one short confirmation line before drafting the body.

Treat whatever the user supplies as authoritative — do not paraphrase a user-supplied title or description.

### 6. Draft the body

The body MUST follow this exact shape:

```
<short description>

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

### 7. Get explicit approval

Show the user the full drafted body in a fenced block, then ask for approval with `AskUserQuestion`. Options, in this exact order (the first is the default when the user presses enter):

1. **Open as draft** — default. Opens the PR with `--draft`.
2. **Open as ready** — opens the PR without `--draft`.
3. **Edit** — revise the body.
4. **Cancel** — abort.

Do not call `gh pr create` before the user picks one of the open options. If they pick edit, revise and re-show. Loop until they approve or cancel.

### 8. Create the PR

Once approved, push the branch if it has no upstream (`git push -u origin <branch>`), then:

```
gh pr create [--draft] --base <base> --title "<final title>" --body "$(cat <<'EOF'
<approved body>
EOF
)"
```

Include `--draft` if the user picked "Open as draft" (the default), omit it if they picked "Open as ready".

Note: `gh pr create --base` takes the bare branch name (e.g. `main`), not `origin/main`. The `origin/` prefix is for local `git` commands only.

Use a HEREDOC for the body — never inline it as a single `--body` string, since the body contains newlines and backticks.

Return the PR URL `gh` prints.

## Notes

- Generated values are proposals, not final: always run the step 5 prompt and the step 7 approval before opening the PR. Whatever the user supplies overrides the generated text verbatim.
- Never push to `main`/`master`. If the current branch is the base branch, stop and tell the user.
- Do not skip hooks, do not force-push.
- Do not pull, merge, or rebase to resolve divergence in step 2 — that's the user's call.
- If `gh pr create` fails (auth, no remote, etc.), report the error verbatim — do not invent fallback flows.
