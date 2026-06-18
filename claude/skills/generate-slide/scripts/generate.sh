#!/usr/bin/env bash
# Generate one slide and deliver it via OneDrive ONLY.
# Usage: generate.sh <SLIDE_ID> [extra run_slide.py args...]
#
# Runs run_slide.py WITHOUT --output_dir, so the deck uploads to OneDrive and the
# URL is printed to stdout. This skill never writes local output: if OneDrive is
# not connected the runner exits non-zero and this script propagates that failure.
source "$(dirname "$0")/_common.sh"

if [ $# -lt 1 ]; then
  echo "usage: generate.sh <SLIDE_ID> [extra args]" >&2
  exit 64
fi
slide_id="$1"; shift

cd "$WORKBENCH_DIR"
exec "$PY" run_slide.py --slide_id "$slide_id" --open_in_browser "$@"
