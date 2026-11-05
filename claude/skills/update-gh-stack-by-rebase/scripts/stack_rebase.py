#!/usr/bin/env python3
"""Rebase a GitHub-native PR stack onto its target branch, layer by layer.

GitHub is the source of truth: the stack is discovered by walking open PRs'
base/head branches, and every layer's own commits are pinned to the head SHAs
the PRs had when the plan was made. Each layer is then replayed with
`git rebase --onto <new parent> <cut> <branch>`, so commits left behind by
squash-merged lower PRs are never replayed.

Subcommands (run from inside a clean worktree of the repo):
  plan   --out plan.json [PR-or-branch]   discover the stack and compute cuts (read-only apart from git fetch)
  apply  --plan plan.json                 rebase each layer, auto-resolving only clean conflicts; resumable
  push   --plan plan.json [--dry-run]     atomic force-with-lease push of rebased layers
  verify --plan plan.json                 check bases, ancestry, commit counts and mergeability on GitHub
"""
import argparse
import difflib
import json
import os
import re
import subprocess
import sys
import time

PR_FIELDS = "number,title,headRefName,baseRefName,headRefOid,state,isDraft,mergeable,mergeStateStatus,commits"


def run(*cmd, check=True):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if check and p.returncode != 0:
        sys.exit(f"✗ {' '.join(cmd)}\n{p.stderr.strip()}")
    return p.stdout.strip()


def succeeds(*cmd):
    return subprocess.run(cmd, capture_output=True).returncode == 0


def git(*args, check=True):
    return run("git", *args, check=check)


def gh_json(*args):
    return json.loads(run("gh", *args))


def is_ancestor(a, b):
    return succeeds("git", "merge-base", "--is-ancestor", a, b)


def count(rng):
    return int(git("rev-list", "--count", rng))


def rev(ref):
    return git("rev-parse", "-q", "--verify", ref + "^{commit}", check=False) or None


def pr(ref):
    d = gh_json("pr", "view", str(ref), "--json", PR_FIELDS)
    d["commitCount"] = len(d.pop("commits"))
    return d


def open_pr_for_head(branch):
    found = gh_json("pr", "list", "--head", branch, "--state", "open", "--json", "number")
    return found[0]["number"] if found else None


def open_children(branch):
    return [x["number"] for x in gh_json("pr", "list", "--base", branch, "--state", "open", "--json", "number")]


def worktrees_by_branch():
    out, path = {}, None
    for line in git("worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree "):]
        elif line.startswith("branch refs/heads/"):
            out[line[len("branch refs/heads/"):]] = path
    return out


def subjects(rng):
    return set(git("log", "--format=%s", rng).splitlines()) if rng else set()


def discover(start_ref):
    start = pr(start_ref)
    if start["state"] != "OPEN":
        sys.exit(f"✗ PR #{start['number']} is {start['state']}; start from an open PR in the stack")
    chain = [start]
    while (n := open_pr_for_head(chain[0]["baseRefName"])):
        chain.insert(0, pr(n))
    while True:
        kids = open_children(chain[-1]["headRefName"])
        if not kids:
            break
        if len(kids) > 1:
            sys.exit(f"✗ {chain[-1]['headRefName']} has several open child PRs {kids}; the stack forks. Rebase each chain separately.")
        chain.append(pr(kids[0]))
    return chain


def bottom_cut(trunk, bottom_oid, merged):
    """Closest point to the bottom layer that is already represented on the trunk."""
    candidates = [("merge-base", git("merge-base", f"origin/{trunk}", bottom_oid))]
    for m in merged:
        oid = m["headRefOid"]
        if rev(oid) and is_ancestor(oid, bottom_oid):
            candidates.append((f"head of merged PR #{m['number']}", oid))
    how, cut = min(candidates, key=lambda c: count(f"{c[1]}..{bottom_oid}"))
    return cut, how


