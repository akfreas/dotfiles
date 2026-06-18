---
name: perplexity-research
description: >-
  Use the Perplexity MCP search tool to gather up-to-date, cited context from
  the web before planning, implementing, or answering — and to do company /
  competitive / due-diligence intel. Invoke whenever the user says "use
  perplexity", "research using perplexity", "do research using perplexity to
  understand X", "research anything you don't have up-to-date knowledge of",
  asks for company/market intel, or otherwise wants current web facts that may
  be past the knowledge cutoff. The tool is
  `mcp__perplexity-mcp__perplexity_search_web`.
---

# Perplexity Research

Use this skill to pull **current, source-backed facts off the web** with Perplexity, then act on them. It exists because the model's knowledge has a cutoff and the user routinely wants research-informed plans, not guesses.

The single most common request is some form of: *"research X using perplexity so you have real context before you do the thing."* The research is a means to an end — finish by **doing the thing** (the plan, the code, the doc), grounded in what you found.

## The tool

`mcp__perplexity-mcp__perplexity_search_web` — load its schema first if not already available:

```
ToolSearch query: "select:mcp__perplexity-mcp__perplexity_search_web"
```

Parameters:
- `query` (string, required) — the search query.
- `recency` (`day` | `week` | `month` | `year`, default `month`) — **default to `year`** for most research. The tool's own default of `month` is too tight and silently drops relevant older results. Only narrow to `week`/`day` when the user explicitly wants breaking/recent-only news.

Perplexity returns a synthesized answer **with citations**. Treat its prose as a lead, not gospel — the citations are the real payload. For anything you'll act on or assert, **WebFetch the cited source** to confirm (load WebFetch via `ToolSearch query: "select:WebFetch"`).

## When to use

Trigger phrasings (all observed in real usage):
- "Use perplexity to research how to best do X" / "Do research using perplexity to understand the proper way to do this"
- "Research using perplexity on any topic you think could benefit from more context"
- "Use perplexity to research anything you don't have up-to-date knowledge of"
- "that is ridiculous, do more research using perplexity to figure this out"
- "Do a perplexity search here to create company intel" / due-diligence on a named company
- Explicit `mcp__perplexity-mcp__perplexity_search_web` or `/perplexity-mcp:perplexity_search_web` references

Use it for: library/API/framework best practices, version-specific behavior, vendor docs and limits, pricing, enum/field values, platform quirks (Xcode Cloud, Supabase Realtime, AWS Secrets Manager, etc.), and company/market/competitor intel.

Do **not** reach for it when the answer is in the codebase, in files the user pointed at, or is stable knowledge well within the cutoff. Search the repo first; use Perplexity for what the repo can't tell you.

## How to query well

The user's queries are precise and dense — mirror that:

- **Quote exact phrases and identifiers**: `"shepherd.vet"`, `"appStoreState"`, `"xcrun simctl"`. Quotes pin Perplexity to the literal term.
- **Use `OR` for synonyms/aliases**: `"Shepherd Pay" OR "shepherd.vet" npm pypi package`.
- **Pack in the specifics**: versions, error strings, enum values, platform, year. `"Azure OpenAI Responses API 60 second timeout RemoteDisconnected long reasoning gpt-5"` beats `azure timeout`.
- **One question per query.** Fan out across several narrow queries rather than one broad one.
- **Disambiguate hard** when a name collides. State what to include and what to exclude, exactly as the user does: *"Shepherd Veterinary Software, website shepherd.vet — NOT the church/farming/video-game/marketing-agency results."* Carry that disambiguation into every query in the batch.

## Fan out for breadth

For anything beyond a single lookup — due diligence, "research the X angle and the Y angle", multi-faceted topics — **spawn parallel agents**, one per angle, each running its own Perplexity queries. The user asks for this directly ("do more research using perplexity, fanning out agents to check out: …"). Give each agent its disambiguation, its angle, and instruction to return findings **with source URLs**. Launch them in one message so they run concurrently.

Good angle splits seen in practice: GitHub/open-source angle, Reddit/community-sentiment angle, official-docs/API angle, pricing/limits angle, people/LinkedIn angle.

## Cite everything — claims must be traceable

The user expects assertions to be **traceable back to a source**. When you write up findings, a plan, or a doc informed by Perplexity:

- Attach a **markdown link** to each non-obvious claim: `... is rate-limited to 10k calls ([AWS docs](https://…))`.
- Prefer linking the **underlying source** Perplexity cited (the one you WebFetched), not a Perplexity URL.
- If asked to "add markdown links so we can trace where the claim was made," go back through the document and source **every** claim, not just the new ones.
- If a claim can't be sourced, say so plainly rather than presenting it as established fact.

## Shape of a typical run

1. Search the repo / read pointed-at files first — don't Perplexity what you already have.
2. Decompose the question into narrow, disambiguated queries (`recency: "year"` unless told otherwise).
3. Run them — fan out to parallel agents if there are multiple angles.
4. WebFetch the key cited sources to verify before relying on them.
5. Deliver the actual thing the user asked for (plan / code / doc / answer), with claims linked to sources.
