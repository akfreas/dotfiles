#!/usr/bin/env python3
"""App Store Connect TestFlight beta feedback -> local JSON, plus a deterministic
dedupe check against Linear issue descriptions.

Subcommands:
  fetch   Download screenshot (and optionally crash) feedback for a release.
  dedupe  Report which fetched feedback IDs are not yet referenced by a Linear issue.

Credentials, in priority order:
  1. ASC_KEY_ID / ASC_ISSUER_ID / (ASC_PRIVATE_KEY_PATH | ASC_PRIVATE_KEY) env vars
  2. A credentials YAML at --credentials or $ASC_CREDENTIALS_PATH, shaped:
       app_store_connect:
         key_id: ABC123
         issuer_id: 3692...
         private_key_file: /path/AuthKey_ABC123.p8
       app:
         bundle_id: com.example.app
"""

import argparse
import base64
import glob
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"


# --------------------------------------------------------------------------
# Interpreter bootstrap: ES256 signing needs `cryptography`, which the system
# python usually lacks. Re-exec into an interpreter that has it.
# --------------------------------------------------------------------------
def _ensure_crypto():
    try:
        import cryptography  # noqa: F401

        return
    except ImportError:
        pass
    if os.environ.get("_TF_FEEDBACK_REEXEC"):
        sys.exit(
            "The `cryptography` package is required and no interpreter with it was found.\n"
            "Create one:\n"
            "  python3 -m venv ~/.claude/skills/testflight-feedback-to-linear/.venv\n"
            "  ~/.claude/skills/testflight-feedback-to-linear/.venv/bin/pip install cryptography\n"
            "Or set ASC_PYTHON to a python that already has it."
        )
    here = os.path.dirname(os.path.abspath(__file__))
    cred = os.environ.get("ASC_CREDENTIALS_PATH", "")
    candidates = [
        os.environ.get("ASC_PYTHON"),
        os.path.join(here, "..", ".venv", "bin", "python"),
    ]
    if cred:
        # e.g. .../scripts/app_store_localization/credentials.yml -> .../scripts/*/.venv
        scripts_dir = os.path.dirname(os.path.dirname(os.path.abspath(cred)))
        candidates += sorted(glob.glob(os.path.join(scripts_dir, "*", ".venv", "bin", "python")))
    for cand in candidates:
        if not cand:
            continue
        cand = os.path.abspath(cand)
        if not os.access(cand, os.X_OK):
            continue
        if os.path.realpath(cand) == os.path.realpath(sys.executable):
            continue
        env = dict(os.environ, _TF_FEEDBACK_REEXEC="1")
        os.execve(cand, [cand, os.path.abspath(__file__)] + sys.argv[1:], env)
    os.environ["_TF_FEEDBACK_REEXEC"] = "1"
    _ensure_crypto()


# --------------------------------------------------------------------------
# Credentials + JWT
# --------------------------------------------------------------------------
def _scalar(text, section, key):
    """Pull `key:` out of a top-level YAML `section:` without a YAML dependency."""
    body = re.search(
        r"^%s:\s*$\n((?:[ \t]+.*\n|\s*\n)*)" % re.escape(section), text, re.M
    )
    if not body:
        return None
    m = re.search(r"^\s+%s:\s*(.+?)\s*(?:#.*)?$" % re.escape(key), body.group(1), re.M)
    if not m:
        return None
    return m.group(1).strip().strip("\"'") or None


def load_credentials(path=None):
    key_id = os.environ.get("ASC_KEY_ID")
    issuer_id = os.environ.get("ASC_ISSUER_ID")
    private_key = os.environ.get("ASC_PRIVATE_KEY")
    key_path = os.environ.get("ASC_PRIVATE_KEY_PATH")
    bundle_id = os.environ.get("ASC_BUNDLE_ID")

    path = path or os.environ.get("ASC_CREDENTIALS_PATH")
    if path and os.path.exists(path):
        text = open(path, encoding="utf-8").read()
        key_id = key_id or _scalar(text, "app_store_connect", "key_id")
        issuer_id = issuer_id or _scalar(text, "app_store_connect", "issuer_id")
        key_path = key_path or _scalar(text, "app_store_connect", "private_key_file")
        bundle_id = bundle_id or _scalar(text, "app", "bundle_id")
        if key_path and not os.path.isabs(key_path):
            key_path = os.path.join(os.path.dirname(os.path.abspath(path)), key_path)

    if not private_key:
        if not key_path:
            sys.exit("No ASC private key: set ASC_PRIVATE_KEY_PATH or private_key_file in credentials.")
        key_path = os.path.expanduser(key_path)
        if not os.path.exists(key_path):
            sys.exit("ASC private key file not found: %s" % key_path)
        private_key = open(key_path, encoding="utf-8").read()
    if not key_id or not issuer_id:
        sys.exit("Missing ASC key_id/issuer_id (env ASC_KEY_ID / ASC_ISSUER_ID or credentials file).")
    return {"key_id": key_id, "issuer_id": issuer_id, "private_key": private_key, "bundle_id": bundle_id}