def broken_link_cut(parent_oid, child_oid, exclude):
    """The child does not contain its parent's head: keep only its own trailing commits."""
    mb = git("merge-base", parent_oid, child_oid)
    commits = git("rev-list", "--reverse", f"{mb}..{child_oid}").split()
    upstream = {l[2:] for l in git("cherry", parent_oid, child_oid).splitlines() if l.startswith("- ")}
    exclude = exclude | subjects(f"{mb}..{parent_oid}")
    own = []
    for c in reversed(commits):
        if c in upstream or git("log", "-1", "--format=%s", c) in exclude:
            break
        own.insert(0, c)
    if not own:
        return None
    return git("rev-parse", own[0] + "^")


def cmd_plan(a):
    git("fetch", "-q", "origin")
    chain = discover(a.ref or git("branch", "--show-current"))
    trunk = chain[0]["baseRefName"]
    notes = []

    # Bottom PR still based on a branch whose PR already merged: GitHub didn't retarget it.
    stale = [m for m in gh_json("pr", "list", "--head", trunk, "--state", "merged", "--json", "number,baseRefName,headRefOid")
             if m["headRefOid"] == rev(f"origin/{trunk}")]
    if stale:
        notes.append(f"Bottom PR #{chain[0]['number']} is still based on {trunk}, whose PR #{stale[0]['number']} merged into "
                     f"{stale[0]['baseRefName']}. Its base must be fixed with unstack + link --base (see SKILL.md).")
        trunk = stale[0]["baseRefName"]

    merged = gh_json("pr", "list", "--state", "merged", "--base", trunk, "--limit", "40",
                     "--json", "number,headRefOid,commits")
    merged_subjects = {c["messageHeadline"] for m in merged for c in m["commits"]}
    wt = worktrees_by_branch()
    here = os.path.realpath(git("rev-parse", "--show-toplevel"))

    layers = []
    for i, p in enumerate(chain):
        head, old = p["headRefName"], p["headRefOid"]
        layer = {"number": p["number"], "title": p["title"], "head": head, "base": p["baseRefName"],
                 "old_oid": old, "gh_commit_count": p["commitCount"], "flags": []}
        if i == 0:
            layer["cut"], how = bottom_cut(trunk, old, merged)
            layer["link"] = f"bottom (cut at {how})"
        elif is_ancestor(chain[i - 1]["headRefOid"], old):
            layer["cut"], layer["link"] = chain[i - 1]["headRefOid"], "ok"
        else:
            layer["cut"] = broken_link_cut(chain[i - 1]["headRefOid"], old, merged_subjects)
            layer["link"] = "BROKEN"
            layer["flags"].append("does not contain its parent's head; own commits guessed, confirm before apply")
            if not layer["cut"]:
                layer["flags"].append("could not find any own commits; pass --cut")
        if a.cut and str(p["number"]) in a.cut:
            layer["cut"] = git("rev-parse", a.cut[str(p["number"])])
            layer["flags"].append("cut overridden on the command line")
        if layer["cut"]:
            layer["own_count"] = count(f"{layer['cut']}..{old}")
            layer["own_subjects"] = git("log", "--reverse", "--format=%h %s", f"{layer['cut']}..{old}").splitlines()
            if git("rev-list", "--merges", f"{layer['cut']}..{old}"):
                layer["flags"].append("contains merge commits; rebase will linearize them")
        holder = wt.get(head)
        if holder and os.path.realpath(holder) != here:
            layer["flags"].append(f"checked out in worktree {holder}; detach it before apply")
        layers.append(layer)

    plan = {"trunk": trunk, "trunk_oid": rev(f"origin/{trunk}"), "notes": notes, "layers": layers}
    with open(a.out, "w") as f:
        json.dump(plan, f, indent=2)

    print(f"Trunk: {trunk} @ {plan['trunk_oid'][:9]}   ({len(layers)} open layers, bottom → top)")
    for n in notes:
        print(f"! {n}")
    for l in layers:
        own = l.get("own_count", "?")
        mark = "!" if l["flags"] else " "
        print(f"{mark} #{l['number']:<5} own={own:<3} github={l['gh_commit_count']:<3} {l['link']:<32} {l['head']}")
        for fl in l["flags"]:
            print(f"      - {fl}")
        if l["link"] == "BROKEN" and l.get("own_subjects"):
            for s in l["own_subjects"]:
                print(f"        {s}")
    print(f"\nPlan written to {a.out}")


