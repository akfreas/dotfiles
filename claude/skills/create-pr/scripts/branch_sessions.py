#!/usr/bin/env python3
"""Find the Claude Code sessions, worktrees and host behind a git branch.

Scans every transcript under ~/.claude/projects (all project directories, so
worktree sessions are found too) for the branch name, keeping only transcripts
modified on or after the moment the branch was minted, and prints a provenance
block for a PR description.

Usage:
    branch_sessions.py [--repo PATH] [--branch NAME] [--base origin/main]
                       [--since ISO8601] [--projects-dir DIR] [--format md|json]

Exit code is 0 even when nothing is found; the markdown then says so.
"""
import argparse
import collections
import datetime as dt
import json
import os
import re
import shutil
import socket
import subprocess
import sys


def run(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return p.stdout if p.returncode == 0 else ""


def parse_ts(s):
    if not s:
        return None
    s = s.strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        d = dt.datetime.fromisoformat(s)
    except ValueError:
        return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=dt.timezone.utc)
    return d


def local(d):
    return d.astimezone() if d else None


def fmt(d, with_date=True):
    d = local(d)
    if not d:
        return "?"
    return d.strftime("%Y-%m-%d %H:%M" if with_date else "%H:%M")


def minted_time(repo, branch, base, override):
    """Earliest evidence of the branch: reflog creation entry or oldest commit date."""
    if override:
        d = parse_ts(override)
        if not d:
            sys.exit(f"--since is not ISO 8601: {override}")
        return d, "given with --since"
    candidates = []
    reflog = run(["git", "reflog", "show", "--date=iso-strict", f"refs/heads/{branch}"], repo)
    for line in reflog.splitlines():
        m = re.search(r"@\{([^}]+)\}: (.*)", line)
        if m and (d := parse_ts(m.group(1))):
            candidates.append((d, "reflog: " + m.group(2).strip()))
    log = run(["git", "log", "--reverse", "--format=%aI%x09%cI", f"{base}..{branch}"], repo)
    for line in log.splitlines():
        for ts in line.split("\t"):
            if d := parse_ts(ts):
                candidates.append((d, "oldest commit date on the branch"))
    if not candidates:
        return None, "no reflog or commits found; searched all transcripts"
    return min(candidates, key=lambda c: c[0])


def transcript_files(projects_dir, branch, since):
    """Transcripts that mention the branch and were modified on or after `since`."""
    if shutil.which("rg"):
        out = run(["rg", "-l", "--fixed-strings", "--glob", "*.jsonl", "--", branch, projects_dir])
    else:
        out = run(["grep", "-rlF", "--include=*.jsonl", "--", branch, projects_dir])
    files = []
    for f in out.splitlines():
        f = f.strip()
        if not f:
            continue
        if since and dt.datetime.fromtimestamp(os.path.getmtime(f), dt.timezone.utc) < since:
            continue
        files.append(f)
    return sorted(files)


def session_key(path, projects_dir):
    """(project_dir, session_id, agent_id) for a transcript path."""
    rel = os.path.relpath(path, projects_dir).split(os.sep)
    project = rel[0]
    name = os.path.basename(path)[:-len(".jsonl")]
    if name.startswith("agent-"):
        parent = rel[1] if len(rel) >= 4 and rel[2] == "subagents" else None
        return project, parent, name[len("agent-"):]
    return project, name, None


