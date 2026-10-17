---
name: create-pr
description: >-
  Create a GitHub PR from the current branch. Runs fully automatically by
  default: bases on `origin/main`, generates the title, description and body
  from the commits and diff, appends a provenance block listing every Claude
  Code session, worktree and host behind the branch, and opens the PR ready
  for review without any prompts. The user can override the base branch,
  title, description, or ask for a draft in their request; only then does the
  skill deviate. Also used to regenerate an existing PR's description.
---

# Create PR

Use this skill when the user asks to open a pull request, or to rewrite an existing PR's description "using the create-pr rules".

**The skill is non-interactive by default.** Do not ask the user anything — not about the base branch, not about the title or description, not for approval of the body. Generate everything, open the PR, report the URL. The point is to open PRs in one shot without repeating the same answers every time.

## Defaults

Unless the user's request says otherwise, use these without asking:

| Thing | Default |
| --- | --- |
| Base branch | `origin/main` |
| Title | generated from the commits and diff |
| Short description | generated from the commits and diff |
| Body | drafted per the format below, ending with the provenance block |
| Draft vs ready | **ready for review** (no `--draft`) |

## Honoring overrides

The user can override any default by saying so in their request — "base it on develop", "open it as a draft", "title it X", "use this description: …". Take whatever they supply verbatim; do not paraphrase a user-supplied title or description. An override for one thing does not turn the rest of the run interactive: everything they did not mention still uses its default.

Only ask a question if the request is genuinely ambiguous in a way that changes the PR (for example they name a base branch that does not exist). Never ask merely to confirm a default.

## Base-branch convention

When a branch name like `main` or `develop` is in play, it means `origin/main` / `origin/develop` — the remote tip, not the local branch. Every `git` command in this skill that takes a base reference MUST use `origin/<name>`. If the user types a bare name, resolve it to `origin/<name>` and say so once in your status output so they can correct you if they meant an upstream other than `origin` or a local branch deliberately.

Before using the remote ref, run `git fetch origin <base>` so `origin/<base>` is up to date. Do not pull. Do not merge. Do not rebase. The fetch is read-only.

## Procedure

### 1. Resolve the base branch

`origin/main`, unless the user named one. No prompt.

### 2. Refresh the base ref, then check for divergence

Run:

- `git fetch origin <base>` — update `origin/<base>` locally. Read-only.
- `git rev-list --left-right --count origin/<base>...HEAD` — output is `<behind>\t<ahead>`: commits on `origin/<base>` not on HEAD, then commits on HEAD not on `origin/<base>`.

Interpret:

- `ahead == 0` → branch has no new commits. Stop and tell the user.
- `behind > 0` → `origin/<base>` has commits the branch doesn't. **STOP.** Do not open the PR. Report the count and the list (`git log --oneline HEAD..origin/<base>`) so the user can rebase or merge themselves. Do not pull, merge, or rebase on their behalf. Do not offer to.
- `behind == 0 && ahead > 0` → proceed.

These are hard blockers, not preference questions — stopping here is correct even in auto mode.

### 3. Gather commit context

Run in parallel:

- `git rev-parse --abbrev-ref HEAD` — current branch.
- `git log origin/<base>..HEAD --pretty=format:'%h %s%n%n%b' --no-merges` — commits this PR will include, with bodies.
- `git diff origin/<base>...HEAD --stat` — high-level shape of the diff.

### 4. Generate a title and short description

From the commits and the diff stat, write:

- A **title** — a single concise line naming what the changeset actually is. Imperative mood, no trailing period, no PR number, no type prefix unless the repo's existing titles use one.
- A **short description** — one or two sentences that honestly summarize what's changing, suitable as the lead of the PR body.

Make these reflect the *whole* diff, not just the first commit. If the commits include unrelated work (orphan refactor, drive-by edits to a different module), do not paper over it — cover it in the description and mention it in your final report so the user can decide whether to drop those commits. If the diff is genuinely grab-bag and no honest one-line summary exists, say so plainly in the description rather than inventing a tidy story.

### 5. Generate the provenance block

