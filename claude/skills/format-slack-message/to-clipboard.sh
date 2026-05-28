#!/bin/sh
# Read HTML from stdin and copy it to the macOS clipboard with BOTH the
# public.html flavor (for rich-text-aware apps like Slack desktop, Mail,
# Notes, TextEdit) AND a plaintext fallback (public.utf8-plain-text, for
# everything else, and required by many apps before they will accept a
# paste at all).
#
# Why this exists:
#   - `pbcopy` only writes plaintext, so HTML piped to it pastes as literal
#     angle brackets.
#   - AppleScript's `set the clipboard to «data HTML...»` form sets only
#     the HTML flavor and CLEARS all other flavors — Slack and many other
#     apps then treat the clipboard as empty and Cmd+V is a no-op.
#   - The fix is a record literal: `{string:"...", «class HTML»:«data ...»}`
#     which sets both flavors atomically.

set -eu

html=$(cat)

if [ -z "$html" ]; then
  echo "format-slack-message/to-clipboard.sh: no input on stdin" >&2
  exit 1
fi

tmpdir=$(mktemp -d -t slackclip)
trap 'rm -rf "$tmpdir"' EXIT

# Write HTML source for hex encoding.
printf '%s' "$html" > "$tmpdir/body.html"

# Derive a plaintext fallback by stripping tags. Try textutil first (handles
# entity decoding, list bullets, paragraph breaks); fall back to a sed strip
# if textutil rejects the input for any reason.
if ! printf '%s' "$html" \
     | textutil -stdin -stdout -format html -convert txt \
                -inputencoding UTF-8 -encoding UTF-8 \
       > "$tmpdir/body.txt" 2>/dev/null; then
  printf '%s' "$html" | sed -e 's/<[^>]*>//g' > "$tmpdir/body.txt"
fi

hex=$(xxd -p -u < "$tmpdir/body.html" | tr -d '\n')

# Use a multi-flavor record so the clipboard has both string and HTML
# representations. The plaintext is read from disk to handle multi-line
# content without AppleScript string-escaping pitfalls.
osascript <<APPLESCRIPT
set plainText to read POSIX file "$tmpdir/body.txt" as «class utf8»
set the clipboard to {string:plainText, «class HTML»:«data HTML${hex}»}
APPLESCRIPT
