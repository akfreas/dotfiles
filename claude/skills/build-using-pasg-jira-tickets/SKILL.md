---
name: build-using-pasg-jira-tickets
description: >-
  Implement a PASG Jira ticket end-to-end, working step by step from the ticket itself
  as the single source of truth — read it over Jira's REST API from the authenticated
  Chrome tab, build exactly its
  acceptance criteria, commit per unit of work with the ticket ID in the second -m flag,
  post a completion comment, and move the status. Use when the user invokes
  /build-using-pasg-jira-tickets, says "build PASGAI-XXX", pastes a
  paloaltostrategygroup.atlassian.net/browse/ URL, or asks to implement, work on, or
  finish a Jira ticket.
---

# Build using PASG Jira tickets

Take one Jira ticket and deliver it — implemented, committed, verified, and reflected back on the ticket.

## The ticket is the absolute authority

This is the governing rule of the skill, and everything below is downstream of it.

The ticket is not a summary of the work. It **is** the work. A manager reads that ticket to know what was asked for, an engineer reads it to know what to build, and a reviewer reads it to judge whether the finished thing matches. All three are looking at the same text and nothing else. So any gap between the ticket and the implementation is not a documentation problem — it is a correctness problem, and it surfaces as someone signing off on work that isn't what they thought they approved.

Concretely:

- **The ticket outranks every other source.** Plan docs, scratchpad files, prior design conversations, memories, your own earlier analysis, and anything the user said in a previous session are all superseded. If a plan doc in the repo contradicts the ticket, the plan doc is stale — say so and follow the ticket.
- **The ticket outranks your judgment about what would be better.** If you think an acceptance criterion is wrong, incomplete, or would be improved by doing something else, **stop and raise it** rather than quietly building the better version. A silently-improved implementation is still drift.
- **Build every acceptance criterion, and nothing beyond them.** Not a subset because something looked hard; not a superset because you were in the file anyway. Extra scope is drift in the other direction and is just as invisible to the reviewer.
- **When scope legitimately changes, the ticket changes first.** Amend the description, then implement against the amended text. Never let the code lead the ticket, even by one turn.
- **Ambiguity is resolved on the ticket, not in the chat.** If the ticket doesn't say, ask the user, then write the answer into the ticket so the next reader sees it too. An answer that lives only in a chat transcript is invisible to the manager checking the work.

If at any point you cannot honestly say "what I built is exactly what this ticket describes," stop and reconcile the two before continuing.

## Standing parameters

Inherited from `create-pasg-jira-tickets` — see that skill for the full table. The ones that matter here:

| Parameter | Value |
| --- | --- |
| Instance | `https://paloaltostrategygroup.atlassian.net` |
| Ticket URL | `https://paloaltostrategygroup.atlassian.net/browse/PASGAI-<n>` |
| Access | **Jira's REST API via `fetch()` inside the authenticated Chrome tab** — see "Talking to Jira" in `create-pasg-jira-tickets`. Read with `/rest/api/3/`, write with `/rest/api/2/` (v2 takes wiki-markup strings; v3 demands ADF). No API token, no `acli`, no Atlassian MCP. Don't click fields. |
| Statuses | `BACKLOG`, `TO DO (APPROVED)`, `IN PROGRESS`, `IN REVIEW`, `DONE`, `NOT DOING` |
| Commits | `/modular-commits`, ticket ID in the **second `-m` flag** |

Posting the completion comment and moving the status are two API calls, not a browser session. That also sidesteps the rich-text editor, which mangles typed input (`- ` auto-bullets and nests, backticks become code chips, `---` is swallowed) — see `create-pasg-jira-tickets` if you ever have to type into it directly.

## Procedure

### 1. Read the ticket — completely, from Jira

Park a tab on the Jira origin, then pull the whole ticket in **one** call — description, status, labels, parent, links, subtasks and comments together:

