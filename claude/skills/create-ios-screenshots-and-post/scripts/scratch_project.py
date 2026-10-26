#!/usr/bin/env python3
"""Build and tear down a throwaway Encamera Xcode project for screenshot tests.

The scratch directory is a symlink mirror of the repo root, so every path that
Xcode resolves against $(SRCROOT) (INFOPLIST_FILE, CODE_SIGN_ENTITLEMENTS in
xcconfigs, ...) lands on the real repo file. An XcodeGen overlay includes the
mirrored project.yml and adds a scratch-only test directory to the UI test
target. The repo's tracked Encamera.xcodeproj is never regenerated, and every
command fails if the repo's git state changed since `setup`.

Usage:
    scratch_project.py setup    --repo PATH --scratch DIR
    scratch_project.py generate --scratch DIR
    scratch_project.py extract  --xcresult PATH --out DIR
    scratch_project.py cleanup  --scratch DIR

Workflow: `setup`, write *.swift tests into <scratch>/temp-screenshot-tests,
`generate`, run `xcodebuild -project <scratch>/Encamera.xcodeproj`, `extract`,
then `cleanup`. `generate` can be re-run after editing the tests.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

PROJECT = "Encamera.xcodeproj"
UI_TEST_TARGET = "EncameraUITests"
TESTS_DIR = "temp-screenshot-tests"
STATE_FILE = ".scratch-state.json"
OVERLAY = "overlay.yml"
# Names the skill creates in the scratch dir; none may shadow a repo entry.
RESERVED = {TESTS_DIR, OVERLAY, STATE_FILE, PROJECT, "DerivedData", "png",
            "run.xcresult", "comment.md", "build.log"}
SKIP_MIRROR = {PROJECT, ".git"}


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if p.returncode != 0:
        die(f"{' '.join(cmd)} failed:\n{p.stdout}{p.stderr}")
    return p.stdout


def repo_fingerprint(repo):
    """git status plus a hash of the tracked diff, so edits to already-dirty files count."""
    status = run(["git", "status", "--porcelain=v1", "--untracked-files=all"], cwd=repo)
    diff = subprocess.run(["git", "diff", "HEAD", "--binary"], cwd=repo,
                          capture_output=True).stdout
    return {"status": status, "diff_sha256": hashlib.sha256(diff).hexdigest()}


def load_state(scratch):
    path = os.path.join(scratch, STATE_FILE)
    if not os.path.isfile(path):
        die(f"{path} not found; run `setup` first")
    with open(path) as f:
        return json.load(f)


def check_repo_unchanged(state):
    now = repo_fingerprint(state["repo"])
    if now != state["fingerprint"]:
        before = set(state["fingerprint"]["status"].splitlines())
        after = set(now["status"].splitlines())
        changed = sorted(after ^ before) or ["(tracked file contents changed)"]
        die("repo git state changed since setup:\n  " + "\n  ".join(changed))


def load_pbxproj(path):
    return json.loads(run(["plutil", "-convert", "json", "-o", "-", path]))["objects"]


def native_targets(objects):
    return {o["name"]: o for o in objects.values() if o.get("isa") == "PBXNativeTarget"}


def settings_by_target(objects):
    """{target: {config: buildSettings}} as written in the project file."""
    out = {}
    for name, target in native_targets(objects).items():
        configs = objects[target["buildConfigurationList"]]["buildConfigurations"]
        out[name] = {objects[c]["name"]: objects[c]["buildSettings"] for c in configs}
    return out


def infoplist_by_target(objects):
    """{target: {config: INFOPLIST_FILE}} for targets that set it."""
    out = {}
    for name, configs in settings_by_target(objects).items():
        values = {config: settings.get("INFOPLIST_FILE") for config, settings in configs.items()}
        if any(values.values()):
            out[name] = values
    return out


def settings_drift(real, gen):
    """Human-readable differences between two settings_by_target() results."""
    drift = []
    for target in sorted(set(real) & set(gen)):
        for config in sorted(set(real[target]) | set(gen[target])):
            a, b = real[target].get(config, {}), gen[target].get(config, {})
            for key in sorted(set(a) | set(b)):
                if a.get(key) != b.get(key):
                    drift.append(f"{target}/{config} {key}: tracked {a.get(key)!r}, scratch {b.get(key)!r}")
    return drift


def plist_resource_count(objects):
    """Info.plist files copied by a Resources phase; the tracked project has none."""
    resource_files = [f for o in objects.values() if o.get("isa") == "PBXResourcesBuildPhase"
                      for f in o.get("files", [])]
    return sum(1 for f in resource_files
               if objects.get(objects[f].get("fileRef"), {}).get("path", "").endswith("Info.plist"))


def target_source_names(objects, target_name):
    target = native_targets(objects)[target_name]
    names = set()
    for phase_id in target["buildPhases"]:
        phase = objects[phase_id]
        if phase.get("isa") != "PBXSourcesBuildPhase":
            continue
        for build_file in phase.get("files", []):
            ref = objects[build_file].get("fileRef")
            if ref:
                names.add(objects[ref].get("path", ""))
    return names


def spec_targets(project_yml):
    """{target: settings style} for the top-level targets in project.yml.

    The style is "structured" when the target's `settings:` starts with
    base/configs/groups, else "flat". It matters for the overlay: XcodeGen
    ignores flat keys once a settings map has a `base:` key, so a `base:`
    overlay on a flat target silently drops all of that target's settings.
    """
    targets, inside, current, in_settings = {}, False, None, False
    with open(project_yml) as f:
        for line in f:
            if re.match(r"^targets:\s*$", line):
                inside = True
                continue
            if re.match(r"^\S", line):
                inside = False
            if not inside:
                continue
            m = re.match(r"^  ([A-Za-z0-9_.-]+):\s*$", line)
            if m:
                current, in_settings = m.group(1), False
                targets[current] = "flat"
            elif current and re.match(r"^    settings:\s*$", line):
                in_settings = True
            elif in_settings and line.strip() and not line.lstrip().startswith("#"):
                key = re.match(r"^\s*([A-Za-z0-9_]+):", line)
                if key and key.group(1) in ("base", "configs", "groups"):
                    targets[current] = "structured"
                in_settings = False
    return targets


def cmd_setup(args):
    repo = os.path.realpath(args.repo)
    scratch = os.path.abspath(args.scratch)
    if not os.path.isfile(os.path.join(repo, "project.yml")):
        die(f"{repo}/project.yml not found; this script only handles the XcodeGen-generated Encamera repo")
    if os.path.exists(scratch) and os.listdir(scratch):
        die(f"{scratch} is not empty; run `cleanup` or pick a new directory")

    entries = [e for e in os.listdir(repo) if e not in SKIP_MIRROR]
    reserved_lower = {r.lower() for r in RESERVED}
    clashes = [e for e in entries if e.lower() in reserved_lower]
    if clashes:
        die(f"repo entries collide with scratch names (case-insensitive): {clashes}")

    os.makedirs(scratch, exist_ok=True)
    for entry in entries:
        os.symlink(os.path.join(repo, entry), os.path.join(scratch, entry))

    # Copied, not symlinked: a symlinked xcshareddata would let xcodegen write into the repo.
    shared = os.path.join(repo, PROJECT, "xcshareddata", "TestPlans")
    if os.path.isdir(shared):
        shutil.copytree(shared, os.path.join(scratch, PROJECT, "xcshareddata", "TestPlans"))

    os.makedirs(os.path.join(scratch, TESTS_DIR))
    state = {"repo": repo, "fingerprint": repo_fingerprint(repo)}
    with open(os.path.join(scratch, STATE_FILE), "w") as f:
        json.dump(state, f, indent=2)

    print(f"mirrored {len(entries)} repo entries into {scratch}")
    print(f"write temp tests into {os.path.join(scratch, TESTS_DIR)}, then run `generate`")


def write_overlay(scratch, repo):
    """Overlay that pins every target's INFOPLIST_FILE to the value in the tracked project.

    xcodegen auto-detects an Info.plist in a target's sources only when the
    directory is not a symlink; without the pin it is copied as a resource and
    the build fails with "Multiple commands produce .../Info.plist".
    """
    real = infoplist_by_target(load_pbxproj(os.path.join(repo, PROJECT, "project.pbxproj")))
    targets = spec_targets(os.path.join(repo, "project.yml"))
    if UI_TEST_TARGET not in targets:
        die(f"{UI_TEST_TARGET} not found in project.yml targets {sorted(targets)}")

    lines = ["include: [project.yml]", "targets:"]
    for name, style in targets.items():
        block = []
        values = real.get(name, {})
        distinct = {v for v in values.values() if v}
        if len(distinct) > 1 and style == "flat":
            die(f"{name} has per-config INFOPLIST_FILE values {values} but flat settings in project.yml; "
                f"the overlay cannot pin them without dropping its other settings")
        if len(distinct) == 1 and style == "flat":
            block += ["    settings:", f"      INFOPLIST_FILE: {distinct.pop()}"]
        elif len(distinct) == 1:
            block += ["    settings:", "      base:", f"        INFOPLIST_FILE: {distinct.pop()}"]
        elif distinct:
            block += ["    settings:", "      configs:"]
            for config, value in sorted(values.items()):
                if value:
                    block += [f"        {config}:", f"          INFOPLIST_FILE: {value}"]
        if name == UI_TEST_TARGET:
            block += ["    sources:", f"      - path: {TESTS_DIR}"]
        if block:
            lines += [f"  {name}:"] + block
    with open(os.path.join(scratch, OVERLAY), "w") as f:
        f.write("\n".join(lines) + "\n")


def cmd_generate(args):
    scratch = os.path.abspath(args.scratch)
    state = load_state(scratch)
    repo = state["repo"]
    check_repo_unchanged(state)

    tests = sorted(f for f in os.listdir(os.path.join(scratch, TESTS_DIR)) if f.endswith(".swift"))
    if not tests:
        die(f"no *.swift files in {os.path.join(scratch, TESTS_DIR)}")

    write_overlay(scratch, repo)
    pbxproj = os.path.join(scratch, PROJECT, "project.pbxproj")
    if os.path.exists(pbxproj):
        os.remove(pbxproj)
    run(["xcodegen", "generate", "--spec", OVERLAY], cwd=scratch)
    check_repo_unchanged(state)

    real = load_pbxproj(os.path.join(repo, PROJECT, "project.pbxproj"))
    gen = load_pbxproj(pbxproj)
    problems = []
    drift = settings_drift(settings_by_target(real), settings_by_target(gen))
    if drift:
        shown = drift[:15] + ([f"... and {len(drift) - 15} more"] if len(drift) > 15 else [])
        problems.append("build settings differ from the tracked project "
                        "(if project.yml changed, regenerate the tracked project first):\n    "
                        + "\n    ".join(shown))
    if plist_resource_count(gen) != plist_resource_count(real):
        problems.append(f"Info.plist resource entries: tracked {plist_resource_count(real)}, "
                        f"scratch {plist_resource_count(gen)}")
    missing = set(tests) - target_source_names(gen, UI_TEST_TARGET)
    if missing:
        problems.append(f"temp tests missing from {UI_TEST_TARGET} sources: {sorted(missing)}")
    real_targets, gen_targets = set(native_targets(real)), set(native_targets(gen))
    if real_targets != gen_targets:
        problems.append(f"target sets differ: tracked-only {sorted(real_targets - gen_targets)}, "
                        f"scratch-only {sorted(gen_targets - real_targets)}")
    if problems:
        die("generated project failed sanity checks:\n  " + "\n  ".join(problems))

    print(f"generated {os.path.join(scratch, PROJECT)}")
    print(f"temp tests in {UI_TEST_TARGET}: {', '.join(tests)}")


def cmd_extract(args):
    xcresult = os.path.abspath(args.xcresult)
    out = os.path.abspath(args.out)
    raw = os.path.join(out, ".raw")
    if os.path.exists(raw):
        shutil.rmtree(raw)
    os.makedirs(raw)
    run(["xcrun", "xcresulttool", "export", "attachments", "--path", xcresult, "--output-path", raw])
    with open(os.path.join(raw, "manifest.json")) as f:
        manifest = json.load(f)

    exported = []
    for test in manifest:
        for attachment in test.get("attachments", []):
            src = os.path.join(raw, attachment["exportedFileName"])
            ext = os.path.splitext(src)[1]
            # BaseUITestCase also attaches view-hierarchy text dumps; keep screenshots only.
            if ext.lower() not in (".png", ".jpg", ".jpeg", ".heic"):
                continue
            # suggestedHumanReadableName is "<name>_<index>_<UUID><ext>".
            human = attachment.get("suggestedHumanReadableName", "")
            name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}(\.\w+)?$", "", human) or os.path.splitext(human)[0]
            dest = os.path.join(out, name + ext)
            if os.path.exists(dest):
                die(f"two attachments are named {name!r}; attachScreenshot names must be unique")
            shutil.move(src, dest)
            exported.append({"name": name, "file": dest, "test": test.get("testIdentifier")})
    shutil.rmtree(raw)
    if not exported:
        die(f"no attachments in {xcresult}; did the tests run and call attachScreenshot?")
    print(json.dumps(exported, indent=2))


def cmd_cleanup(args):
    scratch = os.path.abspath(args.scratch)
    state = load_state(scratch)
    # rmtree unlinks symlinks without following them, so repo files are untouched.
    shutil.rmtree(scratch)
    subprocess.run(["git", "worktree", "prune"], cwd=state["repo"])
    check_repo_unchanged(state)
    print(f"removed {scratch}; repo git state unchanged since setup")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("setup")
    p.add_argument("--repo", required=True)
    p.add_argument("--scratch", required=True)
    p = sub.add_parser("generate")
    p.add_argument("--scratch", required=True)
    p = sub.add_parser("extract")
    p.add_argument("--xcresult", required=True)
    p.add_argument("--out", required=True)
    p = sub.add_parser("cleanup")
    p.add_argument("--scratch", required=True)
    args = parser.parse_args()
    {"setup": cmd_setup, "generate": cmd_generate,
     "extract": cmd_extract, "cleanup": cmd_cleanup}[args.command](args)


if __name__ == "__main__":
    main()
