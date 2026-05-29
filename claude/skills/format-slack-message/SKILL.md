---
name: format-slack-message
description: >-
  Compose a Slack-ready message from the user's request and load it onto the
  macOS clipboard as rich HTML so a single Cmd+V into Slack lands with full
  formatting (italic, inline code, code blocks, lists, links, quotes).
  Use this whenever the user asks for "a Slack message", "something I can
  paste into Slack", or invokes `/format-slack-message`.
---

# format-slack-message

Goal: when the user describes a message they want to send in Slack, produce the final wording AND put a rich-HTML version on their clipboard so they can paste it directly into Slack's composer without re-typing any formatting.

## Why HTML and not Slack mrkdwn

Slack's desktop client reads the `public.html` pasteboard flavor when present and converts standard HTML tags to its native formatting. `pbcopy` only writes plaintext, which is why Markdown-style backticks pasted from a terminal arrive in Slack as literal `` ` `` characters. The helper script in this skill uses AppleScript's `«data HTML...»` form to attach raw HTML bytes under the HTML pasteboard type — that's what Slack picks up.

## Procedure

1. **Understand the message.** Confirm the audience, tone, and key points from the user's request. If the request is ambiguous (one-liner vs. multi-paragraph, casual vs. formal, channel vs. DM), ask one short clarifying question before composing.
2. **Draft the message** in your head as Slack-flavored text: inline code for filenames/commands/identifiers/error strings, code blocks for multi-line snippets, lists for enumerations, links for URLs. Never use bold for emphasis or labels. Get the voice right while drafting, not as a cleanup pass — see "Tone and voice".
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
| `<em>` or `<i>` | _italic_ |
| `<s>` or `<del>` | ~strikethrough~ |
| `<code>` | `inline code` |
| `<pre><code>…</code></pre>` | fenced code block |
| `<a href="URL">text</a>` | linked text |
| `<ul><li>…</li></ul>` | bulleted list |
| `<ol><li>…</li></ol>` | numbered list |
| `<blockquote>…</blockquote>` | > quoted line |
| `<br>` or `<p>` boundary | line break / paragraph break |

Tags outside this table (headings, tables, images, divs with styles, spans with classes) are not reliably honored by Slack on paste, so don't use them. `<strong>` and `<b>` are deliberately excluded: never emit bold (see composition rules).

## Tone and voice

Write the way the user writes in Slack: casual, first-person, direct, human. It's a message to teammates, not a release note, a status bulletin, or an announcement.

- **Greeting.** Open with a greeting to the readers. Default to "Hey team," unless the user names a specific audience when invoking the skill (e.g. a person, a channel, "the reviewers"), in which case greet them. Never lead with a label-style opener like "Heads up", "FYI", "Quick note", or "PSA".
- **Own mistakes plainly.** When the message is about an error, say it straight: "I made a mistake with X." Do not soften it into euphemism or spin it as a neutral FYI.
- **Plain everyday words over trendy or corporate register.** Prefer how a person actually talks. "merged to main" / "gets onto main", not "lands on main".
- **Use contractions and natural connective phrasing.** "there's no content changes" reads human; a clipped "— no content changes" does not.
- **Reference things in the flow of the sentence.** Name a PR/issue by its number inline ("the polyfill change in PR #288"); don't append its full title in parentheses.

### Banned robot / corporate phrases

These are high-frequency LLM and corporate-speak tics. They read as machine-written even when they're technically descriptive. Do not use them; rephrase in plain words or just cut them.

- Opener/filler: "Heads up", "Just a heads up", "Quick note", "FYI", "PSA", "Wanted to flag", "Wanted to surface", "Circling back", "Looping in", "Touching base".
- Euphemism for a mistake: "process slip", "small slip", "minor hiccup", "snag", "oversight occurred", "got crossed".
- Buzz-verbs: "lands"/"landed" (for merged/shipped), "leverage", "surface", "flag" (as a verb), "loop in", "align on", "sync up", "circle back", "drive", "unblock", "action" (as a verb), "operationalize".
- Hedge/padding: "just to be safe", "out of an abundance of caution", "for visibility", "as a quick aside", "at the end of the day", "to be clear" (when nothing was unclear).
- Closing fluff: "Let me know if you have any questions!", "Happy to discuss further", "Thanks in advance for your attention to this", "Appreciate your support".

Say what happened, what you need, and stop. A plain "Thanks!" is fine.

## Composition rules

- **Never use bold.** Do not emit `<strong>` or `<b>`, ever. There is no acceptable use for bold in these messages: not for emphasis, not for labels, not for headings, not for the first word of a list item. If something feels like it needs emphasis, rephrase it or lean on sentence structure instead. The user does not write bold themselves and will not accept it in a message authored on their behalf.
- **Never use an em dash (—).** Do not emit `—` (U+2014) anywhere in the message, and avoid the en dash (–, U+2013) too. When a sentence pulls toward an em dash, first restructure it: split into two sentences or join the clause with a comma, the way the user did ("re-targeted at main, there's no content changes"). Only if it genuinely still needs a dash, use a single hyphen-style dash (` - `) the way a person types in Slack. The goal is to avoid the dash construction in the first place, not to swap one dash glyph for another.
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