```js
const k = 'PASGAI-XXX';
const d = await (await fetch(`/rest/api/2/issue/${k}?fields=summary,description,status,labels,parent,issuelinks,subtasks,comment`, {credentials:'include'})).json();
({summary: d.fields.summary, status: d.fields.status.name, description: d.fields.description,
  links: (d.fields.issuelinks||[]).map(l => l.outwardIssue ? `is blocked by ${l.outwardIssue.key}` : `blocks ${l.inwardIssue.key}`),
  subtasks: (d.fields.subtasks||[]).map(s => `${s.key} ${s.fields.status.name} ${s.fields.summary}`),
  comments: (d.fields.comment.comments||[]).map(c => `${c.author.displayName}: ${c.body}`)})
```

Using `/rest/api/2/` here returns the description as readable text instead of an ADF tree you have to walk. Read all four sections — *What this delivers*, *Input / output*, *Technical shape*, *Acceptance criteria* — and **every comment**: comments frequently carry scope changes that never made it into the description, and a read that skips them builds the wrong thing.

If you delegate this to a subagent, tell it explicitly that it is read-only and must report the contents **verbatim** — a paraphrased acceptance criterion is already drift.

Check the blocked-by links. If a blocker isn't `DONE`, say so and confirm with the user before proceeding.

### 2. Restate the contract before writing code

In your own response, list the acceptance criteria as you understand them and name the files you expect to touch. This is the last cheap moment to catch a misread. If anything in the ticket is ambiguous or looks wrong, raise it **now** — before there is code to defend.

### 3. Work step by step, one unit at a time

Walk the ticket's subtasks (or its acceptance criteria when there are no subtasks) in order, treating each as a unit of work:

- Implement the unit.
- Get it green locally — tests and lint — before starting the next one.
- Commit it with `/modular-commits`, putting the ticket ID in the second `-m` flag so it stays out of the user-visible subject but remains traceable:
  ```bash
  git commit -m "Add strict PASG mermaid dialect parser with grid-position metadata" -m "PASGAI-177"
  ```

Do not batch several units into one commit, and do not run ahead to a later unit because it's convenient. The commit sequence should read as the ticket's own order.

Follow the repo's own rules while you work — `AGENTS.md` / `CLAUDE.md` in the project take precedence over generic habits for venv usage, test policy, lint, and formatting.

### 4. Verify against the acceptance criteria, one by one

Walk the acceptance-criteria list explicitly and state, for each, how it is satisfied and what you ran to prove it. A criterion you cannot demonstrate is not met — say that plainly rather than asserting completion.

Run the full non-slow suite and the linter. Report the real numbers; if something fails, report the failure rather than the intent.

### 5. Report back to the ticket

Post a completion comment covering:

- The **branch** the work is on.
- **What shipped** and where it's wired — real module and file names, in the same technical register as the ticket's *Technical shape* section.
- **Tests** added or extended, by file.
- The **suite result**, verbatim (e.g. "Full non-slow suite: 1280 passed, 0 failed. Lint clean.").

Post it and move the status in one call — `POST /rest/api/2/issue/{key}/comment` with a wiki-markup body, then `GET`/`POST` `/rest/api/3/issue/{key}/transitions` (see `create-pasg-jira-tickets` for both). Use `IN REVIEW` when it needs a human look, `DONE` when it is finished.

Then read the ticket back and confirm the comment is present and the status actually changed. Both can silently fail to take.

### 6. If scope changed along the way

Amend the ticket description surgically to match the agreed scope, post a comment explaining what changed and why, and leave the earlier comments intact as the historical record. Then make sure the code matches the amended ticket, not the original. See `create-pasg-jira-tickets` for the editing procedure.

## Anti-patterns

- Building from a plan doc, an earlier conversation, or a memory when a ticket exists. The ticket wins, always.
- Reading a summary of the ticket instead of the ticket. Subagents report verbatim.
- Skipping the comments and missing a scope change recorded there.
- Silently implementing a better idea than the one the ticket describes.
- Delivering a subset of the acceptance criteria and reporting completion.
- Gold-plating past the acceptance criteria because you were already in the file.
- Letting the code define the scope and updating the ticket afterward to match what you happened to build.
- Resolving an ambiguity in chat and never writing the answer back onto the ticket.
- Marking `DONE` without re-reading the ticket to confirm the comment and status actually saved.
