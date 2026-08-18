---
name: emulate-pasg-agentic
description: >-
  Run a PASG v2 agentic turn in the terminal instead of the Agent Workbench — provision a real run workspace, generate the production operating-context preamble, let that preamble route to the right `.agents/skills/pasg-v2-*` skill, then execute that skill's deterministic scripts against the live SharePoint data room. Use when the user gives a PASG analyst-style request ("generate an architecture slide", "draft the agenda", "what diagrams are in this file", "build the evidence ledger") and wants it run as the Codex agent would, or says "emulate the agentic chat", "run this as the agent", or invokes /emulate-pasg-agentic. Requires a prompt.
---

# Emulate a PASG v2 Agentic Turn

Run one agent turn the way `agentic/runner.py` + Codex would, but with Claude Code as the agent runtime. The point is to exercise **skill selection and the deterministic scripts** without the queue, the worker, the SSE stream, or a Codex binary.

The rule that makes this an emulation rather than an improvisation: **skill selection in PASG v2 is injection, not description ranking.** The runner prepends a fixed operating-context preamble to every turn, and that preamble names which skills to read and under exactly which conditions. So this skill generates the real preamble text and then obeys it. Never route from your own judgement, from Claude Code's skill list, or from a `SKILL.md` description.

## Required input

A prompt — the analyst's message. If the user invoked this without one, **stop and ask for it.** Do not invent a plausible request.

You also need a project slug. Take it from the prompt when it names a project; otherwise list the available ones and ask:

```bash
ls "$PASG_REPO/.agent-data/sharepoint-mirror/"
```

## Step 1 — Provision the workspace and get the preamble

Find the PASG repo first (a worktree under `~/freelance/PASG/worktrees/*` or the main checkout at `~/freelance/PASG/rag`). Then, from the repo root:

```bash
.venv/bin/python ~/.claude/skills/emulate-pasg-agentic/scripts/prepare_turn.py \
  --prompt "<the analyst message, verbatim>" \
  --project <project-slug> \
  --run-id <run-id>
```

Add `--sync-source` when the turn will cite evidence. Without it the snapshot carries synthetic `local:<path>` drive item ids instead of real Graph ids, so ledger entries are not citable on a real run's terms. It costs a full Graph listing of the project folder, so skip it for a pure discovery or inspection turn.

The script provisions (or reuses) `<repo>/.agent-data/runs/<project>/<run-id>/`, seeds `source/source_snapshot.json` if missing, and prints two things: the workspace facts, and the production preamble from `agentic.runner._agentic_turn_instructions`. **Read the whole preamble.** It is long (~12 kB) and it is the contract for the rest of the turn.

Reuse the same `--run-id` for follow-up turns in the same conversation — that is what makes a multi-turn exchange (discovery → pick → classify → slide) behave like one run. Provisioning is idempotent and takes seconds.

## Step 2 — Enter the workspace

Every command from here runs with the workspace as cwd, using the workspace's own `.venv/bin/python` and workspace-relative script paths, exactly as the preamble says:

```bash
cd <workspace>
set -a; . <repo>/.env; set +a
.venv/bin/python .agents/skills/<skill>/scripts/<tool>.py …
```

The `set -a; . .env; set +a` prefix is required on **every** shell call, because Claude Code's working directory and environment do not reliably persist between tool calls, and because the skill scripts never call `load_dotenv` themselves. Without it, `services.rag` reads a missing `GPT5_API_KEY` and `get_project_rag_system` returns `None` silently — no error, just an unexplained empty result.

## Step 3 — Read the startup manifests

The preamble's first instruction is to read these three, in the workspace:

- `PASG_AGENTIC_SKILL_DIGEST.md` — per-skill "Use when" lines plus the canonical command for each
- `PASG_AGENTIC_TOOL_INDEX.md` — the authoritative helper/module map
- `PASG_AGENTIC_TOOLING.md` — workspace rules and the skill list

Read them from the workspace copy, not the repo. They are generated per workspace and are what the real agent sees.

## Step 4 — Select the skill from the preamble

This is the part being tested, so make the decision explicit and auditable.

