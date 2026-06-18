#!/usr/bin/env bash
# Shared paths for the generate-slide skill scripts.
# Override either via environment if the repos ever move.
set -euo pipefail

WORKBENCH_DIR="${WORKBENCH_DIR:-/Users/akfreas/freelance/PASG/rag-slides-workbench}"
RAG_REPO="${RAG_REPO:-/Users/akfreas/freelance/PASG/rag}"
PY="$WORKBENCH_DIR/.venv/bin/python"

export WORKBENCH_DIR RAG_REPO PY
