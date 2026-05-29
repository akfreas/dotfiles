---
name: modular-commits
description: >-
  Make modular git commits from the command line as the machine's git user,
  with single-line imperative messages matching the skill's canonical style.
  No extended description body, no co-author trailers, no Claude attribution.
---

# Modular Git Commits

Use this skill when the user asks to commit changes. Produce small, focused commits via the `git` CLI — the same way the user would in their terminal — attributed to the machine's configured git user.

## Principles

- **Modular.** One logical change per commit. If the working tree contains unrelated edits, split them into multiple commits using targeted `git add <path>` (or `git add -p` for hunks within a file). Never lump unrelated changes into a single commit just because they share a working tree.
- **User-authored.** The commit must be attributed to the local git user (`git config user.name` / `user.email`). Do **not** add `Co-Authored-By: Claude` trailers, "Generated with Claude Code" footers, or any other Claude attribution. Do not override `--author`.
- **Match the canonical style.** Mirror the format shown in **Commit message style** below — imperative mood, capitalized first word, no trailing period, concise but descriptive. Do not read back over the git history to infer a style; the canonical example is the source of truth.
- **One line only.** The message is a single imperative subject line. **No extended description body.** Do not add bullet lists, "why" paragraphs, test plans, or footers. That content is noise.
- **Do not push to the remote.** This is a commit-only operation. Commits need to be reviewed by a human before they are pushed.

## Commit message style

Every commit subject MUST follow this format. It is the single source of truth — do not infer a different style from `git log`.

- Imperative mood, present tense (`Add`, `Fix`, `Use`, `Revert`, `Remove`, `Increase`, `Replace`, `Restore`, `Simplify`, `Support`).
- First word capitalized.
- No trailing period.
- One line, concise but specific — name the thing changed and the effect.
- No prefixes (`feat:`, `fix:`, scope tags), no body, no trailers.

Use these as the canonical examples to match:

```
Auto-scroll preview panel on audience expand to ensure variant pickers are visible
Add gentle panel scroll after audience expand to reveal variant picker
Use audience-expand semantic identifier to expand target audience in variant picker tests
Add contentDescription to audience expand header for UI test accessibility
Revert unnecessary scroll and sleep in navigation tests
Revert to coordinate scroll for audience toggles, expand single audience for variant picker
Use search bar to filter audiences instead of scrolling panel
Add scrolling and extended timeouts for navigation tests on slow CI emulators
Use AccessibilityNodeInfo ACTION_SCROLL_FORWARD to scroll panel without dismissing bottom sheet
Simplify variant picker search to only use accessibility tree traversal
Remove scroll loop from variant picker search to prevent CI hangs
Add singleClick option to tapElement to prevent double-toggle on expand-all
Fix waitForElement race condition, revert dual-click, and add robust variant picker finding
Increase default element timeout to 20s and disable emulator animations
Replace UiObject2.click() with coordinate-based taps for CI emulator reliability
```

## Procedure

1. **Inspect state.** Run these in parallel:
   - `git status` (no `-uall`)
   - `git diff` and `git diff --staged`

   Do not run `git log` to derive message style — use the canonical **Commit message style** below.

2. **Plan the commits.** Group changes into the smallest coherent units. If everything belongs together, one commit is fine. Otherwise, stage and commit each group separately.

3. **Stage deliberately.** Use `git add <path>` for specific files. Avoid `git add -A` / `git add .` — they pull in untracked secrets, build artifacts, or stray edits. Use `git add -p` when a single file holds multiple logical changes.

4. **Write the message.** One sentence, matching the canonical **Commit message style** below. No body.

5. **Commit.** Use `git commit -m "<message>"`. Do **not** pass `--author`, `-S` overrides, `--no-verify`, or heredoc bodies. Do **not** append Claude attribution trailers.

6. **Verify.** Run `git status` and `git log -n 1 --pretty=fuller` to confirm the commit landed with the correct author and no stray trailers.

7. **Repeat** for each remaining logical group.

8. **Summarize.** After all commits land, print a tree-style summary of every commit made in this session (oldest → newest). See **Output format** below.

## Output format

After committing, print one block per commit. Use `git show --name-status --format="%h - %s" <hash>` to get the data, then render it with box-drawing characters so it reads like `tree` output. Emit the block via `printf` (or `echo -e`) so the ANSI escape codes are interpreted by the terminal — do **not** wrap the output in a fenced code block.

Rules:
- Header line: `<short-hash> - <subject>`.
- Group files under `Added`, `Updated`, `Deleted`, `Renamed` (only include groups that have entries). Map git status letters: `A` → Added, `M` → Updated, `D` → Deleted, `R` → Renamed, `C` → Copied.
- Use `├──` for non-last items and `└──` for the last item at each level. The last group in a commit uses `└──`; earlier groups use `├──`. Inside a group, the last file uses `└──` and others use `├──`. Use `│   ` to continue vertical lines through non-last groups; use four spaces under the last group.
- Separate commits with a blank line.

### Colors (ANSI escape codes)

Apply these exact codes. Always terminate every colored span with `\033[0m` so color does not bleed into the next element. Tree characters (`├──`, `└──`, `│`) inherit the default terminal color — do not color them.

| Element          | Code              | Name              |
|------------------|-------------------|-------------------|
| Commit hash      | `\033[1;34m`      | bold blue         |
| Commit message   | `\033[37m`        | white             |
| `Added` label    | `\033[32m`        | green             |
| `Updated` label  | `\033[33m`        | yellow            |
| `Deleted` label  | `\033[31m`        | red               |
| `Renamed` label  | `\033[36m`        | cyan              |
| File paths       | `\033[37m`        | white             |
| Reset            | `\033[0m`         | —                 |

### Example (literal bytes to print)

```
\033[1;34m75b6010\033[0m - \033[37mUpdate gitconfig to use gitignore in home dir and update paths for android sdk\033[0m
├── \033[32mAdded\033[0m
│   ├── \033[37m.gitignore_global\033[0m
│   └── \033[37mandroid/local.properties\033[0m
└── \033[33mUpdated\033[0m
    └── \033[37m.gitconfig\033[0m

\033[1;34m1ae7ed5\033[0m - \033[37mAdd error handling to setup.sh\033[0m
└── \033[33mUpdated\033[0m
    └── \033[37msetup.sh\033[0m
```

If a commit touches no files (empty commit), print the header line followed by `└── (no file changes)` with `(no file changes)` in white.

## Anti-patterns

- Adding `Co-Authored-By: Claude …` or any "Generated with Claude Code" line.
- Writing a multi-paragraph body explaining what the diff already shows.
- Bundling unrelated changes "to save a commit."
- Using `--amend` to retrofit changes into a prior commit without the user asking.
- Skipping hooks with `--no-verify`.
- Force-pushing or otherwise rewriting shared history without explicit instruction.

## Quick checklist

- [ ] Changes grouped into modular, logical commits
- [ ] Each message is a single imperative line matching the canonical **Commit message style**
- [ ] No extended description body
- [ ] No Claude attribution anywhere
- [ ] Author is the machine's configured git user
- [ ] Hooks ran; commit verified with `git log`
