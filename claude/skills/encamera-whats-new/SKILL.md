---
name: encamera-whats-new
description: >-
  Generate the "What's New in this Version" App Store release notes for the
  Encamera iOS app by summarizing PRs merged since the last semantic-release
  tag and writing them into the `whats_new` field of
  EncameraCore/Sources/EncameraCore/scripts/app_store_localization/app_store.yml.
  Invoke when the user asks for "what's new", App Store release notes, or to
  update `whats_new`.
---

# Generate Encamera App Store "What's New" Notes

The Encamera App Store listing has a `whats_new` field in
`/Users/akfreas/github/EncameraApp/Encamera/EncameraCore/Sources/EncameraCore/scripts/app_store_localization/app_store.yml`.
On each release, that field must be rewritten to summarize what changed since
the previous release — written for App Store users, not developers.

## 1. Find the last release tag

The repo tags every semantic release. Get the most recent semver tag:

```sh
git -C /Users/akfreas/github/EncameraApp/Encamera tag --sort=-version:refname \
  | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
  | head -1
```

Use that tag as the cutoff. If unsure which tag is the actual last shipped
release, ask the user before continuing.

## 2. Read every commit message in detail

Do **not** rely on `--oneline`. PR titles alone often hide user-relevant
behavior in the body. Pull subject + body for every commit since the tag:

```sh
git -C /Users/akfreas/github/EncameraApp/Encamera log <last-tag>..HEAD \
  --pretty=format:'%h %s%n%b%n---'
```

Read all of it. Each `(#NNN)` commit is a merged PR; the body is the PR
description.

## 3. Decide what counts as user-facing

Include only changes a customer would notice in the app. Use this filter:

**Include**
- New camera, album, viewer, sharing, or import/export features
- Visible UI/UX changes (layout, controls, animations, copy that users see)
- Bug fixes for behavior a user could have hit (crashes, wrong sort order,
  flashes, modal padding, getting stuck on a screen, etc.)
- Significant user-perceivable performance improvements (faster album load,
  smoother scrolling on large albums, faster import)
- Removal of a user-visible feature
- Changes to user-facing strings the user would care about (e.g. a renamed
  feature, replaced external link a user would click)

**Exclude**
- Pure refactors / extractions / renames with no behavior change
  (e.g. "Extract zoom functionality into testable ZoomService")
- Tests, test infra, UI test seeding hooks, accessibility markers added only
  for tests
- Analytics, logging, telemetry, dashboards
- CI / workflow / build / release-tooling changes
- README, docs, in-repo user-guide files
- Debug-only or feature-flag-gated dev tooling not exposed to end users
  (e.g. "Add debug capability to clear media index" behind a debug flag)
- Dependency bumps with no user-visible effect
- Internal data-model migrations unless the user sees the result

When a single PR has both internal and user-facing changes, keep only the
user-facing slice.

## 3a. Identify feature-flag-gated bullets

Some user-facing features ship gated behind a remote feature flag (search the
PR diff or body for `Feature.` enum additions, `RemoteFeatureFlagService`
registrations, or phrases like "Gate ... behind ... feature flag"). Recent
example: the megapixel/video-quality picker is gated behind
`megapixelSettings`.

These features only reach users if the flag is on at release time, so they
need explicit confirmation before you advertise them:

- Build the bullet as normal.
- In the report back to the user (step 6), call out **every** flag-gated
  bullet by name with the flag identifier — e.g.
  *"Camera quality settings is gated behind the `megapixelSettings` remote
  flag — drop the bullet if you don't plan to flip the flag on for this
  release."*
- If multiple flag-gated features are in the diff, list each one separately.

Do not silently include or silently drop them. The user makes the call.

## 4. Write the bullets

Style rules (match the existing `whats_new` block in `app_store.yml`):

- Two sections: `New in this update:` and `Bug fixes:`. Omit a section if it
  would be empty.
- One bullet per change. Lead with a short feature name, then a colon, then a
  plain-English explanation of what the user gets. Example:
  `Camera exposure slider: adjust brightness with a smooth, iOS-style control right in the camera view`
- Customer-facing voice. No PR numbers, no file names, no internal type names
  (`ZoomService`, `MediaIndexStore`, `L10n`, etc.), no "refactored",
  "extracted", "migrated".
- Keep it tight — aim for 4–7 "new" bullets and 1–3 bug-fix bullets. If
  several small fixes don't deserve their own line, end the bug-fix list with
  `Various stability and performance improvements`.
- Do not invent features. If a commit body is ambiguous, either skip it or
  ask the user.

## 5. Update `app_store.yml`

Edit the file in place:
`/Users/akfreas/github/EncameraApp/Encamera/EncameraCore/Sources/EncameraCore/scripts/app_store_localization/app_store.yml`

Replace **only** the `whats_new: |` block under `listing:`. Leave
`description`, `keywords`, `subtitle`, etc. untouched.

Indentation must match the surrounding YAML (the block is nested under
`listing:`, so bullets are indented further). Mirror the indentation of the
existing block exactly — don't reflow other fields.

## 6. Show the user the new block

After editing, print the new `whats_new` block back to the user so they can
sanity-check the bullets before the release goes out. Do not commit or push;
the user will handle that.
