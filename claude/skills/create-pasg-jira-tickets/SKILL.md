---
name: create-pasg-jira-tickets
description: >-
  Create, review, and update Jira tickets in the PASG Atlassian instance by calling its
  REST API with fetch() from inside the authenticated Chrome tab (no API token, no Jira
  MCP, and no clicking through forms). Bakes in the standing conventions — PASGAI project,
  Alex Freas as assignee, no story points, and the four-section ticket body. Use when the
  user invokes /create-pasg-jira-tickets, asks to "create Jira tickets", "make an epic on
  Jira", "turn this plan into tickets", "update PASGAI-XXX", or to review/verify
  existing tickets against a plan.
---

# Create Jira tickets

Turn a plan, a feature idea, or a scope change into well-formed Jira work items in the PASG instance — and keep existing tickets honest as the work evolves.

Jira is reached through the PASG Chrome profile — but **drive it with the REST API from inside the page, not by clicking**. See [Talking to Jira](#talking-to-jira) below; read that section before touching a ticket. There is no standalone API token, no `acli`, and no Atlassian MCP server, so `curl` from the shell will not authenticate.

## Standing parameters

Unless the user overrides them in the request, these are the defaults:

| Parameter | Value |
| --- | --- |
| Instance | `https://paloaltostrategygroup.atlassian.net` |
| Project | `PASGAI` ("PASG AI Project") |
| Board | `https://paloaltostrategygroup.atlassian.net/jira/software/projects/PASGAI/boards/2` |
| Backlog list view (rank-ordered) | `https://paloaltostrategygroup.atlassian.net/jira/software/projects/PASGAI/list?jql=project%20%3D%20PASGAI%20ORDER%20BY%20cf%5B10019%5D%20ASC` |
| Single ticket | `https://paloaltostrategygroup.atlassian.net/browse/PASGAI-<n>` |
| Assignee | `Alex Freas` — that is the literal account name. Searching "Alexander" returns **no match**. Via API, resolve the accountId with `/rest/api/3/user/search?query=Freas`. |
| Story points | **Never set them.** Leave the field empty. |
| Epic | Optional. Only create/attach one when the user asks; otherwise attach tickets straight to the project. |
| Statuses | `BACKLOG`, `TO DO (APPROVED)`, `IN PROGRESS`, `IN REVIEW`, `DONE`, `NOT DOING` |
| Labels | Reuse existing ones (`agentic`, `skills`, …). Don't invent a new label without asking. |

Structure: a **Story/Task** per unit of shippable behavior, with **Subtasks** for the individual commits/work items beneath it. Express ordering with **"is blocked by"** links, not with prose in the description.

## Talking to Jira

**Drive Jira with `fetch()` against its REST API, executed inside the authenticated page.** Do not create or edit tickets by clicking fields. Clicking a set of tickets through the UI takes over an hour and hundreds of thousands of tokens; the same work over the API takes a couple of minutes and a handful of calls. Reserve clicking for the one case the API cannot cover — visually confirming something renders as intended.

The session cookie is HttpOnly, so it cannot be read out and used from the shell. It does not need to be: a `fetch()` running **on the Jira origin** has the browser attach it automatically. Nothing is extracted, stored, or passed through you.

### Step 1 — Establish the session (once per session)

1. `mcp__claude-in-chrome__tabs_context_mcp` with `createIfEmpty: true`.
2. If several Chrome instances are connected, `list_connected_browsers` then **ask the user which one** — only one profile is signed in. A wrong pick lands on `id.atlassian.com/login`.
3. `navigate` that tab to `https://paloaltostrategygroup.atlassian.net/browse/PASGAI-1` (any Jira URL works — it only has to put the tab on the right origin).
4. Wait ~5s, then confirm the tab title is a Jira page and not a login screen.

Every call below then runs via `mcp__claude-in-chrome__javascript_tool` against that `tabId`. Paths are relative (`/rest/api/...`) so they inherit the origin; always pass `credentials: 'include'`.

### Step 2 — Use v2 for writing, v3 for reading

This is the single most important detail. **API v3 requires the description to be an ADF document** — a deeply nested JSON tree that is miserable to author and easy to get wrong. **API v2 accepts a plain string with Jira wiki markup**, which maps directly onto the house ticket format:

| Ticket format | Wiki markup |
| --- | --- |
| Section heading | `_What this delivers._` on its own line |
| Acceptance criteria | lines starting `* ` |
| Numbered sequence | lines starting `# ` |
| Paragraph break | one blank line |

So: **write with `/rest/api/2/`, read with `/rest/api/3/`.** Avoid em-dashes and backticks in bodies sent this way — plain hyphens and unquoted identifiers survive the round-trip cleanly.

**`*text*` means different things in the two paths, and mixing them leaves a ticket set visibly inconsistent.** In wiki markup (API) `*text*` is **bold** and `_text_` is *italic*; in the browser editor, a pasted `*text*` is read as markdown and comes out *italic*. Existing PASGAI tickets use **italic** section headings, so **write `_Heading._`** to match. Before appending to a ticket, `GET` the v2 description and match whatever style is actually in it rather than assuming.

That also means **you cannot blind-append**: `PUT` replaces the whole description, so fetch the current v2 text, splice into it, and put the whole thing back. Anchor the splice on a marker you have *read*, not one you assume is there.

### Step 3 — The calls

Create an issue (returns the new key). Subtasks add `parent`; top-level issues omit it:

```js
const r = await fetch('/rest/api/2/issue', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  credentials: 'include',
  body: JSON.stringify({fields: {
    project:   {key: 'PASGAI'},
    issuetype: {name: 'Story'},            // Story | Task | Bug | Epic | Subtask
    summary:   'One-line summary',
    description: bodyText,                  // wiki markup string
    labels:    ['agentic', 'skills'],
    assignee:  {id: accountId},             // from /rest/api/3/user/search?query=Freas
    // parent: {key: 'PASGAI-189'}          // subtasks only
  }})
});
(await r.json()).key
```

Set or replace a description on an existing issue (`204` = success):

```js
await fetch(`/rest/api/2/issue/${key}`, {
  method: 'PUT', headers: {'Content-Type': 'application/json'}, credentials: 'include',
  body: JSON.stringify({fields: {description: bodyText}})
});
```

Link two issues. **Direction matters and is easy to invert** — for "A is blocked by B", A is the `inwardIssue` and B is the `outwardIssue`:

```js
await fetch('/rest/api/3/issueLink', {
  method: 'POST', headers: {'Content-Type': 'application/json'}, credentials: 'include',
  body: JSON.stringify({
    type: {name: 'Blocks'},
    inwardIssue:  {key: blockedIssue},
    outwardIssue: {key: blockerIssue}
  })
});
```

Comment, and transition status:

```js
await fetch(`/rest/api/2/issue/${key}/comment`, {
  method: 'POST', headers: {'Content-Type': 'application/json'}, credentials: 'include',
  body: JSON.stringify({body: commentText})
});

const ts = await (await fetch(`/rest/api/3/issue/${key}/transitions`, {credentials:'include'})).json();
const id = ts.transitions.find(t => t.name === 'In Review').id;
await fetch(`/rest/api/3/issue/${key}/transitions`, {
  method: 'POST', headers: {'Content-Type': 'application/json'}, credentials: 'include',
  body: JSON.stringify({transition: {id}})
});
```

Loop over a batch in **one** `javascript_tool` call, collecting `{key, status}` per item, rather than one call per ticket.

### Step 4 — Read back and verify, always

Creating is not the same as saving correctly. Finish every batch with a single read-back that proves each field landed:

```js
const rows = [];
for (const k of keys) {
  const f = (await (await fetch(`/rest/api/3/issue/${k}?fields=summary,issuetype,assignee,labels,parent,description,issuelinks`, {credentials:'include'})).json()).fields;
  const blockedBy = (f.issuelinks||[]).filter(l => l.outwardIssue && l.type.name === 'Blocks').map(l => l.outwardIssue.key);
  rows.push(`${k} ${f.issuetype.name} desc=${JSON.stringify(f.description||'').length} parent=${f.parent?f.parent.key:'-'} ${f.assignee?f.assignee.displayName:'UNASSIGNED'} [${(f.labels||[]).join('+')}] blockedBy=${blockedBy.join(',')||'-'}`);
}
rows
```

Check the **description length** on every row. A short one means the body never landed — this has caught silent truncation that looked fine in the UI. Re-`PUT` any that are wrong.

When reading links, note that Jira returns only the *other* issue: on issue X, an entry carrying `outwardIssue: Y` means "X is blocked by Y", and one carrying `inwardIssue: Z` means "X blocks Z". Getting this backwards makes a correct chain look inverted.

## Ticket body format

Every ticket description — story and subtask alike — uses these four sections, in this order:

**What this delivers.** Plain-English purpose. What is broken or missing today, and what is true once this ships. Written so a manager reading only this paragraph understands why the ticket exists.

**Input / output.** What goes in, what comes out. If there is no runtime input (a wiring/config ticket), say so explicitly — "No runtime input; this is prompt/config wiring plus tests" — and then state the *observable* result.

**Technical shape.** The actual engineering. Name real files, functions, and modules (`agentic/runner.py:_agentic_turn_instructions`), the mechanism (injection vs. matching, sync vs. async, which layer owns what), and which test files get extended. This section is why a manager can tell what is being done *technically*, not just what the feature is.

**Acceptance criteria.** A short bulleted list of concrete, checkable outcomes. Each one must be something a person could verify by looking at the system, not a restatement of the task.

## Writing rules — earned the hard way

These exist because real tickets were rejected for violating them. Hold the line.

- **Every ticket must answer three questions: what goes in, what drives the interaction, and what we get when it's finished.** A ticket that leaves any of the three implicit is not done being written.
- **Technical *and* practical.** "As a manager I should be able to tell what we are doing technically, it's not just about the feature." Both registers in every ticket — never one at the expense of the other.
- **No AI slop.** No jargon mouthfuls, no impressive-sounding sentences with no substance, no filler adjectives. Professional and crisp.
- **Never paste test-result phrasing into a description as if it were a requirement.** A line like "Tested standalone against a mixed fixture set: each diagram kind correctly labeled" is meaningless to a reader who doesn't already know the code. State what is being verified and why it matters instead.
- **No references to local files.** Strip mentions of markdown plans, scratchpad docs, and repo paths *used as sources*. Ticket text may reference other Jira tickets by key and may name source files as *implementation targets* — but never "see `plan.md`". The ticket has to read as a standalone Jira ticket. Cross-reference sibling tickets by key (PASGAI-180), not by document.
- **Ground the narrative.** When a ticket or epic explains how a decision was reached, tie it to real events — the analyses that were run, what they showed, who weighed in — so it is grounded in actual work rather than reconstructed rationale.
- **Write it as the final authority, because it is.** Once a ticket exists it is the only document anyone works from — the engineer implements from it and the manager checks the finished work against it. Neither of them will open your plan doc. So a ticket that is vague, incomplete, or out of date doesn't merely read badly; it guarantees drift between what was asked for and what gets built. Every gap you leave becomes an invented decision downstream. Implementation is governed by `build-using-pasg-jira-tickets`, which treats these tickets as absolute — write them so that is a safe thing to do.

## Procedure — creating tickets

1. **Load the source.** Read the plan/doc/feature description the user pointed at. If the work touches a codebase, investigate it enough to write a real **Technical shape** section — file names and functions, not guesses. Don't write a ticket for code you haven't looked at.
2. **Decide the shape.** Stories vs. subtasks, and what blocks what. Epic only if asked.
3. **Draft every ticket body in full, in a scratchpad file, before opening Jira.** Drafting first lets the user review the wording cheaply, and gives you the exact strings to send.
4. **Establish the session.** Follow [Talking to Jira](#talking-to-jira) step 1 — pick the signed-in Chrome profile and park a tab on the Jira origin.
5. **Create everything over the API.** One `javascript_tool` call per phase, not per ticket: create the parent, then loop the subtasks, then loop the links. Set summary, description, assignee, labels and parent in the create call. Leave story points empty.
6. **Read back and verify.** Run the step-4 verification loop and check the description length on every row. Report the created keys and URLs.

Delegate to a **subagent** when you are also writing code in the same session. Give it the fully-drafted text and tell it explicitly whether it may mutate tickets or is read-only.

## When you do touch the rich-text editor

The API path avoids the editor entirely, which is most of why it is faster. If you ever fall back to typing into a ticket by hand, these all silently reformat input:

- **`- ` at line start becomes a bullet list**, and successive lines nest progressively deeper. Use **Shift+Enter** soft line breaks, or paste the whole block from the clipboard in one go.
- **Backtick-wrapped tokens auto-render as inline code chips.** Usually fine — just know the raw backticks won't survive.
- **`---` is consumed as a delimiter** and vanishes. Don't structure a body with horizontal rules.
- **The editor does not reliably open on the first click**, and a click that misses lands your keystrokes somewhere else — in the body of another field, or in a stray Create dialog. Confirm the editor is open (its Save button exists) *before* typing or pasting.
- **Always verify after save**, and prefer re-`PUT`ing the whole description over patching it in place.

## Procedure — reviewing tickets against a plan

When the user asks to verify that tickets still match reality (titles drift, scope changes land in chat but not in Jira):

1. Read each ticket **from Jira over the API** — not from memory, not from the plan doc. Stale local copies are exactly what this check exists to catch. One `javascript_tool` call can fetch every ticket in the set at once.
2. Compare against the current plan/decisions, field by field: title, description sections, acceptance criteria, links, status.
3. **Write a scratchpad report of the deltas and stop.** Do not mutate tickets in the same pass. The user reviews the change list, then you apply it in the next turn.
4. Apply approved changes one ticket at a time, verifying each save.

## Procedure — a scope change lands mid-flight

When a decision drops or adds scope after a ticket exists (often discovered while the work is underway), the ticket must be corrected immediately — a ticket that no longer describes the agreed scope is the exact drift this whole convention exists to prevent.

1. Edit the description **surgically**: remove or amend only the affected sentences, leaving every other section byte-identical. Scan the whole body for other mentions of the dropped scope; there is usually more than one.
2. Post a comment stating what changed and why, in the user's words where possible.
3. Leave earlier comments untouched even when they now contradict the description. They are the historical record of how the scope moved.
4. Re-read the saved ticket and confirm both the edit landed and nothing else shifted.

## Implementing a ticket

Out of scope for this skill. To build a ticket that already exists, use **`build-using-pasg-jira-tickets`**, which shares these same parameters and treats the ticket as the absolute authority.

## Anti-patterns

- **Clicking tickets into existence field by field.** It is the slowest and least reliable path — an hour and enormous token cost for what the API does in minutes. Use the UI only to eyeball a result.
- Trying to `curl` Jira from the shell, or hunting for an API token. There isn't one; the auth lives in the browser session.
- Sending a description to `/rest/api/3/` as a raw string. v3 needs ADF — use v2 for writes.
- Writing a ticket from a plan doc without reading the code it describes, then filling **Technical shape** with plausible-sounding invention.
- Leaving a plan-doc reference ("as described in `diagram_extraction_plan.md`") in a ticket body.
- Setting story points because the field is there.
- Reporting success on a create/update without a read-back that checks description length. A truncated body looks fine until someone opens it.
- Inverting a blocked-by link because the inward/outward fields read backwards from what you expect.
- Mutating tickets during a verification pass instead of producing the delta report first.
