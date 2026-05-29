---
name: verify-doc
description: >-
  Step through a markdown doc section-by-section and verify each ## section against the real codebase, editing the doc in place to match reality. Use when the user asks to "verify", "fact-check", "audit", or "make sure X.md is up to date / matches the code".
---

# Verify Doc

Walk a markdown file ## section by ## section, fact-check each section against the actual codebase, edit the doc to fix anything stale, and end with a summary report of what changed.

## Input

The user points you at a markdown file (e.g. `/verify-doc docs/architecture.md` or "verify docs/foo.md"). Treat the argument as the path to verify. If no path is given, ask once.

Before doing anything else, check the repo for a `CLAUDE.md` or `AGENTS.md` at the repo root and read them — many repos encode rules (venv usage, lint policy, never-edit lists) that constrain how you should run commands and what you can change. Honor them.

## Workflow

### 1. Build the todo list

Read the target file. Extract every `^## ` heading in order. Create one task per section with TaskCreate, with subjects like `Verify <section name>`. Do not collapse multiple sections into one task — the user wants to see them tick off one by one.

If the file has zero `## ` headings, fall back to `# ` headings; if it still has none, treat the whole file as a single task.

### 2. Verify each section, one at a time

For each task in order:

1. TaskUpdate to `in_progress`.
2. Read the section's content from the markdown file (only that section — not the whole file every time).
3. For every concrete claim in the section, verify it against the real code:
   - **Paths / files / directories** — confirm they exist (`ls`, `Read`).
   - **Symbols** (functions, classes, env vars, route paths, table names, columns) — grep for them.
   - **Diagrams** (Mermaid flowcharts / sequence diagrams / ERDs) — every node label that names code (a module, function, route, table, column, env var) is a claim. Verify each.
   - **Cross-doc links** — confirm the target file exists.
   - **Behavior notes / "X defaults to Y"** — find the code that sets the default and confirm.
4. If something is stale, edit the doc in place (prefer `Edit` over `Write`) so it reflects current reality. Preserve voice, tone, and surrounding structure. Don't rewrite sections that are already correct.
5. Keep a running note (in your own working memory, not a file) of what you changed in this section and why. You'll need it for the final summary.
6. TaskUpdate to `completed`. Move to the next task.

Run independent reads/greps in parallel within a section to keep things fast, but **do not** batch verification across sections — finish one section's edits before starting the next, so the todo list reflects real progress.

### 3. Heuristics for what counts as "stale"

Fix:
- Wrong file/function/class/route/env-var/table/column names.
- Diagrams whose edges or nodes no longer match the wiring (e.g. routers not registered, services renamed, deleted modals still listed).
- Behavior notes that contradict the code (defaults, fallbacks, error paths).
- Dead links to docs that no longer exist.
- Library swaps (e.g. PyMuPDF → pypdf) the doc didn't catch up to.
- Missing major entities (tables, routes, components) that have been added since the doc was last touched.

Leave alone:
- Stylistic choices, ordering, or phrasing that's correct but not how you'd have written it.
- Aspirational / forward-looking sections clearly labeled as such (e.g. a "Production" subgraph that documents intended deploy even if the repo doesn't fully implement it). Note these in the summary instead of deleting.
- Anything the repo's `CLAUDE.md`/`AGENTS.md` says not to touch.

When in doubt about whether something is stale vs. aspirational, leave it and flag it in the summary.

### 4. Final report

After every task is completed, output a single message to the user — no tool calls — structured like this:

```
Verified <path> — <N> sections checked.

Updates per section:
- <Section name>: <one-line summary of what changed, or "no changes">
- ...

Flagged (not edited, needs human call):
- <thing>: <why it's ambiguous>
- ...
```

Keep each bullet to a single line. If a section had multiple changes, summarize them compactly (e.g. "fixed 3 stale route paths; added missing `agenda_jobs` table to ERD"). If nothing in the doc needed changes, say so explicitly for that section rather than omitting it — the user wants to see that you actually checked.

## Constraints

- **Don't rewrite the whole doc.** Edit only what's wrong. Preserve unrelated content verbatim.
- **Don't add net-new sections** unless the user asks. If you find a major undocumented subsystem, mention it in the flagged section of the report instead.
- **Don't run destructive shell commands** during verification — read-only operations only (`ls`, `grep`, `Read`, `cat`-less file inspection).
- **Don't commit, push, or open a PR** unless the user explicitly asks. This skill only edits files locally.
- **Don't skip sections** even if they "look fine" — the value of this skill is exhaustive verification, so at least skim and grep for the concrete claims in every section.
- **Trust but verify memory.** If you have prior memory about this repo's structure, still re-check it against the live code — repos drift.
