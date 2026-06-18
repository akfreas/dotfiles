#!/usr/bin/env bash
# Print every valid body-slide ID, one per line.
source "$(dirname "$0")/_common.sh"

RAG_REPO="$RAG_REPO" "$PY" -c "import os,sys; sys.path.insert(0, os.environ['RAG_REPO']); from services.slide_config import get_all_body_slide_ids; print('\n'.join(get_all_body_slide_ids()))"
