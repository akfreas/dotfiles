---
name: testflight-feedback-to-linear
description: Turn TestFlight beta-tester feedback for a release into Linear bug tickets — pull the feedback from App Store Connect, script-check which items already have tickets by their feedback ID, investigate a likely root cause in the code, and file the missing ones with the tester's own words and their screenshot attached. Use when the user invokes /testflight-feedback-to-linear, or asks to "file tickets for beta feedback", "triage TestFlight feedback for 3.0.0", or "make Linear issues from tester feedback".
---

# TestFlight feedback → Linear tickets

Beta feedback arrives as a screenshot plus a sentence of context, and it stays invisible until someone turns it into a ticket. This skill does that end to end: fetch, deduplicate deterministically, read the screenshot, guess at the cause, file it.

## Inputs

| Param | Required | Meaning |
| -- | -- | -- |
| `release` | **yes** | Marketing version as TestFlight shows it, e.g. `3.0.0`. Accepts `3.0.0 (1203)` to pin one build. |
| `parent ticket title` | no | Title (or identifier) of a Linear issue that every new ticket becomes a sub-issue of. Without it, tickets land in the **App Bugs** project with no parent. |

If no release is given, ask for one — do not guess from `project.yml`. Everything else has a default.

## Workflow

### 1. Fetch the feedback

```bash
python3 ~/.claude/skills/testflight-feedback-to-linear/scripts/tf_feedback.py fetch \
  --release <RELEASE> --out <SCRATCHPAD>/tf-<RELEASE>
```

Add `--build <N>` to pin one build, `--include-crashes` for crash feedback too, `--bundle-id` if the app isn't the one in the credentials file.

Credentials resolve from `$ASC_CREDENTIALS_PATH` (an App Store Connect credentials YAML with `app_store_connect.key_id` / `issuer_id` / `private_key_file` and `app.bundle_id`), or from `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_PRIVATE_KEY_PATH`. If the project configures an `asc` MCP server, that server's `ASC_CREDENTIALS_PATH` env value is the path to use — read it out of `~/.claude.json` and export it. The script re-execs itself into a Python that has `cryptography` (it looks at `$ASC_PYTHON`, its own `.venv`, and venvs next to the credentials file); if it can't find one it prints the two commands that create one.

Output: `feedback.json` plus `screenshots/<feedbackId>-N.jpg` in the out dir. Screenshot files are named by feedback ID, so the ID is always recoverable from a path. Note a release usually spans many builds — the script sweeps all of them.

### 2. Deduplicate with the script, not by eye

The dedupe key is the **feedback ID** (e.g. `AJLePxVxlPl7-t39XZIupJk`), which every ticket this skill writes carries on the first line of its description. Two passes, because `list_issues` truncates descriptions at ~400 characters and a marker buried deeper would be invisible:

**Pass A — bulk.** Dump the candidate issues to a file and let the script match:

```
list_issues(project: "App Bugs", fields: ["id","title","description","url"], limit: 250)
```

Save the raw JSON result to `<SCRATCHPAD>/dumps/bulk.json` (paginate with `cursor` into `bulk-2.json`, … if `hasNextPage`). If a parent ticket was named, also dump `list_issues(parentId: "<PARENT>")`. Then:

```bash
python3 ~/.claude/skills/testflight-feedback-to-linear/scripts/tf_feedback.py dedupe \
  --feedback <OUT>/feedback.json --issues <SCRATCHPAD>/dumps/*.json --out <OUT>/dedupe.json
```

**Pass B — confirm each survivor.** For every ID in the report's `searchQueries`, run `list_issues(query: "<feedback id>", fields: ["id","title","description"])`, save each result to `dumps/search-<id>.json`, and re-run `dedupe` with those files added to `--issues`. Linear's search is fuzzy and ranked, so it returns near-misses — never read the result yourself and call it a match. Let the script do the exact substring match; an empty search result is a reliable "not filed yet".

A JSON dump only ever matches against the issue objects inside it, never the raw blob — so a search dump that echoes its own query string cannot match the very ID it failed to find. Don't defeat that by pasting the ID into a plain-text dump file.

Report the split (`N already ticketed, M new`) before writing anything. If nothing is new, say so and stop — that is a successful run.

### 3. Investigate a likely root cause

Per new item, timeboxed — this is a hint for whoever picks the ticket up, not a diagnosis:

