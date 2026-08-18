---
name: update-pasg-timesheet
description: >-
  Reconstruct a day's PASG billable hours from Claude Code session transcripts and write
  the time entries into Toggl via its API from the authenticated freas.me Chrome browser.
  PASG work only. A target day ("today", "yesterday", "on Wednesday", "2026-08-07") is
  REQUIRED — refuse to run without one. Use when the user invokes /update-pasg-timesheet
  or asks to reconstruct/fill in their PASG timesheet or Toggl entries for a day.
---

# Update PASG timesheet

Reconstruct which hours were spent actively working on PASG in Claude Code on a given day, and create matching time entries in Toggl. Never delete or modify existing Toggl data.

## Required argument: the day

The skill takes exactly one day, e.g. "today", "yesterday", "on Wednesday", or an explicit date. **If no day was given, stop and ask for one before touching anything.** Resolve it to a single `YYYY-MM-DD` in local time and state the resolved date in the final output. Never process more than one day per invocation.

## Step 1 — Mine the Claude Code transcripts

Session transcripts live in `~/.claude/projects/<project-dir>/**/*.jsonl` (subagent transcripts sit under `<session-id>/subagents/`). Each line is JSON with a UTC `timestamp`, `type` (`user`/`assistant`/...), `gitBranch`, and for user turns a `message.content` that is either a string or a block list.

Write a throwaway Python script in the scratchpad (this is a scratch tool, not production code) that:

1. Scans every `*.jsonl` whose mtime is on or after the target day (sessions still open later can contain the day's events).
2. **Keeps only PASG project dirs** — directory name contains `PASG` (e.g. `-Users-akfreas-freelance-PASG-rag*` and its worktrees). Everything else (Encamera, Sage, personal projects) is out of scope, always.
3. Parses each line, converts the timestamp to local time with `.astimezone()`, and keeps events falling on the target date.
4. Collects per event: local time, project dir, session id (mark subagent files), event type, `gitBranch`, and for real user prompts a ~90-char preview. Treat `<task-notification>`, `<command-name>`, `[Request interrupted…]`, `isMeta`, and tool-result blocks as non-prompts (they still count as activity events).

## Step 2 — Build billable blocks

- Sort all events, merge into contiguous blocks, splitting wherever the gap between consecutive events exceeds **15 minutes**.
- **Overnight autonomous work is not billable.** Drop any block that has no real user prompts (subagents auto-resuming via task notifications), and drop blocks falling in the 01:00–05:00 window. Billable time is daytime work where the user's prompts are close together — prompting and waiting on results.
- Attribute each block to a ticket: `gitBranch` names (e.g. `pasgai-185-…`), `PASGAI-\d+` / `atlassian.net/browse/…` mentions in the prompts, and the session's kickoff prompt. A block can span multiple tickets; say so in the description.
- Compose one Toggl entry per block: start, stop, and a short description leading with the ticket id(s), e.g. `PASGAI-185 implementation + docs; PASGAI-189 image-selection subtask`.

## Step 3 — Write to Toggl (API from the browser)

Use the Chrome tools. **The right browser is the one named "freas.me browser"** — call `list_connected_browsers` first; if the current one isn't it, follow the selection flow to connect to it. Then open a tab on `https://track.toggl.com/timer`. If Toggl shows a login screen, stop and ask the user to log in — never enter credentials.

Do everything through Toggl's v9 API with `javascript_tool` from the authenticated page (session-cookie auth; no UI clicking needed):

1. `GET /api/v9/me?with_related_data=true` → workspace id and the **PASG** project id (workspace 7373814 / project 219757680 at time of writing — verify, don't assume).
2. **Overlap check before creating anything:** `GET /api/v9/me/time_entries?start_date=<day>&end_date=<day+1>` and compare existing entries against the planned blocks. Always create every planned entry regardless of overlaps — never skip one — but flag every direct overlap (existing entry id, description, span) in the output so the user can resolve the double-counting themselves.
3. Create each entry: `POST /api/v9/workspaces/{wid}/time_entries` with `{workspace_id, project_id, description, start, stop, duration (seconds), billable: true, created_with: 'claude-timesheet'}`. Send `start`/`stop` as UTC ISO strings converted from local times.
4. Verify: re-fetch the day's entries and confirm the new ids exist.

**NEVER delete, overwrite, or edit existing Toggl entries** — not even ones this skill created on a previous run. If cleanup is needed, list the entry ids and spans and let the user do it.

## Step 4 — Report

The final message must contain:

1. The resolved date and a table of the exact entries created: local start–stop, duration, description, and Toggl entry id. State the total hours added.
2. Any overlaps with pre-existing entries (id, description, span).
3. The excluded blocks (overnight/autonomous) with their spans, so the user can see what was left out.
4. The raw data: every real user prompt with local timestamp, ticket/branch tag, and truncated (~90 chars) prompt text, in chronological order.
