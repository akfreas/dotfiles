---
name: documentation-review
description: Interactive documentation review that DEFERS edits. The user raises critiques or questions about docs; you explain/answer them and log each as a proposed change into one per-session file under `documentation-notebook/` named `documentation-review-<chat_id>.md` — without editing the docs. The point of deferring is to see the whole set of changes at once so doc-wide/systemic issues surface before anything is touched, then apply them together in a deliberate pass. Use when the user invokes /documentation-review, asks to "review"/"critique" documentation, or starts pointing out problems or questions about docs for you to note for a later pass.
---

# Documentation Review

A two-phase workflow for reviewing documentation: a **capture phase** (default,
most of the time) where critiques and questions are collected without changing
any docs, and a separate **apply phase** that happens only when the user says
they are ready.

## Why defer instead of fixing each item as it comes up

This is the whole reason the skill exists. Fixing documentation one critique at a
time is actively harmful:

- **Systemic issues only become visible across many comments.** A single remark
  often turns out to be an instance of a doc-wide problem (e.g. "this section
  narrates code instead of explaining the concept" is rarely one section). If you
  fix it in place immediately, you miss that it's everywhere — or you fix it
  inconsistently across files.
- **Early fixes can be invalidated by later realizations.** A later comment may
  reframe earlier ones; piecemeal edits made before that realization have to be
  redone.
- **Batching keeps the docs consistent.** Applying a coherent set of changes in
  one deliberate pass (often after spotting the cross-cutting theme) produces
  uniform results; trickle edits drift.

So during review you **collect and explain**; you do **not** edit the docs. The
review file is the declared set of changes. Acting on them is a separate, later
step the user initiates.

## The review file

One markdown file per chat session, holding every entry from that session.

- **Location:** `documentation-notebook/` at the **root of the project**. Resolve
  the root with `git rev-parse --show-toplevel`; fall back to the current working
  directory if not a git repo. Create `documentation-notebook/` if it does not
  exist (just write into it — no need to pre-check).
- **Filename:** `documentation-review-<chat_id>.md`, where `<chat_id>` is the
  current chat/session ID. The ID is embedded so the user can resume the
  conversation later from the file alone (`claude --resume <chat_id>`).
- **One file per session:** on the first invocation in a session, create it; on
  every later invocation in the same session, **append** to the same file. Never
  start a second file for the same session.

### Determining the chat ID

Resolve it once, at the start, in this order:

1. `$CLAUDE_SESSION_ID` if set in the environment.
2. Otherwise derive it from your session's scratchpad / transcript directory path
   — it contains the session UUID as a path segment
   (e.g. `.../<UUID>/scratchpad`). Extract the UUID
   (`[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}`).
3. If you still cannot determine it, ask the user (they can read it from
   `/status`).

This UUID must be the same id `claude --resume <id>` accepts. If unsure, confirm
with the user once rather than guessing.

### File header (write on creation)

```markdown
# Documentation review — <chat_id>

Resume this conversation: `claude --resume <chat_id>`
Started: <YYYY-MM-DD>
Docs under review: <path(s) / area, e.g. documentation/agentic/>

This file collects review comments to be applied in a later pass — see the
documentation-review skill. Entries are not applied to the docs until the user
says they are ready. No doc edits are made during the capture phase.

---
```

Convert any relative date to an absolute one. If you don't know the date, ask or
omit it rather than guessing.

## Capture phase (the default loop)

For each critique or question the user raises:

1. **Explain / answer it first, in chat.** This is a real back-and-forth, not
   silent logging. If it's a question, answer it. If it's a critique, say what the
   doc is trying to convey, why the current wording falls short, and what the fix
   should be. A question almost always reveals unclear wording worth capturing,
   so capture it too.
2. **Append a structured entry** to the review file. Number entries sequentially
   across the session. Use this shape:

   ```markdown
   ## <N>. <short title of the issue>

   **Flag:** <what's wrong or unclear, in one or two sentences>

   **Where it appears:** <file(s) + section/heading; quote the offending text if
   the user did>

   **What it means / should say:** <the explanation you gave in chat, distilled —
   enough that the fix is actionable later without re-deriving it>

   **Proposed fix:** <concrete change: rewrite, restructure, add/remove, etc. Draft
   replacement text when useful.>

   **Status:** open

   ---
   ```

3. **Do not edit the documentation.** Capture only. The exception is if the user
   explicitly says to apply something now.

4. **Watch for cross-cutting themes as the queue grows.** If a new comment looks
   like an instance of a broader problem, say so in chat and record it as an
   overarching entry that names the pattern and notes which earlier entries it
   subsumes. Surfacing the systemic issue is the highest-value outcome of the
   review.

## Apply phase (only when the user says they're ready)

Do not start this until the user explicitly asks to apply / act on the review.
Then:

1. **Read the whole review file first** and look across all entries for
   cross-cutting or systemic changes. Decide whether a structural/sweeping change
   should lead (and reshape the individual fixes) before doing spot edits.
2. Propose a short application plan if the changes are broad (e.g. a doc-wide
   restructure plus targeted fixes). For large sweeps, consider doing the work in
   the background (e.g. one agent per file) driven by a written plan, so changes
   stay consistent.
3. Apply the changes, then verify (links/anchors resolve, formatting intact,
   nothing stale).
4. Mark applied entries `Status: resolved` (or append a short resolution note at
   the end recording which commits delivered them). Keep the file as the record.

## Rules

- Capture by default; never edit the docs during the capture phase unless told to.
- One file per session, named `documentation-review-<chat_id>.md`, append-only
  within the session.
- Always explain/answer in chat before logging — the value is the back-and-forth,
  not just the note.
- Keep entries actionable on their own: someone reading only the file later (or
  resuming the chat) should be able to act without re-deriving the reasoning.
- The review file is a working artifact under `documentation-notebook/`; do not
  commit it unless the user asks.