Every PR body ends with a block that records where the code was worked on: the Claude Code sessions that touched or discussed the branch, the worktrees the branch was checked out in, and the host the sessions ran on. The point is to be able to come back months later, find the transcripts, reread the thought process, and relaunch a session with `claude --resume`. Past searches for "that session where we talked about X" went wrong in exactly the ways this block prevents: the session lived in a worktree's project directory rather than the main checkout's, the worktree had since been removed, or the wrong session was picked because only one project directory was searched.

The block is produced by the helper script shipped with this skill, `scripts/branch_sessions.py`, next to this file (the skill's base directory is printed when the skill loads). Run it from the repo:

```
python3 -I <skill base dir>/scripts/branch_sessions.py --repo "$(git rev-parse --show-toplevel)" --branch <branch> --base origin/<base>
```

What it does, so you can explain it or debug it:

- Works out when the branch was minted: the earliest of the branch's reflog creation entry (`branch: Created from …`) and the oldest author or committer date among `origin/<base>..<branch>`. The reflog matters because rebases rewrite commit dates; the commit dates matter when the branch was created on another machine and the reflog here only shows a fetch.
- Searches every transcript under `~/.claude/projects/` — all project directories, not just the current checkout's, because worktree sessions live under their own directory — for the branch name with `rg`, and keeps only transcripts modified on or after the minted time.
- For each matching session it collects the session ID, the time range, the AI or custom title (falling back to the first prompt or slash command), the working directories, whether the branch was actually checked out there or merely mentioned, whether it was driven through Remote Control (a `bridge-session` entry), whether it ran from the desktop app or the SDK, how many subagent transcripts it has, and whether its transcript sits under a different project directory than its working directory suggests.
- Groups sessions by worktree. The worktrees are the git toplevels of every directory a session had the branch checked out in, including worktrees that no longer exist (marked "worktree removed"), plus any live worktree that has the branch checked out now.
- Prints the hostname, because transcripts only exist on the machine the session ran on. If a session was run on another computer (for example through `run-remote-agent`), it will not appear here, and the hostname tells future-you which machine's transcripts you are looking at.

Rules for the block:

- Paste the script's output verbatim as the final section of the body, after a blank line following the last `Changes` bullet. Do not prune sessions you think are unrelated, do not reorder, do not reformat, do not summarize. A session that "only" mentions the branch is still a lead.
- If it prints `No transcripts on this host mention the branch`, keep that line in the PR. It tells the reader to look on another machine.
- If the user says the work started earlier than the branch (it was renamed, or restarted from a scratch branch), pass `--since <ISO 8601>` with the earlier time. If they name the old branch, run the script a second time with `--branch <old name>` and append both blocks.
- If the script errors, report the error verbatim in your final message, open the PR without the block, and say that the block is missing. Do not hand-write a replacement.
- `--format json` prints the same data as JSON if you need to inspect it; never paste the JSON into the PR.

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

<provenance block, verbatim from scripts/branch_sessions.py>
```

The bug/limitation block is omitted entirely for pure feature PRs. When present, it sits between the lead description and `Changes`, separated by blank lines. There is no header word for it — just the bullets.

`Changes` is the literal word `Changes` on its own line, followed by bullets. No colon.

The provenance block is a `<details>` element the script emits, so it renders collapsed on GitHub and keeps the description readable. It is the one part of the body that is allowed to contain file paths, hostnames and session IDs.

#### Hard rules for the body

**Do not:**
- Use bold, italic, headers, or any formatting other than backticks for code/identifiers.
- Reference file paths. Refer to classes, functions, or other named code symbols instead. (The provenance block is exempt: it exists to hold paths.)
- Write verbose statements about what changed. Mirror the terseness of the commit messages.
- Use corporate-dev-speak. Banned words/phrases (non-exhaustive): `lands`, `landed` (for merged/shipped), `leverage`, `surface` (as a verb), `flag` (as a verb), `loop in`, `align on`, `sync up`, `circle back`, `drive`, `unblock`, `action` (as a verb), `operationalize`.
- Add a "Test plan" section, a "Summary" header, a "Generated with Claude Code" footer, or any trailers.
- Add emojis.
- Edit the provenance block by hand.

**Do:**
- Be concise. Match the prose register of the commits.
- Focus on the real problem the changeset solves. If the user wants the technical detail, they can read the commits.
- Use backticks around class names, function names, and other identifiers.
- Group related commits into single bullets when they describe one logical change. Do not just list every commit verbatim.

#### Gold-standard examples

Bug fix (provenance block elided):

```
The checklist analysis was getting cut off because of a limitation on the query page size, which meant that it looked like some rows were simply not there.

- `getDealChecklistAnalysisForDeals` fetched analysis records for 50 deals at once without pagination
- Supabase PostgREST defaults to max 1000 rows per query; with ~40 records/deal, batches of 50 deals return ~2000 rows but only the first 1000 were returned
- Deals beyond the 1000-row cutoff had their analysis silently dropped, making them appear unanalyzed in the checklist grid

Changes
- Added pagination within each batch query using `.range()` with `DEFAULT_PAGE_SIZE=1000`, fetching all pages until results are exhausted
```

Feature, with the provenance block as the script prints it:

```
Add the ability to pinch-to-zoom using gestures on the camera, much like the system camera.

- Added gesture recognizer to `CameraView` that hooks into camera controls model
- As camera is zooming, the `CameraZoomControlIndicator` for the zoom level also update

<details>
<summary>Claude Code sessions</summary>

Host `Alex-F-MacBook-Pro.local`. Branch created 2026-10-12 21:23 (reflog: branch: Created from HEAD); transcripts searched from then until 2026-10-17 21:45. Resume a session with `cd <worktree> && claude --resume <id>`; its transcript is `~/.claude/projects/<worktree path with / and . replaced by ->/<id>.jsonl` on the host unless noted.

`/Users/akfreas/github/EncameraApp/Encamera`
- `b344b4f5-97f9-4298-891f-c4bdecdee457` 2026-10-13 06:36 to 13:57 Pinch-to-zoom gesture on CameraView
- `554ca5f0-ab7d-4f1a-b461-f5d599aec4b8` 2026-10-16 13:21 to 15:08 (remote control; 1 subagent) Zoom indicator follows gesture

`/Users/akfreas/github/EncameraApp/Encamera-key-picker` (worktree removed)
- `357b0f18-926d-4ef3-b728-7f6e350705f7` 2026-10-15 15:55 to 18:03 (also worked in `/Users/akfreas/github/EncameraApp/Encamera`) CameraZoomControlIndicator date label

Mention the branch without having it checked out
- `c21e41df-d454-4c39-819e-d86174e79280` 2026-10-12 18:20 to 22:02 Camera controls model review, in `/Users/akfreas/github/EncameraApp/Encamera-enc484`

</details>
```

### 7. Create the PR

Push the branch if it has no upstream (`git push -u origin <branch>`), then:

```
gh pr create --base <base> --title "<final title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

Open it ready for review — omit `--draft` unless the user asked for a draft, in which case add it.

Note: `gh pr create --base` takes the bare branch name (e.g. `main`), not `origin/main`. The `origin/` prefix is for local `git` commands only.

Use a HEREDOC for the body — never inline it as a single `--body` string, since the body contains newlines, backticks and the `<details>` element.

When the user asks to update an existing PR's description instead of opening one, build the body the same way (steps 3 to 6, provenance block regenerated, never copied from the old description) and apply it with `gh pr edit <number> --body "$(cat <<'EOF' … EOF)"`.

### 8. Report

Return the PR URL `gh` prints, plus the base branch and the title you used, so the user can see what was opened and fix it if a generated value missed. Add one line on the provenance block: how many sessions and worktrees it lists, and whether any session was driven through Remote Control or any worktree has since been removed. Editing an already-open PR is cheap; blocking on a prompt every time is not.

## Notes

- Never push to `main`/`master`. If the current branch is the base branch, stop and tell the user.
- Do not skip hooks, do not force-push.
- Do not pull, merge, or rebase to resolve divergence in step 2 — that's the user's call.
- If `gh pr create` fails (auth, no remote, etc.), report the error verbatim — do not invent fallback flows.
- The provenance script reads transcripts only; it never modifies `~/.claude`, and it needs `rg` (falls back to `grep`) and Python 3.9 or newer.
