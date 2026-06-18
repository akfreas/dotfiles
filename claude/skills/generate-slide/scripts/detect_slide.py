#!/usr/bin/env python3
"""Infer which slide the user is working on from git changes in the rag repo.

Maps every body-slide's prompt/schema/template path (from services.slide_config)
to its slide ID, then intersects that with the files changed on the current rag
branch (uncommitted changes + commits since the merge-base with main).

Prints one candidate slide ID per line. Prints nothing (exit 0) if no slide's
files were touched. Must be run with the workbench venv so slide_config imports.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

RAG_REPO = Path(os.environ.get("RAG_REPO", "/Users/akfreas/freelance/PASG/rag")).resolve()


def _git(*args: str) -> list[str]:
    try:
        out = subprocess.run(
            ["git", "-C", str(RAG_REPO), *args],
            capture_output=True, text=True, timeout=10,
        )
    except Exception:
        return []
    return [l.strip() for l in out.stdout.splitlines() if l.strip()]


def changed_files() -> set[str]:
    files: set[str] = set()
    # Uncommitted (staged + unstaged + untracked) changes.
    for line in _git("status", "--porcelain"):
        # Format: "XY path" (rename shows "old -> new"); take the final token.
        path = line[3:].strip() if len(line) > 3 else line
        if "->" in path:
            path = path.split("->")[-1].strip()
        if path:
            files.add(path)
    # Commits on this branch since it diverged from main.
    base = _git("merge-base", "HEAD", "main")
    diff_range = f"{base[0]}...HEAD" if base else "HEAD"
    files.update(_git("diff", "--name-only", diff_range))
    return files


def main() -> int:
    sys.path.insert(0, str(RAG_REPO))
    try:
        from services.slide_config import BODY_SLIDE_CONFIGS
    except Exception as exc:  # pragma: no cover
        print(f"error: could not import slide_config: {exc}", file=sys.stderr)
        return 1

    path2id: dict[str, str] = {}
    for sid, cfg in BODY_SLIDE_CONFIGS.items():
        for attr in ("prompt_path", "schema_path", "template_path"):
            p = (getattr(cfg, attr, "") or "").strip()
            if p:
                path2id[p] = sid

    changed = changed_files()
    hits = sorted({
        sid for p, sid in path2id.items()
        if any(c.endswith(p) or p in c for c in changed)
    })
    for sid in hits:
        print(sid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