def scan(path, branch):
    """One pass over a transcript collecting the metadata the PR block needs."""
    info = {
        "mentions": 0, "cwds": collections.Counter(), "branch_cwds": collections.Counter(), "branches": collections.Counter(),
        "first_ts": None, "last_ts": None, "title": None, "first_prompt": None,
        "entrypoint": None, "bridge": None, "version": None, "session_id_field": None,
    }
    needed = ('"type":"user"', '"type":"assistant"', '"type":"ai-title"',
              '"type":"custom-title"', '"type":"bridge-session"')
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if branch in line:
                info["mentions"] += 1
            if not any(n in line for n in needed):
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            t = d.get("type")
            if t == "ai-title":
                info["title"] = info["title"] or d.get("aiTitle")
            elif t == "custom-title":
                info["title"] = d.get("customTitle") or info["title"]
            elif t == "bridge-session":
                info["bridge"] = d.get("bridgeSessionId") or info["bridge"]
            elif t in ("user", "assistant"):
                info["session_id_field"] = info["session_id_field"] or d.get("sessionId")
                ts = parse_ts(d.get("timestamp"))
                if ts:
                    info["first_ts"] = min(info["first_ts"] or ts, ts)
                    info["last_ts"] = max(info["last_ts"] or ts, ts)
                if d.get("cwd"):
                    info["cwds"][d["cwd"]] += 1
                    if d.get("gitBranch") == branch:
                        info["branch_cwds"][d["cwd"]] += 1
                if d.get("gitBranch"):
                    info["branches"][d["gitBranch"]] += 1
                info["entrypoint"] = info["entrypoint"] or d.get("entrypoint")
                info["version"] = info["version"] or d.get("version")
                if t == "user" and info["first_prompt"] is None:
                    info["first_prompt"] = prompt_text(d.get("message", {}).get("content"))
    return info


def prompt_text(content):
    """The user's own words from a user entry, or the slash command they ran; None for noise."""
    if isinstance(content, list):
        content = " ".join(b.get("text", "") for b in content if b.get("type") == "text")
    if not isinstance(content, str) or not content.strip():
        return None
    text = content.strip()
    if not text.startswith("<"):
        return " ".join(text.split())
    m = re.search(r"<command-name>(/[^<]+)</command-name>", text)
    if m and m.group(1).strip() not in ("/clear", "/exit", "/resume"):
        args = re.search(r"<command-args>([^<]*)</command-args>", text)
        return " ".join((m.group(1).strip() + " " + (args.group(1) if args else "")).split())
    return None


def git_toplevel(path):
    if not os.path.isdir(path):
        return None
    return run(["git", "rev-parse", "--show-toplevel"], path).strip() or None