def load(a):
    with open(a.plan) as f:
        return json.load(f)


def new_base(plan, i):
    return f"origin/{plan['trunk']}" if i == 0 else plan["layers"][i - 1]["head"]


def load_state(a):
    try:
        with open(a.plan + ".state.json") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def record(a, plan, i):
    st, l = load_state(a), plan["layers"][i]
    cur = rev(f"refs/heads/{l['head']}")
    st[l["head"]] = {"oid": cur, "count": count(f"{rev(new_base(plan, i))}..{cur}")}
    with open(a.plan + ".state.json", "w") as f:
        json.dump(st, f, indent=2)
    return st[l["head"]]["count"]


def layer_done(a, plan, i):
    l, st = plan["layers"][i], load_state(a)
    cur = rev(f"refs/heads/{l['head']}")
    return bool(cur) and st.get(l["head"], {}).get("oid") == cur and is_ancestor(rev(new_base(plan, i)), cur)


REBASE = ["git", "-c", "rerere.enabled=true", "-c", "merge.conflictStyle=diff3", "rebase"]
IMPORT = re.compile(r"^\s*(import|@testable import|#import|#include|using|require|from\s+\S+\s+import)\b")
DECL = re.compile(r"\b(?:func|def|class|struct|enum|protocol|interface|case|let|var|const|function|type|fn|typealias|associatedtype)\s+`?([A-Za-z_][A-Za-z0-9_]*)")


def meaningful(lines):
    return [x.strip() for x in lines if x.strip()]


TOKEN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*|\s+|.")
WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*|\s+")


def word_only(tokens):
    return all(WORD.fullmatch(t) for t in tokens) and any(not t.isspace() for t in tokens)


COMMENT = re.compile(r"^\s*(//|/\*|\*|#|<!--|--)")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
PROSE_SUFFIXES = (".md", ".mdx", ".txt", ".rst")


def is_prose(line, prose_file):
    return prose_file or bool(COMMENT.match(line))


def rename_map(base, target, prose_file=False):
    """The word substitutions that turn base into target, as {old: (new, prose)}, or None if the target did anything else.

    Lines pair up one to one, and within a line only runs of words change;
    punctuation, lines and structure stay as they were. On a code line only a
    single identifier may be renamed to another single identifier. A comment or
    prose line may also reword a phrase, and such a rewording is marked prose so
    it is never carried onto code. Every occurrence of a renamed word in the
    base must be one the target changed: `f(x: x)` → `g(y: x)` renames the label
    only, which a word substitution cannot express, so it is refused.
    """
    b, t = meaningful(base), meaningful(target)
    if len(b) != len(t):
        return None
    renames, hits = {}, {}
    for bl, tl in zip(b, t):
        prose = is_prose(bl, prose_file)
        if prose != is_prose(tl, prose_file):
            return None
        bt, tt = TOKEN.findall(bl), TOKEN.findall(tl)
        for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, bt, tt, autojunk=False).get_opcodes():
            if op == "equal":
                continue
            old, new = "".join(bt[i1:i2]).strip(), "".join(tt[j1:j2]).strip()
            if op != "replace" or not word_only(bt[i1:i2]) or not word_only(tt[j1:j2]) or not old:
                return None
            identifier_rename = bool(IDENT.fullmatch(old) and IDENT.fullmatch(new))
            if not prose and not identifier_rename:
                return None
            entry = (new, not identifier_rename)
            if renames.setdefault(old, entry)[0] != new:
                return None
            hits[old] = hits.get(old, 0) + 1
    for old in renames:
        rx = re.compile(rf"(?<![A-Za-z0-9_]){re.escape(old)}(?![A-Za-z0-9_])")
        if sum(len(rx.findall(l)) for l in b) != hits[old]:
            return None
    return renames or None


