#!/usr/bin/env python3
"""Provision (or reuse) a PASG v2 run workspace and print the real turn preamble.

This is the setup half of the ``emulate-pasg-agentic`` skill. It does the work
``agentic.runner.create_agent_run`` does before a turn — provision the
workspace, make sure ``source/source_snapshot.json`` exists — and then prints
the *actual* operating-context preamble the production runner would prepend,
via ``agentic.runner._agentic_turn_instructions``.

The preamble is the router. Skill selection in PASG v2 is injection, not
description ranking: the runner hands the agent a fixed list of skills and the
conditions under which to read each one. Emulating the agent therefore means
reading this text and obeying it, not inventing routing logic.

Nothing here calls an LLM, and nothing here decides which skill to use.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

DEFAULT_REPO_FALLBACK = Path("/Users/akfreas/freelance/PASG/rag")
REPO_MARKER = Path("agentic") / "runner.py"


def resolve_repo(explicit: str | None) -> Path:
    """Find the PASG repo: --repo, then $PASG_AGENT_REPO_ROOT, cwd's parents, fallback."""
    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit).expanduser())
    configured = os.getenv("PASG_AGENT_REPO_ROOT")
    if configured:
        candidates.append(Path(configured).expanduser())
    cwd = Path.cwd().resolve()
    candidates.extend([cwd, *cwd.parents])
    candidates.append(DEFAULT_REPO_FALLBACK)
    for candidate in candidates:
        if (candidate / REPO_MARKER).is_file():
            return candidate.resolve()
    raise SystemExit(
        "could not locate the PASG repo (no agentic/runner.py found); pass --repo"
    )


def load_env(repo: Path) -> Path:
    """Load repo/.env into this process so the imports below see credentials.

    The skill scripts themselves never call ``load_dotenv``; in production the
    worker process already carries the environment. Child processes the agent
    launches still need their own ``set -a; . .env; set +a``.
    """
    env_path = repo / ".env"
    if not env_path.is_file():
        raise SystemExit(f"{env_path} does not exist; the run needs Azure + Graph credentials")
    from dotenv import load_dotenv

    load_dotenv(env_path)
    return env_path


def mirror_sharepoint_root(repo: Path, project: str) -> str | None:
    """The project's SharePoint folder, from its local mirror manifest."""
    manifest = repo / ".agent-data" / "sharepoint-mirror" / project / "manifest.json"
    if not manifest.is_file():
        return None
    try:
        return str(json.loads(manifest.read_text(encoding="utf-8")).get("sharepoint_root") or "") or None
    except (json.JSONDecodeError, OSError):
        return None


def seed_snapshot(workspace: Path, project: str, sharepoint_root: str) -> None:
    """Write a minimal snapshot so snapshot-dependent tooling has a root to read."""
    from agentic.snapshots import build_local_snapshot

    build_local_snapshot(
        project_slug=project,
        sharepoint_root=sharepoint_root,
        mirror_files_dir=workspace / "dataroom",
    ).write_manifest(workspace / "source" / "source_snapshot.json")


def sync_snapshot(repo: Path, workspace: Path, sharepoint_root: str) -> None:
    """Re-inventory the snapshot from SharePoint so records carry real drive item ids.

    A seeded snapshot has synthetic ``local:<path>`` ids, which are not citable
    on the same terms as a real run's. This is the fidelity upgrade; it costs a
    full Graph listing of the project folder.
    """
    script = repo / ".agents/skills/pasg-v2-core/scripts/hydrate_source_snapshot.py"
    subprocess.run(
        [
            str(workspace / ".venv" / "bin" / "python"),
            str(script),
            "source/source_snapshot.json",
            "--workspace",
            ".",
            "--mode",
            "usual-project",
            "--dry-run",
            "--sync-source",
            "--sharepoint-root",
            sharepoint_root,
        ],
        cwd=workspace,
        env=os.environ.copy(),
        check=True,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prompt", required=True, help="the analyst message for this turn")
    parser.add_argument("--project", required=True, help="project slug, e.g. 2026-04-fulcrum")
    parser.add_argument("--run-id", default="cc-emulation", help="run id; reuse it for follow-up turns")
    parser.add_argument("--repo", default=None, help="PASG repo root; auto-detected by default")
    parser.add_argument(
        "--sharepoint-root",
        default=None,
        help="project folder; defaults to the local mirror manifest's sharepoint_root",
    )
    parser.add_argument(
        "--sync-source",
        action="store_true",
        help="re-inventory the snapshot from SharePoint for real drive item ids (slower)",
    )
    args = parser.parse_args(argv)

    repo = resolve_repo(args.repo)
    env_path = load_env(repo)
    sys.path.insert(0, str(repo))

    from agentic.runner import _agentic_turn_instructions
    from agentic.workspaces import WorkspaceProvisioner

    sharepoint_root = args.sharepoint_root or mirror_sharepoint_root(repo, args.project)
    if not sharepoint_root:
        raise SystemExit(
            f"no mirror manifest for {args.project}; pass --sharepoint-root "
            '"PASG Library/02 - Projects/<project folder>"'
        )

    paths = WorkspaceProvisioner(repo_root=repo).prepare(
        project_slug=args.project, run_id=args.run_id
    )
    workspace = paths.root
    snapshot = workspace / "source" / "source_snapshot.json"
    seeded = not snapshot.is_file()
    if seeded:
        seed_snapshot(workspace, args.project, sharepoint_root)
    if args.sync_source:
        sync_snapshot(repo, workspace, sharepoint_root)

    snapshot_doc = json.loads(snapshot.read_text(encoding="utf-8"))
    synthetic = sum(
        1 for f in snapshot_doc.get("files", []) if str(f.get("drive_item_id", "")).startswith("local:")
    )

    print("=" * 78)
    print("WORKSPACE READY")
    print("=" * 78)
    print(f"repo:            {repo}")
    print(f"workspace:       {workspace}")
    print(f"sharepoint_root: {sharepoint_root}")
    print(f"snapshot:        {snapshot_doc.get('file_count')} files, {synthetic} synthetic ids")
    print(f"dataroom:        {sum(1 for _ in workspace.joinpath('dataroom').rglob('*') if _.is_file())} files")
    print()
    print("Run every command from the workspace, with the environment exported:")
    print(f"  cd {workspace}")
    print(f"  set -a; . {env_path}; set +a")
    print()
    print("=" * 78)
    print("TURN PREAMBLE (production text — this is the router; obey it)")
    print("=" * 78)
    print(_agentic_turn_instructions(args.prompt, workspace))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
