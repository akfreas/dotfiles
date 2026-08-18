---
name: explain-in-plain-english
description: >-
  Explain a topic the way a person would explain it to another person — organized
  around the idea rather than around the sources, causal prose rather than quoted
  evidence. Runs in three passes: announce the plan, write a dense technical
  report to a file for yourself, then produce a short human-facing explanation
  and offer the technical report as a follow-up. Use when the user invokes
  /explain-in-plain-english, or asks to "explain X in plain english", "help me
  understand X", "what does this actually mean", "give it to me straight", or
  says a previous explanation was hard to read.
---

# Explain In Plain English

A person asking "explain this to me" wants to *grok the idea*. They do not want proof that you did the research. Those are different documents, and the failure mode this skill exists to prevent is shipping the second one when they asked for the first.

So write both. The technical one goes in a file, for you and for follow-up questions. The human one goes in the chat.

## Parameters

- **topic** (required) — what to explain. May be a question, a concept, a subsystem, a person's changes, a decision.
- **source** (optional) — where to look: paths, a repo area, commits/branches/PRs, URLs, docs, a Linear/Jira ID, a prior conversation. When absent, infer it from the topic.

If no topic is given at all, infer one from the recent conversation and say so in the first line of step 1.

## Step 1 — Announce before you research

Before any tool call that gathers information, post a short block (a few lines, not a document):

- **What I think you're asking** — the topic in your own words. If you inferred the topic or the sources, say **explicitly** which parts are inferred, so a wrong guess gets caught before you spend the effort.
- **Where I'm going to look** — the concrete sources: files, commit ranges, authors, docs, the web.

Then start gathering immediately in the same turn. This is a checkpoint the user can interrupt, not a question that blocks — do not wait for approval.

Gather widely. The value of this skill is assembling context a human could not assemble quickly: read the whole commit range, all the relevant files, the tests, the docs, the PR discussion. Delegate broad sweeps to subagents when the reading is large. Over-gather here; you compress later.

## Step 2 — Write the technical report to a file

Write a dense, verbose, source-anchored report and save it. **Do not print it in the chat.**

Path: the session scratchpad directory if one exists, otherwise a temp directory. Name it `explain-<topic-slug>.md`. Keep the absolute path — step 3 cites it.

This document is written for you, not for a person. Optimize for retrieval and precision, not readability:

- Every claim carries its source: `file.py:120`, a commit hash, a URL, a quoted line.
- Quote the actual text where wording matters. Include signatures, flags, config values, schema shapes.
- Record contradictions, dead ends, and things you could not confirm — those are exactly what follow-up questions land on.
- Note what you did *not* read, so a later turn knows where the gaps are.

Jargon is fine here. Length is fine here. This is the receipts.

## Step 3 — Write the human-facing explanation

Now throw away the structure of the report and rebuild around the idea.

### Find the one thing first

Almost every topic has a single load-bearing idea, and everything else is a consequence of it. Find it and open with it in one or two plain sentences. Then let each remaining piece arrive as an answer to "what did that force us to change?"

If you cannot name the one thing, you have not finished understanding the topic — go back to step 2.

### Organize by idea, never by source

Do not structure the explanation as one section per commit, per file, per ticket, or per document. That makes the reader assemble the story themselves out of disconnected buckets. Sources are how *you* found the answer; they are not how the answer is shaped.

### Explain, don't quote

A quoted rule tells the reader what a file says. They asked what *happens differently now*. Convert every quote into consequence. Signatures, flags, exact paths, and code blocks almost never belong here — they are in the report.

### Give everything a reason for existing

For each component, say what would go wrong without it before saying what it does. "Editing a real 40-slide deck risks quietly wrecking slide 12 while fixing slide 28, so there's now a checker that proves you didn't" beats any accurate description of the checker.

### Drop the internal vocabulary

Repo-internal terms of art make you sound embedded and tell the reader nothing. Replace each one with what it means in ordinary words. If a term is genuinely load-bearing and the reader will meet it again, introduce it once in plain words and then use it.

### Prose over bullet fragments

Causal chains — *it used to be X, that was risky because Y, so now Z* — cannot survive being chopped into bullets. Use paragraphs. Reserve lists for things that are genuinely a set of parallel items, and keep heading density low. Bold-lead bullets and nested lists signal structure while actually fragmenting the argument.

### Close with the short version

End with one or two sentences someone could repeat out loud to a colleague.

### Length

Shorter than you want it to be. This is a conversation opener, not a reference. Details get drilled down in later turns — that is the point of having the report.

## Step 4 — Offer the receipts

End the chat message with a single line, plainly worded, telling the user there is a fuller evidence-backed version with the sources cited and where it is. Something like:

> I also wrote the dense, source-cited version to `<absolute path>` if you want the evidence-backed take instead — happy to walk through any part of this from there.

Keep it to one line. Do not summarize the report, and do not apologize for the plain version.

## Follow-up turns

When the user asks a follow-up, re-read the saved report rather than re-researching. Answer follow-ups in the same plain register unless they ask for specifics — a request for a file path, an exact value, or "show me the code" is a request to switch registers, and then precision wins over readability.

## Anti-patterns

These are the specific ways this goes wrong:

- Structuring the explanation around commits, PRs, or files instead of the idea.
- Leading with what you found rather than what it means.
- Block quotes of prose from the sources, or function signatures, in the human output.
- Listing components with no reason given for why each exists.
- Passive hedging that avoids committing to what actually changed.
- Writing to demonstrate thorough research instead of writing to be understood.
- Printing the technical report into the chat, or skipping it because the topic "seems simple" — the report is what makes follow-ups cheap.