def apply_renames(base, target, incoming, prose_file=False):
    """Carry the target's renames onto the incoming lines, if the incoming side left every renamed word alone.

    Identifier renames apply to code and prose lines; prose rewordings only to
    prose lines.
    """
    renames = rename_map(base, target, prose_file)
    if not renames:
        return None
    pattern = {old: re.compile(rf"(?<![A-Za-z0-9_]){re.escape(old)}(?![A-Za-z0-9_])") for old in renames}

    def applies(old, line):
        return not renames[old][1] or is_prose(line, prose_file)

    for old, rx in pattern.items():
        seen = lambda lines: sum(len(rx.findall(l)) for l in lines if applies(old, l))
        if seen(incoming) < seen(base):
            return None
    out = []
    for line in incoming:
        for old, rx in pattern.items():
            if applies(old, line):
                line = rx.sub(lambda _: renames[old][0], line)
        out.append(line)
    return out


def classify(target, base, incoming, prose_file=False):
    """Resolve one diff3 hunk if it is clean; return (kind, merged lines or None)."""
    if meaningful(target) == meaningful(incoming):
        return "identical on both sides", target
    if meaningful(target) == meaningful(base):
        return "only the incoming commit changed it", incoming
    if meaningful(incoming) == meaningful(base):
        return "only the target changed it", target
    if meaningful(base) and (merged := apply_renames(base, target, incoming, prose_file)) is not None:
        names = ", ".join(f"{o} → {n}" for o, (n, _) in rename_map(base, target, prose_file).items())
        return f"rename on the target carried onto the incoming lines ({names})", merged
    if meaningful(base):
        return f"overlapping: both sides changed the same {len(meaningful(base))} line(s)", None
    clash = {m for l in target for m in DECL.findall(l)} & {m for l in incoming for m in DECL.findall(l)}
    if clash:
        return f"overlapping: both sides add {', '.join(sorted(clash))}", None
    have = {l.strip() for l in target}
    return "additive: both sides inserted lines", target + [l for l in incoming if not (IMPORT.match(l) and l.strip() in have)]


def resolve_text(text, prose_file=False):
    """Return (resolved text, [hunk kinds]) or (None, reason)."""
    lines, out, kinds, i = text.splitlines(keepends=True), [], [], 0
    while i < len(lines):
        if not lines[i].startswith("<<<<<<< "):
            out.append(lines[i])
            i += 1
            continue
        sides, state, i = {"target": [], "base": None, "incoming": None}, "target", i + 1
        while i < len(lines) and not (state == "incoming" and lines[i].startswith(">>>>>>> ")):
            l = lines[i]
            if l.startswith("<<<<<<< "):
                return None, "nested conflict markers"
            if state == "target" and l.startswith("||||||| "):
                state, sides["base"] = "base", []
            elif state in ("target", "base") and l.rstrip("\r\n") == "=======":
                state, sides["incoming"] = "incoming", []
            else:
                sides[state].append(l)
            i += 1
        if i >= len(lines) or sides["base"] is None:
            return None, "conflict markers without a base section"
        kind, merged = classify(sides["target"], sides["base"], sides["incoming"], prose_file)
        if merged is None:
            hunk = "".join(["  target:\n"] + ["    " + l for l in sides["target"][:15]] +
                           ["  base:\n"] + ["    " + l for l in sides["base"][:15]] +
                           ["  incoming:\n"] + ["    " + l for l in sides["incoming"][:15]])
            return None, f"{kind}\n{hunk}"
        out += merged
        kinds.append(kind)
        i += 1
    return "".join(out), kinds


def auto_resolve(layer, log):
    """Resolve every conflicted file of the current rebase step, or none of them."""
    commit = (git("log", "-1", "--format=%h %s", "REBASE_HEAD", check=False)
              or ((sha := stopped_pick()) and git("log", "-1", "--format=%h %s", sha, check=False)) or "?")
    resolved = {}
    for line in git("status", "--porcelain=v1", "--untracked-files=no").splitlines():
        code, path = line[:2], line[3:]
        if code not in ("DD", "AU", "UD", "UA", "DU", "AA", "UU"):
            continue
        where = f"#{layer['number']} {commit} — {path}"
        if code != "UU":
            return f"{where}: {code} conflict (delete, rename or both added the file), not a line-level conflict"
        try:
            text = open(path, encoding="utf-8").read()
        except (UnicodeDecodeError, IsADirectoryError):
            return f"{where}: binary or non-text file"
        if "<<<<<<< " not in text:
            resolved[path] = (text, ["recorded resolution replayed by rerere"])
            continue
        merged, kinds = resolve_text(text, path.lower().endswith(PROSE_SUFFIXES))
        if merged is None:
            return f"{where}: {kinds}"
        resolved[path] = (merged, kinds)
    for path, (text, kinds) in resolved.items():
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        git("add", "--", path)
        for k in kinds:
            entry = f"#{layer['number']} {commit} — {path}: {k}"
            print(f"  ↺ auto-resolved {entry}")
            log.write(entry + "\n")
    return None


