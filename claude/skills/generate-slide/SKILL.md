---
name: generate-slide
description: Generate a PASG slide deck for the slide currently being worked on in the rag repo, using the slide-workbench headless runner. Infers the slide ID from git changes in ../rag and runs run_slide.py with the project slug taken from .env. Delivers via OneDrive only. Use when the user says "generate the slide", "/generate-slide", or wants to render the slide they're editing.
allowed-tools: Bash, Read
---

# generate-slide

Generates a single PASG slide deck for the slide the user is currently working on,
by driving the slide-workbench headless runner (`run_slide.py`).

The user works in the **rag repo** (`../rag` relative to the workbench), editing a
slide's prompt / schema / template files. This skill figures out *which* slide that
is from git, confirms it, and runs generation against the live rag branch. Delivery
is **OneDrive only** — there is no local-output fallback.

## Layout

All logic lives in `scripts/` next to this file — call those, don't re-implement inline:

- `scripts/check_slug.sh` — prints `PROJECT_SLUG` from the rag/workbench `.env`; exits 1 if unset.
- `scripts/detect_slide.py` — prints candidate slide ID(s) inferred from rag git changes.
- `scripts/list_slides.sh` — prints every valid slide ID.
- `scripts/generate.sh <SLIDE_ID>` — runs `run_slide.py` and uploads to OneDrive.

Paths default to `/Users/akfreas/freelance/PASG/rag-slides-workbench` (workbench, has
`run_slide.py` + `.venv`) and its `../rag` sibling. Override with `WORKBENCH_DIR` /
`RAG_REPO` env vars if the repos move. Let `$SKILL` be this skill's directory.

## Steps

### 1. Confirm the project slug is configured
The runner reads `PROJECT_SLUG` from `.env`, so we don't pass `--project_slug`.
Fail early with a clear message if it's missing:

```bash
"$SKILL/scripts/check_slug.sh"
```

Exit 1 (no output) → tell the user to set `PROJECT_SLUG=<slug>` in the rag `.env`, then stop.

### 2. Infer the slide ID from git changes in the rag repo
If the user passed a slide ID as an argument to this skill, use it and skip inference.
Otherwise:

```bash
"$WORKBENCH_DIR/.venv/bin/python" "$SKILL/scripts/detect_slide.py"
```

- **Exactly one line** → that's the slide ID; carry it to step 3.
- **Multiple lines** → list them and ask the user which one (AskUserQuestion).
- **No output** → nothing maps cleanly. Ask the user for the slide ID; you can show the
  valid options with `"$SKILL/scripts/list_slides.sh"`.

### 3. Confirm before running
Generation runs against the **currently checked-out rag branch** and costs an LLM call.
Show the user the slide ID, the project slug (step 1), and the rag branch
(`git -C "$RAG_REPO" rev-parse --abbrev-ref HEAD`), and confirm before proceeding.

### 4. Run generation (OneDrive only)
```bash
"$SKILL/scripts/generate.sh" <SLIDE_ID>
```

- Progress goes to stderr; the final **OneDrive URL** is printed to stdout, and the
  result opens in the browser.
- This is OneDrive-only by design — do **not** add `--output_dir` and do **not** fall
  back to local output. OneDrive upload requires a prior interactive sign-in via the TUI
  (`.venv/bin/python run_slide.py` with no args); a headless run won't prompt.
- Exit codes: `2` = unknown slide ID or OneDrive not connected; `1` = generation/upload
  failure. On any non-zero exit (including any OneDrive error), surface the stderr message
  and treat the run as failed — no workaround.

### 5. Report
On success, report the OneDrive URL and that it opened. On any failure (including any
OneDrive error), report the error from stderr and stop — no local fallback.