def _b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def make_token(creds):
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec, utils as asym_utils

    now = int(time.time())
    header = {"alg": "ES256", "kid": creds["key_id"], "typ": "JWT"}
    payload = {"iss": creds["issuer_id"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    signing_input = b".".join(
        [_b64(json.dumps(header, separators=(",", ":")).encode()),
         _b64(json.dumps(payload, separators=(",", ":")).encode())]
    )
    key = serialization.load_pem_private_key(creds["private_key"].encode(), password=None)
    der = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = asym_utils.decode_dss_signature(der)
    sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return (signing_input + b"." + _b64(sig)).decode()


# --------------------------------------------------------------------------
# API helpers
# --------------------------------------------------------------------------
def api_get(token, path, params=None):
    url = path if path.startswith("http") else API + path
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params, doseq=True)
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")
            if e.code in (429, 500, 502, 503) and attempt < 3:
                time.sleep(2 ** attempt)
                continue
            sys.exit("ASC API %s on %s\n%s" % (e.code, url, body[:2000]))
        except urllib.error.URLError as e:
            if attempt < 3:
                time.sleep(2 ** attempt)
                continue
            sys.exit("ASC API request failed for %s: %s" % (url, e))


def api_get_all(token, path, params=None, cap=1000):
    params = dict(params or {})
    params.setdefault("limit", 200)
    out, included, page = [], [], api_get(token, path, params)
    while True:
        out.extend(page.get("data", []))
        included.extend(page.get("included", []))
        nxt = (page.get("links") or {}).get("next")
        if not nxt or len(out) >= cap:
            return out, included
        page = api_get(token, nxt)


def resolve_app_id(token, bundle_id):
    data, _ = api_get_all(token, "/v1/apps", {"filter[bundleId]": bundle_id, "limit": 20})
    for app in data:
        if app.get("attributes", {}).get("bundleId") == bundle_id:
            return app["id"]
    if data:
        return data[0]["id"]
    sys.exit("No app found for bundle id %s" % bundle_id)


def resolve_builds(token, app_id, release, build_number=None):
    """`release` is the marketing/pre-release version ("1.9.0"). Accepts "1.9.0 (42)"."""
    m = re.match(r"^\s*([0-9][0-9A-Za-z.\-]*)\s*(?:[(\[]\s*([0-9A-Za-z.\-]+)\s*[)\]])?\s*$", release or "")
    if not m:
        sys.exit("Unparsable --release %r (expected e.g. 1.9.0 or '1.9.0 (42)')" % release)
    version, inline_build = m.group(1), m.group(2)
    build_number = build_number or inline_build

    params = {
        "filter[app]": app_id,
        "filter[preReleaseVersion.version]": version,
        "fields[builds]": "version,uploadedDate,expired,processingState",
        "include": "preReleaseVersion",
        "limit": 200,
        "sort": "-uploadedDate",
    }
    if build_number:
        params["filter[version]"] = build_number
    data, _ = api_get_all(token, "/v1/builds", params)
    if not data:
        sys.exit(
            "No builds found for release %s%s. Check the version string against "
            "TestFlight (it is the marketing version, not the build number)."
            % (version, " build %s" % build_number if build_number else "")
        )
    return version, [{"id": b["id"], "buildNumber": b.get("attributes", {}).get("version"),
                      "uploadedDate": b.get("attributes", {}).get("uploadedDate")} for b in data]


def index_included(included):
    return {(i["type"], i["id"]): i for i in included}


def rel_id(item, name):
    return (((item.get("relationships") or {}).get(name) or {}).get("data") or {}).get("id")


def tester_name(idx, tester_id):
    t = idx.get(("betaTesters", tester_id)) if tester_id else None
    if not t:
        return {"id": tester_id, "name": None, "email": None}
    a = t.get("attributes", {})
    name = " ".join(x for x in [a.get("firstName"), a.get("lastName")] if x).strip() or None
    return {"id": tester_id, "name": name, "email": a.get("email")}


MAGIC = [(b"\xff\xd8\xff", ".jpg", "image/jpeg"),
         (b"\x89PNG\r\n\x1a\n", ".png", "image/png"),
         (b"GIF8", ".gif", "image/gif")]


def download(url, dest_stem):
    """Fetch to `dest_stem` + the real extension. Apple hands out JPEGs regardless of
    the advertised fileName, and Linear rejects a mismatched contentType."""
    req = urllib.request.Request(url)  # screenshot URLs are pre-signed; no auth header
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                blob = resp.read()
            break
        except Exception as e:  # noqa: BLE001
            if attempt == 2:
                print("  ! screenshot download failed (%s): %s" % (dest_stem, e), file=sys.stderr)
                return None
            time.sleep(1 + attempt)
    ext, ctype = ".png", "image/png"
    for prefix, e, c in MAGIC:
        if blob.startswith(prefix):
            ext, ctype = e, c
            break
    path = dest_stem + ext
    with open(path, "wb") as fh:
        fh.write(blob)
    return {"localPath": path, "contentType": ctype, "byteSize": len(blob)}


# --------------------------------------------------------------------------
# fetch
# --------------------------------------------------------------------------
def cmd_fetch(args):
    creds = load_credentials(args.credentials)
    bundle_id = args.bundle_id or creds.get("bundle_id")
    if not bundle_id:
        sys.exit("No bundle id: pass --bundle-id or set app.bundle_id in the credentials file.")
    token = make_token(creds)

    app_id = resolve_app_id(token, bundle_id)
    version, builds = resolve_builds(token, app_id, args.release, args.build)
    print("App %s (%s) release %s -> %d build(s): %s"
          % (bundle_id, app_id, version,
             len(builds), ", ".join(str(b["buildNumber"]) for b in builds)), file=sys.stderr)

    out_dir = os.path.abspath(args.out)
    shots_dir = os.path.join(out_dir, "screenshots")
    os.makedirs(shots_dir, exist_ok=True)

    items = []
    for build in builds:
        items += fetch_screenshot_feedback(token, app_id, build, shots_dir, args.no_download)
        if args.include_crashes:
            items += fetch_crash_feedback(token, app_id, build)

    items.sort(key=lambda i: i.get("createdDate") or "", reverse=True)
    result = {
        "bundleId": bundle_id,
        "appId": app_id,
        "release": version,
        "builds": builds,
        "count": len(items),
        "outputDir": out_dir,
        "feedback": items,
    }
    path = os.path.join(out_dir, "feedback.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2, ensure_ascii=False)
    print("Wrote %d feedback item(s) to %s" % (len(items), path), file=sys.stderr)
    json.dump(result, sys.stdout, indent=2, ensure_ascii=False)
    print()


def fetch_screenshot_feedback(token, app_id, build, shots_dir, no_download):
    data, included = api_get_all(
        token,
        "/v1/apps/%s/betaFeedbackScreenshotSubmissions" % app_id,
        {"filter[build]": build["id"], "include": "tester", "sort": "-createdDate", "limit": 200},
    )
    idx = index_included(included)
    items = []
    for entry in data:
        a = entry.get("attributes", {}) or {}
        fid = entry["id"]
        shots = []
        for n, shot in enumerate(a.get("screenshots") or []):
            url = shot.get("url")
            stem = os.path.join(shots_dir, "%s-%d" % (fid, n + 1))
            got = download(url, stem) if url and not no_download else None
            shots.append({
                "fileName": (os.path.basename(got["localPath"]) if got
                             else shot.get("fileName") or "%s-%d.jpg" % (fid, n + 1)),
                "url": url,
                "localPath": got["localPath"] if got else None,
                "contentType": got["contentType"] if got else None,
                "byteSize": got["byteSize"] if got else shot.get("fileSize"),
            })
        items.append({
            "id": fid,
            "kind": "screenshot",
            "createdDate": a.get("createdDate"),
            "comment": a.get("comment"),
            "tester": tester_name(idx, rel_id(entry, "tester")),
            "buildId": build["id"],
            "buildNumber": build["buildNumber"],
            "deviceModel": a.get("deviceModel"),
            "osVersion": a.get("osVersion"),
            "devicePlatform": a.get("devicePlatform"),
            "deviceFamily": a.get("deviceFamily"),
            "locale": a.get("locale"),
            "timeZone": a.get("timeZone"),
            "connectionType": a.get("connectionType"),
            "batteryPercentage": a.get("batteryPercentage"),
            "appUptimeInMilliseconds": a.get("appUptimeInMilliseconds"),
            "diskBytesAvailable": a.get("diskBytesAvailable"),
            "screenshots": shots,
            "raw": a if os.environ.get("TF_FEEDBACK_RAW") else None,
        })
    return items


def fetch_crash_feedback(token, app_id, build):
    data, included = api_get_all(
        token,
        "/v1/apps/%s/betaFeedbackCrashSubmissions" % app_id,
        {"filter[build]": build["id"], "include": "tester", "sort": "-createdDate", "limit": 200},
    )
    idx = index_included(included)
    items = []
    for entry in data:
        a = entry.get("attributes", {}) or {}
        items.append({
            "id": entry["id"],
            "kind": "crash",
            "createdDate": a.get("createdDate"),
            "comment": a.get("comment"),
            "tester": tester_name(idx, rel_id(entry, "tester")),
            "buildId": build["id"],
            "buildNumber": build["buildNumber"],
            "deviceModel": a.get("deviceModel"),
            "osVersion": a.get("osVersion"),
            "devicePlatform": a.get("devicePlatform"),
            "locale": a.get("locale"),
            "crashLogUrl": (a.get("crashLog") or {}).get("url") if isinstance(a.get("crashLog"), dict) else None,
            "screenshots": [],
        })
    return items


# --------------------------------------------------------------------------
# dedupe
# --------------------------------------------------------------------------
def cmd_dedupe(args):
    feedback = json.load(open(args.feedback, encoding="utf-8"))
    items = feedback.get("feedback", feedback if isinstance(feedback, list) else [])

    haystacks = []  # (label, text)
    for path in args.issues:
        raw = open(path, encoding="utf-8").read()
        haystacks += flatten_issues(raw)
    if not haystacks:
        print("WARNING: issue dump(s) contained no text — every item will look new.", file=sys.stderr)

    new, existing = [], []
    for item in items:
        fid = item["id"]
        hits = [label for label, text in haystacks if fid in text]
        (existing if hits else new).append({
            "id": fid,
            "kind": item.get("kind"),
            "createdDate": item.get("createdDate"),
            "comment": (item.get("comment") or "").strip(),
            "tester": (item.get("tester") or {}).get("name") or (item.get("tester") or {}).get("email"),
            "testerEmail": (item.get("tester") or {}).get("email"),
            "buildNumber": item.get("buildNumber"),
            "deviceModel": item.get("deviceModel"),
            "osVersion": item.get("osVersion"),
            "locale": item.get("locale"),
            "screenshots": [
                {"path": s.get("localPath"), "contentType": s.get("contentType"), "byteSize": s.get("byteSize")}
                for s in item.get("screenshots") or [] if s.get("localPath")
            ],
            "matchedIssues": hits,
        })

    report = {"total": len(items), "newCount": len(new), "existingCount": len(existing),
              "new": new, "existing": existing,
              "searchQueries": [n["id"] for n in new],
              "issueSources": args.issues}
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2, ensure_ascii=False)
    print("%d feedback item(s): %d already ticketed, %d NEW"
          % (report["total"], len(existing), len(new)), file=sys.stderr)
    json.dump(report, sys.stdout, indent=2, ensure_ascii=False)
    print()


def flatten_issues(raw):
    """Return [(label, searchable_text)] from a Linear issue dump (JSON or raw text).

    A JSON dump matches only against the issue objects found inside it, never the
    whole blob: a search dump that echoes its own query would otherwise match the
    very ID it failed to find.
    """
    try:
        data = json.loads(raw)
    except ValueError:
        return [("<text dump>", raw)]

    def walk(node, out):
        if isinstance(node, dict):
            if "identifier" in node or ("id" in node and "title" in node):
                label = node.get("identifier") or node.get("id")
                out.append((str(label), json.dumps(node, ensure_ascii=False)))
                return
            for v in node.values():
                walk(v, out)
        elif isinstance(node, list):
            for v in node:
                walk(v, out)

    found = []
    walk(data, found)
    return found


# --------------------------------------------------------------------------
def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    f = sub.add_parser("fetch", help="download TestFlight beta feedback for a release")
    f.add_argument("--release", required=True, help="marketing version, e.g. 1.9.0 or '1.9.0 (42)'")
    f.add_argument("--build", help="restrict to one build number")
    f.add_argument("--bundle-id", help="defaults to app.bundle_id from the credentials file")
    f.add_argument("--credentials", help="path to credentials YAML (default $ASC_CREDENTIALS_PATH)")
    f.add_argument("--out", default="./tf-feedback", help="output directory (default ./tf-feedback)")
    f.add_argument("--include-crashes", action="store_true", help="also fetch crash feedback")
    f.add_argument("--no-download", action="store_true", help="skip downloading screenshot files")
    f.set_defaults(func=cmd_fetch)

    d = sub.add_parser("dedupe", help="find feedback IDs not referenced by any Linear issue")
    d.add_argument("--feedback", required=True, help="feedback.json produced by `fetch`")
    d.add_argument("--issues", required=True, nargs="+",
                   help="one or more files holding the Linear issue dump (JSON or text)")
    d.add_argument("--out", help="also write the report to this path")
    d.set_defaults(func=cmd_dedupe)

    args = p.parse_args()
    if args.cmd == "fetch":
        _ensure_crypto()
    args.func(args)


if __name__ == "__main__":
    main()