def collect(repo, branch, base, since_override, projects_dir, exclude_session=None):
    since, since_reason = minted_time(repo, branch, base, since_override)
    files = [f for f in transcript_files(projects_dir, branch, since)
             if not exclude_session or exclude_session not in f]
    sessions = {}
    for f in files:
        project, sid, agent = session_key(f, projects_dir)
        info = scan(f, branch)
        if sid is None:
            sid = info["session_id_field"] or f"agent-{agent}"
        s = sessions.setdefault(sid, {
            "session_id": sid, "project_dir": os.path.join(projects_dir, project),
            "transcript": None, "subagents": [], "mentions": 0,
            "cwds": collections.Counter(), "branch_cwds": collections.Counter(), "branches": collections.Counter(),
            "first_ts": None, "last_ts": None, "title": None, "first_prompt": None,
            "entrypoint": None, "bridge": None, "version": None,
        })
        if agent:
            s["subagents"].append(f)
        else:
            s["transcript"] = f
            s["title"] = info["title"] or s["title"]
            s["first_prompt"] = info["first_prompt"] or s["first_prompt"]
            s["bridge"] = info["bridge"] or s["bridge"]
            s["entrypoint"] = info["entrypoint"] or s["entrypoint"]
            s["version"] = info["version"] or s["version"]
        s["mentions"] += info["mentions"]
        s["cwds"].update(info["cwds"])
        s["branch_cwds"].update(info["branch_cwds"])
        s["branches"].update(info["branches"])
        for k in ("first_ts", "last_ts"):
            vals = [v for v in (s[k], info[k]) if v]
            if vals:
                s[k] = min(vals) if k == "first_ts" else max(vals)
    empty = [sid for sid, s in sessions.items() if not s["title"] and not s["first_prompt"] and not s["subagents"]]
    for sid in empty:
        del sessions[sid]
    for s in sessions.values():
        if s["transcript"] is None:  # subagent found but parent transcript never mentions the branch
            parent = os.path.join(s["project_dir"], s["session_id"] + ".jsonl")
            if os.path.exists(parent):
                s["transcript"] = parent
                info = scan(parent, branch)
                for k in ("title", "first_prompt", "bridge", "entrypoint", "version"):
                    s[k] = s[k] or info[k]
                s["cwds"].update(info["cwds"])
                s["branch_cwds"].update(info["branch_cwds"])
                s["branches"].update(info["branches"])
        s["checked_out"] = s["branches"].get(branch, 0) > 0
        s["primary_cwd"] = s["cwds"].most_common(1)[0][0] if s["cwds"] else None
        s["expected_project_dir"] = os.path.join(projects_dir, re.sub(r"[/.]", "-", s["primary_cwd"])) if s["primary_cwd"] else None

    # Worktrees: every cwd of a session that had the branch checked out, normalised to its git toplevel.
    worktrees = collections.OrderedDict()
    live = {}
    for block in run(["git", "worktree", "list", "--porcelain"], repo).strip().split("\n\n"):
        wt = {}
        for line in block.splitlines():
            k, _, v = line.partition(" ")
            wt[k] = v
        if wt.get("worktree"):
            live[wt["worktree"]] = wt.get("branch", "").replace("refs/heads/", "")
    pairs = []
    for s in sessions.values():
        if s["checked_out"]:
            for cwd in s["branch_cwds"]:
                top = git_toplevel(cwd)
                pairs.append((top is None, len(top or cwd), top or cwd, top is not None, s))
    for _, _, key, exists, s in sorted(pairs, key=lambda p: (p[0], p[1], p[4]["first_ts"] or dt.datetime.max.replace(tzinfo=dt.timezone.utc))):
        if not exists:  # a removed worktree: fold the path into the shortest known root that contains it
            for root in worktrees:
                if key == root or key.startswith(root.rstrip("/") + "/"):
                    key = root
                    break
        w = worktrees.setdefault(key, {"path": key, "exists": exists, "sessions": [], "first_ts": None, "last_ts": None})
        if s["session_id"] not in w["sessions"]:
            w["sessions"].append(s["session_id"])
        w["first_ts"] = min([x for x in (w["first_ts"], s["first_ts"]) if x], default=None)
        w["last_ts"] = max([x for x in (w["last_ts"], s["last_ts"]) if x], default=None)
    for s in sessions.values():
        roots = []
        for cwd, _ in s["cwds"].most_common():
            if os.path.isdir(cwd):
                top = git_toplevel(cwd)
                if not top:  # an existing directory that is not a repository: shell noise, not a worktree
                    continue
            else:
                top = cwd  # removed worktree; collapsed onto its shortest known ancestor below
            if top not in roots:
                roots.append(top)
        folded = []
        for r in sorted(roots, key=len):
            for k in list(worktrees) + folded:
                if r == k or r.startswith(k.rstrip("/") + "/"):
                    r = k
                    break
            if r not in folded:
                folded.append(r)
        primary = next((r for r in folded if s["primary_cwd"] and (s["primary_cwd"] == r or s["primary_cwd"].startswith(r.rstrip("/") + "/"))), folded[0] if folded else s["primary_cwd"])
        mine = [w for w in worktrees if s["session_id"] in worktrees[w]["sessions"]]
        s["primary_root"] = primary
        s["other_roots"] = [r for r in folded if r not in (mine or [primary])]
    for path, b in live.items():
        if b == branch and path not in worktrees:
            worktrees[path] = {"path": path, "exists": True, "sessions": [], "first_ts": None, "last_ts": None}
    for w in worktrees.values():
        w["currently_checked_out_here"] = live.get(w["path"]) == branch

    ordered = sorted(sessions.values(), key=lambda s: (not s["checked_out"], s["first_ts"] or dt.datetime.max.replace(tzinfo=dt.timezone.utc)))
    return {
        "host": socket.gethostname(),
        "branch": branch,
        "base": base,
        "since": since.isoformat() if since else None,
        "since_reason": since_reason,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "transcripts_scanned": len(files),
        "empty_sessions_skipped": len(empty),
        "sessions": ordered,
        "worktrees": list(worktrees.values()),
    }