def rebasing_branch():
    for d in ("rebase-merge", "rebase-apply"):
        path = git("rev-parse", "--git-path", d)
        if os.path.isdir(path):
            head = os.path.join(path, "head-name")
            return open(head).read().strip().removeprefix("refs/heads/") if os.path.exists(head) else "?"
    return None


def stopped_pick():
    """The commit the rebase stopped on: the last pick in its done list."""
    done = git("rev-parse", "--git-path", "rebase-merge/done")
    if not os.path.exists(done):
        return None
    picks = [l.split()[1] for l in open(done) if l.split()[:1] == ["pick"]]
    return picks[-1] if picks else None


def drive(cmd, layer, log):
    """Run a rebase step and keep resolving clean conflicts until it finishes; exit 3 on an unclean one."""
    env = dict(os.environ, GIT_EDITOR="true")
    p = subprocess.run(cmd, capture_output=True, text=True, env=env)
    while p.returncode != 0:
        if not rebasing_branch():
            sys.exit(f"✗ git rebase failed for #{layer['number']}:\n{(p.stdout + p.stderr).strip()}")
        if not git("diff", "--name-only", "--diff-filter=U"):
            if "nothing to commit" in p.stdout + p.stderr or "No changes" in p.stdout + p.stderr:
                p = subprocess.run(REBASE[:-1] + ["rebase", "--skip"], capture_output=True, text=True, env=env)
                continue
            if "you have staged changes" in p.stdout + p.stderr and (sha := stopped_pick()):
                # The stopped pick's message file is gone, so --continue no longer
                # knows the staged resolution is that pick. Commit it as the pick.
                git("commit", "-q", "--no-verify", "-C", sha)
                p = subprocess.run(REBASE + ["--continue"], capture_output=True, text=True, env=env)
                continue
            print(f"✗ git rebase --continue failed for #{layer['number']} with no conflicted files:")
            print(f"  {(p.stdout + p.stderr).strip()}")
            print("The rebase is left in progress in this worktree. Nothing has been pushed.")
            sys.exit(3)
        else:
            why = auto_resolve(layer, log)
            if why:
                log.write(f"STOPPED {why.splitlines()[0]}\n")
                print(f"✗ Stopped: conflict in #{layer['number']} ({layer['head']}) is not clean to resolve automatically.")
                print(f"  {why}")
                print("The rebase is left in progress in this worktree. Nothing has been pushed.")
                sys.exit(3)
        p = subprocess.run(REBASE + ["--continue"], capture_output=True, text=True, env=env)


def cmd_apply(a):
    plan = load(a)
    missing = [l["number"] for l in plan["layers"] if not l.get("cut")]
    if missing:
        sys.exit(f"✗ No cut for PR(s) {missing}; re-plan with --cut.")
    with open(a.plan + ".resolutions.log", "a") as log:
        if (b := rebasing_branch()):
            layer = next((l for l in plan["layers"] if l["head"] == b), None)
            if not layer:
                sys.exit(f"✗ A rebase of {b}, which is not in the plan, is in progress here.")
            print(f"Resuming the rebase of #{layer['number']} ({b})")
            drive(REBASE + ["--continue"], layer, log)
            record(a, plan, plan["layers"].index(layer))
        elif git("status", "--porcelain", "--untracked-files=no"):
            sys.exit("✗ This worktree has uncommitted changes; run apply in a clean temporary worktree.")
        for i, l in enumerate(plan["layers"]):
            b = l["head"]
            if layer_done(a, plan, i):
                print(f"✓ #{l['number']} on {new_base(plan, i)}")
                continue
            if rev(f"refs/heads/{b}") != l["old_oid"]:
                git("checkout", "-q", "--detach")
                git("branch", "-f", b, l["old_oid"])
            drive(REBASE + ["--onto", rev(new_base(plan, i)), l["cut"], b], l, log)
            got = record(a, plan, i)
            warn = "" if got == l["own_count"] else f"  ! now {got} commits, planned {l['own_count']}"
            print(f"✓ #{l['number']} rebased onto {new_base(plan, i)}{warn}")
    print(f"All layers rebased. Auto-resolutions are logged in {a.plan}.resolutions.log.")
    print("Build every layer, one subagent per layer, at most 3 at once, then push.")


