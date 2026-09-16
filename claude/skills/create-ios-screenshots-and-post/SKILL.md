---
name: create-ios-screenshots-and-post
description: >-
  Capture screenshots in UI tests for new/changed views, run the tests, extract
  the screenshots from the xcresult bundle, and post them as a single formatted
  PR comment. Screenshots are uploaded via GitHub's user-attachments endpoint —
  never committed to the repo.
---

# Create iOS screenshots and post to PR

Use this skill when the user wants visual evidence of UI changes posted to a pull request. The goal is to make PR review effortless and leave a permanent visual record of what each change looked like.

## Overview

1. Identify new/changed views in the current unit of work.
2. Add `attachScreenshot(named:)` calls in the relevant UI tests (or confirm existing ones cover the changes).
3. Run the tests to produce an `.xcresult` bundle.
4. Extract the named screenshot attachments from the bundle.
5. Upload each image to GitHub via the user-attachments endpoint (no repo commit).
6. Post a single formatted comment on the PR.

## Prerequisites

- The repo must have a PR open for the current branch, or the user must specify a PR number.
- `gh` CLI must be authenticated (`gh auth status`).
- UI tests must inherit from `BaseUITestCase`, which provides `attachScreenshot(named:)`.

## Step 1 — Identify screenshots to capture

Determine the unit of work: diff the current branch against `origin/main` (or the PR base).

```bash
git diff --name-only origin/main...HEAD -- '*.swift'
```

Look at the changed view controllers, SwiftUI views, and screens. For each new or meaningfully changed view, there should be at least one `attachScreenshot(named:)` call in a UI test that navigates to that screen.

**If screenshots already exist** for a feature (the test already calls `attachScreenshot`), do not add duplicates. Note which tests already cover the feature — they are still relevant for step 3.

**When adding new screenshot calls**, follow these conventions:

- Use `attachScreenshot(named: "kebab-case-descriptive-name")` — the name should describe the screen/state, not the test.
- Place the call after the view is fully loaded and in the state you want to capture.
- One screenshot per distinct visual state. Multiple states of the same screen (e.g. empty vs populated) get separate named screenshots.
- The `attachScreenshot` method is defined in `BaseUITestCase` and uses `XCTAttachment(screenshot: app.screenshot())` with `.keepAlways` lifetime, so screenshots survive passing runs.

Example:

```swift
func testMediaInfoDetails() throws {
    launchApp()
    // navigate to the screen...
    app.cells.firstMatch.tap()

    attachScreenshot(named: "media-info-detail-view")
}
```

## Step 2 — Run the relevant tests

Run only the tests that produce the screenshots you need. Use `xcodebuild test` with `-only-testing` to scope the run. Always produce a result bundle:

```bash
xcodebuild test \
  -scheme Encamera \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing "EncameraUITests/<TestClass>/<testMethod>" \
  -resultBundlePath /tmp/screenshots-run.xcresult \
  2>&1 | xcpretty
```

If multiple test classes are needed, pass multiple `-only-testing` flags.

Confirm the tests passed before proceeding. If a test fails, fix it — do not skip the screenshot.

## Step 3 — Extract screenshots from the xcresult bundle

Use `xcresulttool` to list attachments and export the screenshot images:

```bash
XCRESULT="/tmp/screenshots-run.xcresult"

xcrun xcresulttool get --path "$XCRESULT" --format json > /tmp/xcresult-root.json
```

Then find the test action results and walk the action summaries to locate attachments. The attachment payloads are referenced by id and can be exported:

```bash
xcrun xcresulttool export --path "$XCRESULT" --output-path /tmp/screenshots/ --type file --id <attachment-ref-id>
```

A practical approach that works reliably:

```bash
SCREENSHOTS_DIR="/tmp/pr-screenshots"
mkdir -p "$SCREENSHOTS_DIR"

# Find all .png attachments in the xcresult bundle
find "$XCRESULT" -name "*.png" -exec cp {} "$SCREENSHOTS_DIR/" \;
```