def to_json(result):
    def conv(o):
        if isinstance(o, dt.datetime):
            return o.isoformat()
        if isinstance(o, collections.Counter):
            return dict(o)
        raise TypeError(type(o))
    return json.dumps(result, default=conv, indent=2)


def session_line(s):
    title = s["title"] or s["first_prompt"] or "(untitled)"
    if len(title) > 110:
        title = title[:109] + "…"
    when = fmt(s["first_ts"])
    if s["last_ts"] and s["first_ts"] and s["last_ts"].date() == s["first_ts"].date():
        when += f" to {fmt(s['last_ts'], with_date=False)}"
    elif s["last_ts"]:
        when += f" to {fmt(s['last_ts'])}"
    flags = []
    if s["bridge"]:
        flags.append("remote control")
    if s["entrypoint"] and s["entrypoint"] != "cli":
        flags.append(s["entrypoint"])
    if s["subagents"]:
        flags.append(f"{len(s['subagents'])} subagent{'s' if len(s['subagents']) != 1 else ''}")
    for other in s.get("other_roots", []):
        flags.append(f"also worked in `{other}`")
    if s["transcript"] and s["expected_project_dir"] and os.path.dirname(s["transcript"]) != s["expected_project_dir"]:
        flags.append(f"transcript under `{os.path.basename(os.path.dirname(s['transcript']))}`")
    flag_txt = f" ({'; '.join(flags)})" if flags else ""
    return f"- `{s['session_id']}` {when}{flag_txt} {title}"


def to_markdown(result):
    out = ["<details>", "<summary>Claude Code sessions</summary>", ""]
    head = f"Host `{result['host']}`."
    if result["since"]:
        head += f" Branch created {fmt(parse_ts(result['since']))} ({result['since_reason']}); transcripts searched from then until {fmt(parse_ts(result['generated_at']))}."
    else:
        head += f" Branch creation time unknown; all transcripts searched, up to {fmt(parse_ts(result['generated_at']))}."
    head += " Resume a session with `cd <worktree> && claude --resume <id>`; its transcript is `~/.claude/projects/<worktree path with / and . replaced by ->/<id>.jsonl` on the host unless noted."
    out += [head, ""]
    if not result["sessions"]:
        out += ["No transcripts on this host mention the branch.", "", "</details>"]
        return "\n".join(out)
    by_wt = collections.OrderedDict((w["path"], w) for w in result["worktrees"])
    placed = set()
    for path, w in by_wt.items():
        members = [s for s in result["sessions"] if s["session_id"] in w["sessions"]]
        if not members and not w["currently_checked_out_here"]:
            continue
        bits = []
        if not w["exists"]:
            bits.append("worktree removed")
        elif w["currently_checked_out_here"]:
            bits.append("branch checked out here now")
        out.append(f"`{path}`" + (f" ({', '.join(bits)})" if bits else ""))
        for s in members:
            out.append(session_line(s))
            placed.add(s["session_id"])
        out.append("")
    rest = [s for s in result["sessions"] if s["session_id"] not in placed]
    if rest:
        out.append("Mention the branch without having it checked out")
        for s in rest:
            out.append(session_line(s) + f", in `{s['primary_root'] or '?'}`")
        out.append("")
    out.append("</details>")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=os.getcwd())
    ap.add_argument("--branch", default=None, help="defaults to the checked-out branch of --repo")
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--since", default=None, help="ISO 8601 override for the branch creation time")
    ap.add_argument("--projects-dir", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--format", choices=("md", "json"), default="md")
    ap.add_argument("--exclude-session", default=None, help="a session id to leave out of the results")
    a = ap.parse_args()
    repo = os.path.abspath(a.repo)
    branch = a.branch or run(["git", "rev-parse", "--abbrev-ref", "HEAD"], repo).strip()
    if not branch or branch == "HEAD":
        sys.exit("could not determine the branch; pass --branch")
    result = collect(repo, branch, a.base, a.since, a.projects_dir, a.exclude_session)
    print(to_json(result) if a.format == "json" else to_markdown(result))


if __name__ == "__main__":
    main()