def cmd_push(a):
    plan = load(a)
    args = []
    for i, l in enumerate(plan["layers"]):
        if not layer_done(a, plan, i):
            sys.exit(f"✗ #{l['number']} is not rebased (or changed since apply); run apply first.")
        if rev(f"refs/heads/{l['head']}") != l["old_oid"]:
            args += [f"--force-with-lease=refs/heads/{l['head']}:{l['old_oid']}", f"refs/heads/{l['head']}:refs/heads/{l['head']}"]
    if not args:
        print("Nothing to push; every layer already matches GitHub.")
        return
    cmd = ["git", "push", "--atomic", "origin"] + args
    if a.dry_run:
        cmd.insert(2, "--dry-run")
    p = subprocess.run(cmd, capture_output=True, text=True)
    print((p.stdout + p.stderr).strip())
    if p.returncode != 0:
        sys.exit("✗ Push rejected. Nothing was updated (atomic). If a lease failed, someone pushed to that branch: re-plan.")


def cmd_verify(a):
    plan = load(a)
    st = load_state(a)
    git("fetch", "-q", "origin")
    bad = 0
    for i, l in enumerate(plan["layers"]):
        expected_base = plan["trunk"] if i == 0 else plan["layers"][i - 1]["head"]
        for _ in range(12):
            p = pr(l["number"])
            if p["mergeable"] != "UNKNOWN":
                break
            time.sleep(5)
        problems = []
        if p["state"] != "OPEN":
            problems.append(p["state"])
        if p["baseRefName"] != expected_base:
            problems.append(f"base is {p['baseRefName']}, expected {expected_base}")
        if p["headRefOid"] != rev(f"refs/heads/{l['head']}"):
            problems.append("GitHub head differs from the local rebased branch")
        if not is_ancestor(f"origin/{expected_base}", f"origin/{l['head']}"):
            problems.append("does not contain its base's head")
        else:
            own = count(f"origin/{expected_base}..origin/{l['head']}")
            want = st.get(l["head"], {}).get("count", l["own_count"])
            if own != want:
                problems.append(f"{own} commits over its base, expected {want}")
        if p["mergeable"] == "CONFLICTING":
            problems.append("GitHub reports merge conflicts")
        bad += bool(problems)
        status = "✓" if not problems else "✗"
        print(f"{status} #{l['number']:<5} {p['mergeable']:<11} {p['mergeStateStatus']:<9} commits={p['commitCount']:<3} {l['head']}")
        for pb in problems:
            print(f"      - {pb}")
    if bad:
        sys.exit(f"✗ {bad} layer(s) need attention")
    print("Stack is consistent and mergeable.")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("ref", nargs="?", help="any PR number, URL or branch in the stack (default: current branch)")
    p.add_argument("--out", required=True)
    p.add_argument("--cut", action="append", default=[], metavar="PR=SHA",
                   help="override where a layer's own commits start (exclusive)")
    for name in ("apply", "push", "verify"):
        s = sub.add_parser(name)
        s.add_argument("--plan", required=True)
        if name == "push":
            s.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if a.cmd == "plan":
        a.cut = dict(c.split("=", 1) for c in a.cut)
    {"plan": cmd_plan, "apply": cmd_apply, "push": cmd_push, "verify": cmd_verify}[a.cmd](a)


if __name__ == "__main__":
    main()