- **Read the screenshot** with the Read tool. It usually names the exact screen, and often shows the stuck state (a spinner, a zero count, a truncated control). This is the highest-value step; do not skip it.
- Map the screen to its view/view-model file, and the tester's verb ("switched from iCloud back to local", "import ring is broken") to the code path that runs it.
- Skim that path for the failure mode the screenshot shows — an `await` with no timeout, a state flag never cleared, an error swallowed into a silent branch.
- Check `git log` for recent changes to those files that shipped in the reported build; a regression's cause is usually in the diff.

Cite real `path:line` anchors and verify each one. Hedge honestly — "Most likely / Worth ruling out" — and if the code gives you nothing, write "No candidate found" rather than inventing one. A confident wrong cause costs more than none.

### 4. Write the ticket

Create with `save_issue`: `team` (from the target project), `title`, `description` (template below), `labels: ["Bug"]` if that label exists in the workspace (check `list_issue_labels`, never create one), `state` Backlog/Triage, and:

- Parent given → resolve it (`list_issues(query: "<title>")`, confirm the title matches) and set `parentId`, plus the same `project` the parent carries.
- No parent → `project: "App Bugs"`.

Title: what the user experienced, specific and imperative-free — "Switching storage from iCloud back to local freezes on the migration screen". Not "Beta feedback from Mihai".

```markdown
TestFlight feedback: `<FEEDBACK_ID>` · build <BUILD> · reported <YYYY-MM-DD> by <Tester Name> (<email>)

## What the tester said

> <the comment, verbatim — do not fix spelling, do not paraphrase>

## Environment

| | |
| -- | -- |
| Release | <version> (build <n>) |
| Device | <marketing name if certain, else the raw code> (`<deviceModel>`) |
| OS | iOS <osVersion> |
| Locale | <locale> |

## Screenshot

<embedded below>

## Possible root cause

<1–3 short paragraphs or bullets, each anchored to `path:line`. State confidence. "Most likely: …" / "Worth ruling out: …".>

## Next step

<The one thing that would confirm or kill the hypothesis — a log to check, a repro to attempt, a test to write.>
```

The first line is load-bearing: it is what step 2 matches on, and it must stay within the first ~400 characters of the description. Never reword it or move it below a heading.

### 5. Attach the screenshot

`prepare_attachment_upload` needs an existing issue, so this runs after creation. One file at a time — the signed URL expires in 60 seconds, so never prepare a second upload before the first PUT lands.

1. `prepare_attachment_upload(issue: "<ENC-123>", filename: "<id>-1.jpg", contentType: "<contentType from dedupe.json>", size: <byteSize from dedupe.json>)` — use the script's values verbatim; Apple serves JPEGs whatever the filename suggests, and a mismatched type or size is rejected.
2. PUT the bytes with every signed header exactly as returned (casing included, or it's a 403):

   ```bash
   curl -sS -X PUT --data-binary @<path> \
     -H "content-type: image/jpeg" \
     -H "x-goog-content-length-range: <size>,<size>" \
     -H "cache-control: public, max-age=31536000" \
     -H 'Content-Disposition: attachment; filename="<id>-1.jpg"' \
     "<uploadRequest.url>"
   ```

3. `create_attachment_from_upload(issue, assetUrl, title: "TestFlight screenshot")`.
4. Embed it in the description so it renders inline — `save_issue` with a patch:

   ```
   patch: [{op: "replace", old_string: "<embedded below>", new_string: "![TestFlight screenshot](<assetUrl>)"}]
   ```

If an upload fails, keep the ticket and put the local screenshot path in the description instead of leaving a broken embed — then say so in the summary.

### 6. Return the ticket text

End the turn with, for each ticket created, its identifier + URL and **the full description text as written**, in a fenced block the user can read without opening Linear. Then a one-glance summary: how many feedback items the release had, how many were already ticketed (with their identifiers), how many you filed, and anything you deliberately left out — an item too vague to ticket, a failed screenshot upload, a root cause you couldn't guess at.

## Notes

- Feedback items with no comment (screenshot only) still deserve a ticket; write the title from what the screenshot shows and say the tester left no comment.
- Two testers reporting the same bug are two feedback IDs. File one ticket, put **both** IDs on the first line (space-separated — the script matches by substring), and quote both comments.
- Never edit or close pre-existing issues. If a new item looks like a duplicate of a ticket that lacks the marker, file nothing, and report the overlap so the user can add the ID themselves.
- Screenshots and comments are real users' data — they belong in Linear, and nowhere else.
