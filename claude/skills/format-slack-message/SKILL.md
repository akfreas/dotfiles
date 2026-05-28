---
name: format-slack-message
description: >-
  Compose a Slack-ready message from the user's request and load it onto the
  macOS clipboard as rich HTML so a single Cmd+V into Slack lands with full
  formatting (bold, italic, inline code, code blocks, lists, links, quotes).
  Use this whenever the user asks for "a Slack message", "something I can
  paste into Slack", or invokes `/format-slack-message`.
---

# format-slack-message

Goal: when the user describes a message they want to send in Slack, produce the final wording AND put a rich-HTML version on their clipboard so they can paste it directly into Slack's composer without re-typing any formatting.

## Why HTML and not Slack mrkdwn

Slack's desktop client reads the `public.html` pasteboard flavor when present and converts standard HTML tags to its native formatting. `pbcopy` only writes plaintext, which is why Markdown-style backticks pasted from a terminal arrive in Slack as literal `` ` `` characters. The helper script in this skill uses AppleScript's `«data HTML...»` form to attach raw HTML bytes under the HTML pasteboard type — that's what Slack picks up.

## Procedure

1. **Understand the message.** Confirm the audience, tone, and key points from the user's request. If the request is ambiguous (one-liner vs. multi-paragraph, casual vs. formal, channel vs. DM), ask one short clarifying question before composing.
2. **Draft the message** in your head as Slack-flavored text — bold for emphasis or labels, inline code for filenames/commands/identifiers/error strings, code blocks for multi-line snippets, lists for enumerations, links for URLs.
3. **Render to HTML** using only the tag set in the mapping table below. Escape `&`, `<`, `>` inside literal content.
4. **Pipe to the clipboard** via the helper:
   ```sh
   printf '%s' '<HTML HERE>' | ~/.claude/skills/format-slack-message/to-clipboard.sh
   ```
   For multi-line HTML, prefer a heredoc:
   ```sh
   ~/.claude/skills/format-slack-message/to-clipboard.sh <<'HTML'
   <p>First paragraph with <strong>bold</strong> and <code>inline</code>.</p>
   <p>Second paragraph.</p>
   HTML
   ```
5. **Show the user a plaintext preview** of the message (no HTML tags) so they can sanity-check the wording before pasting. Confirm in one line that it's on the clipboard and ready to paste.

## HTML → Slack mapping

| HTML | Slack result |
| --- | --- |
| `<strong>` or `<b>` | **bold** |
| `<em>` or `<i>` | _italic_ |
| `<s>` or `<del>` | ~strikethrough~ |
| `<code>` | `inline code` |
| `<pre><code>…</code></pre>` | fenced code block |
| `<a href="URL">text</a>` | linked text |
| `<ul><li>…</li></ul>` | bulleted list |
| `<ol><li>…</li></ol>` | numbered list |
| `<blockquote>…</blockquote>` | > quoted line |
| `<br>` or `<p>` boundary | line break / paragraph break |

Tags outside this table (headings, tables, images, divs with styles, spans with classes) are not reliably honored by Slack on paste — don't use them.

## Composition rules

- **Code spans for tokens, not sentences.** Wrap filenames (`publish-npm.yaml`), commands (`pnpm build:pkgs`), identifiers (`MyComponent`), env vars, file paths, and error strings. Don't wrap whole sentences in `<code>`.
- **Code blocks for multi-line snippets.** Always `<pre><code>…</code></pre>` (Slack ignores bare `<pre>` for code styling). Include a language hint only if the user asked for one — Slack doesn't render it but it documents intent.
- **Paragraphs.** Prefer `<p>…</p>` blocks for distinct paragraphs. Use `<br>` only for soft line breaks inside one paragraph (e.g., a signature).
- **Lists.** Use `<ul>`/`<ol>` for any enumeration of two or more items. Don't fake bullets with `•` or `-` — Slack's native list rendering is cleaner.
- **Links.** Use `<a href="…">descriptive text</a>`. Don't paste raw URLs unless the URL itself is the point.
- **Escape literals.** Inside `<code>` and elsewhere, replace `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`. (Quotes inside attribute values: `&quot;`.)
- **No leading/trailing whitespace** in the HTML — Slack preserves it and it looks sloppy.
- **No emoji unless the user asked.** If they did, use the literal Unicode glyph (🎉), not `:tada:` — pasted text doesn't trigger Slack's shortcode expansion.

## Confirming success

After running the helper, output one short line to the user, e.g.:

> Copied. Paste into Slack with Cmd+V.

Then show the plaintext preview (no HTML) so they can edit before sending if needed.

## Failure modes

- If `osascript` errors (rare — usually means the data was malformed), the helper exits non-zero. Re-check that all `&`/`<`/`>` in the source content are escaped, then retry.
- If the user reports formatting didn't survive the paste, ask which Slack client (desktop vs. web vs. mobile) — only the desktop app reads `public.html`. The web client and mobile apps fall back to plaintext, and there's no fix from the macOS side.
