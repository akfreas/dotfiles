#!/usr/bin/env bash
# Print the configured PROJECT_SLUG (from the rag or workbench .env), if any.
# Exits 0 and prints the slug when set; exits 1 and prints nothing when missing.
source "$(dirname "$0")/_common.sh"

line="$(grep -h '^PROJECT_SLUG=' "$RAG_REPO/.env" "$WORKBENCH_DIR/.env" 2>/dev/null | head -n1 || true)"
slug="${line#PROJECT_SLUG=}"
slug="${slug%\"}"; slug="${slug#\"}"; slug="${slug%\'}"; slug="${slug#\'}"
if [ -n "$slug" ]; then
  echo "$slug"
else
  exit 1
fi