1. Scan the preamble for the conditional routing lines. They read like *"Only when an analyst asks you to check a document's images for diagrams … use `.agents/skills/pasg-v2-diagram-extraction`"* and *"For factual diligence Q&A, run … `source_answer.py` before answering"*. Cross-check against the digest's "Use when" line for the same skill.
2. **Quote the line that triggered your choice** in your reply, before running anything. One or two skills, not a survey.
3. **When no preamble line matches, say so** and do the work with the general tooling the preamble names (`inspect_source_file.py`, `rg`, `find`). Do not force a skill just because one exists.
4. **When two lines match, follow the preamble's own ordering** (`pasg-v2-core` and `pasg-writing-style` first; hydrate → source map → agenda/DRL → evidence ledger → deck → promotion). If the ordering does not resolve it, ask the analyst rather than guessing.
5. Read the chosen skill from **`.agents/skills/<name>/SKILL.md` inside the workspace**. Do not use Claude Code's `Skill` tool for the `pasg-v2-*` skills: it loads the worktree copy through `.claude/skills`, which can differ from the workspace copy the agent would actually read, and it bypasses the injection model this skill exists to reproduce.

Then follow that skill's protocol exactly — including its entry-point rules (for example, diagram extraction must not run discovery on a file the analyst already supplied) and any sentence it says to reproduce verbatim.

## Fidelity rules

Break these and the run stops being evidence about the real system.

- **Do not look at client images the agent would not look at.** Discovery previews under `outputs/diagrams/previews/` exist for the *analyst* to rank; the real agent never sees them and pays zero vision calls for that pass. Present them to the user as paths and let them choose. Rendered output you produced yourself — `visual/*.png` from `render_visual_review.py` — is different: the agent does review its own decks, so reading those is in-policy.
- **Do not substitute your own reasoning for a script.** If a skill says to resolve a pick with `--image <n>`, run it; do not map the number yourself.
- **Do not edit `repo/`, `templates/`, `prompts/`, `config/`, or `skills/`** in the workspace. They are read-only reference copies.
- **Do not set `PASG_AGENT_REPO_ROOT`** during an emulation turn. The workspace `repo/` copy is the code path a real run uses. Only override it when you are deliberately iterating on `agentic/*` source and want edits to take effect without re-provisioning — and say so when you do, because it changes what the run proves.
- **Report artifacts by workspace-relative path** (`outputs/deck_strategy.json`), never absolute container-style paths.

## Known environment gaps

State these when they bite; do not silently work around them.

- **RAG is usually empty locally.** Most projects have no rows in `documents`/`document_embeddings` in the dev Postgres, so `build_hybrid_evidence_candidates.py` reports `rag status: unavailable` and returns 0 candidates. That is a data gap, not a bug. Fall back to direct inspection (`inspect_source_file.py --full`), which the evidence-ledger skill names as the primary path anyway.
- **Slide authoring needs the DB.** `author_slide_json_batch.py` calls `get_project_rag_system`, which needs Postgres reachable and the project row present. `make dev-up` provides it. The LLM half works even when the index is empty, because authoring reads the context bundle.
- **Vision needs the right deployment name.** `OPENAI_VISION_MODEL` must be a name the endpoint accepts (`gpt-5.6-sol`). A mismatched name fails as a raw traceback ending in `400 Unsupported parameter: 'temperature'`.
- **`check_writing_guardrails.py` lints the `mermaid` field as prose.** `list_bloat` / `obtuse_language` findings on a `mermaid` path are checker artifacts. Keep them, note them, do not rewrite a client's topology to satisfy a linter.
- **Old workspaces are traps.** Any run directory provisioned inside the dev container has a `.venv/bin/python` wrapper pointing at `/opt/venv`, which does not exist on the host, and a `repo/` copy frozen at whatever the code was then. Always provision fresh through `prepare_turn.py`.

## What this does not emulate

Say so plainly when reporting, so nobody reads a green terminal run as a green production run:

- **The model.** The real runtime is `gpt-5.6-sol` under Codex. Conclusions about how well the preamble or a `SKILL.md` is worded do not transfer. The gate for that is `scripts/run_diagram_skill_selection_eval.py --live` and its siblings.
- **The sandbox.** No `workspace-write`, no bubblewrap, no approval protocol. A script writing outside the workspace goes unnoticed here.
- **The orchestration.** No events, no SSE, no `collect_agent_outputs`, no `agent_run_artifacts` or evidence rows, no promotion, no steering, no fork. Artifacts just sit in the workspace.
- **The analyst-facing gallery.** Markdown image references render as tiles in the workbench and as literal text in a terminal.

## Reporting back

Close the turn the way the agent would, plus the emulation notes:

1. The routing decision and the preamble line that produced it.
2. What ran, in order, with the one-line stdout summary each script printed.
3. The artifacts, by workspace-relative path.
4. Findings in plain language — how many images, which diagrams, which QC/guardrail findings survived review.
5. The offered next step, never taken silently (a skill that says "offer to build the slide" means offer, then stop).
6. Anything from **Known environment gaps** that affected the result.