If the `find` approach doesn't locate the files (xcresult format varies by Xcode version), fall back to `xcresulttool` JSON traversal to find attachment references and export them individually.

Name the exported files to match their `attachScreenshot(named:)` names so you can correlate them to features.

## Step 4 — Upload images to GitHub

**NEVER commit screenshots to the repository.** Use GitHub's user-attachments upload endpoint, which is token-authenticated and works on private repos:

```bash
REPO="EncameraApp/Encamera"  # or derive from `gh repo view --json nameWithOwner -q .nameWithOwner`
REPO_ID=$(gh api "repos/$REPO" --jq .id)

upload_image() {
    local file="$1"
    local name=$(basename "$file")
    local url
    url=$(curl -s "https://uploads.github.com/user-attachments/assets?name=$name&content_type=image/png&repository_id=$REPO_ID" \
        -X POST \
        -H "Authorization: Bearer $(gh auth token)" \
        -H "Accept: application/json" \
        --data-binary "@$file" | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])")
    echo "$url"
}
```

Call `upload_image` for each screenshot and store the returned URL.

**Verification**: on a private repo, an unauthenticated curl of the URL returns 404 — that is expected. The URL will render correctly in the PR comment for anyone with repo access.

## Step 5 — Post the PR comment

Compose a single comment containing all screenshots. Use this format for each screenshot section:

```markdown
### <Screen Name / Feature>
<commit SHA link(s) — the commits that introduced or changed this screen>

<Brief description: what was done, what changed, what to look at during review>

<img src="<uploaded-image-url>" width="330" />

<Device the screenshot was taken on, e.g. "iPhone 16 Pro — iOS 18.2 Simulator">

---
```

Repeat for each screenshot. The `---` separator goes between sections, not after the last one.

### Composing the commit links

For each screenshot, identify which commit(s) in the PR introduced or changed the relevant view. Link them as:

```markdown
[`abc1234`](https://github.com/EncameraApp/Encamera/commit/abc1234), [`def5678`](https://github.com/EncameraApp/Encamera/commit/def5678)
```

Use `git log origin/main..HEAD --oneline -- <relevant-file-paths>` to find the right commits.

### Posting the comment

```bash
PR_NUMBER=<number>
gh pr comment "$PR_NUMBER" --body "$(cat <<'EOF'
<composed markdown body>
EOF
)"
```

If the body is large, write it to a temp file first and use `--body-file`:

```bash
gh pr comment "$PR_NUMBER" --body-file /tmp/pr-screenshot-comment.md
```

## Target override

By default, screenshots are posted as a PR comment. The user may request a different target:

- **Artifact**: publish as a Claude Code artifact instead of a PR comment. Use the same markdown format.
- **Local file**: write the composed markdown to a file the user specifies.
- **Slack**: if the user asks for Slack, post using the format-slack-message skill conventions.

## Checklist

- [ ] Identified new/changed views from the diff
- [ ] Added `attachScreenshot(named:)` calls where missing (or confirmed existing ones)
- [ ] Ran the relevant UI tests and they passed
- [ ] Extracted screenshot PNGs from the xcresult bundle
- [ ] Uploaded each image via user-attachments endpoint (not committed to repo)
- [ ] Composed the comment with the correct format (screen name, commit links, description, image, device)
- [ ] Posted the comment to the PR

## Anti-patterns

- **Committing screenshots to the repo.** Never. Use the upload endpoint.
- **Posting one comment per screenshot.** Always batch into a single comment.
- **Screenshots of unchanged screens.** Only capture what's new or changed in this unit of work.
- **Unnamed screenshots.** Every `attachScreenshot` call must have a descriptive name — `screenshot-1` is not acceptable.
- **Skipping failed tests.** If a test fails, fix it. A screenshot of a broken state is not useful evidence.
