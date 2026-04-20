---
name: modular-commits
description: >-
  Make modular git commits from the command line as the machine's git user,
  with one- or two-sentence messages matching the recent style of that user.
  No extended description body, no co-author trailers, no Claude attribution.
---

# Modular Git Commits

Use this skill when the user asks to commit changes. Produce small, focused commits via the `git` CLI — the same way the user would in their terminal — attributed to the machine's configured git user.

## Principles

- **Modular.** One logical change per commit. If the working tree contains unrelated edits, split them into multiple commits using targeted `git add <path>` (or `git add -p` for hunks within a file). Never lump unrelated changes into a single commit just because they share a working tree.
- **User-authored.** The commit must be attributed to the local git user (`git config user.name` / `user.email`). Do **not** add `Co-Authored-By: Claude` trailers, "Generated with Claude Code" footers, or any other Claude attribution. Do not override `--author`.
- **Match existing style.** Read the last 5 commits from the current git user and mirror their format — casing, tense, prefix conventions, punctuation, length. Consistency with that user's history beats any generic convention.
- **One or two sentences only.** The message is a single subject line (optionally a second sentence if the user's style does so). **No extended description body.** Do not add bullet lists, "why" paragraphs, test plans, or footers. That content is noise.
- **Do not push to the remote.** This is a commit-only operation. Commits need to be reviewed by a human before they are pushed.

## Procedure

1. **Inspect state.** Run these in parallel:
   - `git status` (no `-uall`)
   - `git diff` and `git diff --staged`
   - `git log -n 5 --author="$(git config user.email)" --pretty=format:"%s"` to capture recent message style from this user specifically. If that yields nothing, fall back to `git log -n 5 --pretty=format:"%an | %s"` and use the most recent commits by the configured user name.

2. **Plan the commits.** Group changes into the smallest coherent units. If everything belongs together, one commit is fine. Otherwise, stage and commit each group separately.

3. **Stage deliberately.** Use `git add <path>` for specific files. Avoid `git add -A` / `git add .` — they pull in untracked secrets, build artifacts, or stray edits. Use `git add -p` when a single file holds multiple logical changes.

4. **Write the message.** One sentence, matching the observed style. A second sentence is allowed only if the user's recent commits commonly do so. No body.

5. **Commit.** Use `git commit -m "<message>"`. Do **not** pass `--author`, `-S` overrides, `--no-verify`, or heredoc bodies. Do **not** append Claude attribution trailers.

6. **Verify.** Run `git status` and `git log -n 1 --pretty=fuller` to confirm the commit landed with the correct author and no stray trailers.

7. **Repeat** for each remaining logical group.

8. **Summarize.** After all commits land, print a tree-style summary of every commit made in this session (oldest → newest). See **Output format** below.

## Output format

After committing, print one block per commit. Use `git show --name-status --format="%h - %s" <hash>` to get the data, then render it with box-drawing characters so it reads like `tree` output.

Rules:
- Header line: `<short-hash> - <subject>`.
- Group files under `Added`, `Updated`, `Deleted`, `Renamed` (only include groups that have entries). Map git status letters: `A` → Added, `M` → Updated, `D` → Deleted, `R` → Renamed, `C` → Copied.
- Use `├──` for non-last items and `└──` for the last item at each level. The last group in a commit uses `└──`; earlier groups use `├──`. Inside a group, the last file uses `└──` and others use `├──`. Use `│   ` to continue vertical lines through non-last groups; use four spaces under the last group.
- Separate commits with a blank line.

Example (two commits, showing correct spacing):

```
75b6010 - Update gitconfig to use gitignore in home dir and update paths for android sdk
├── Added
│   ├── .gitignore_global
│   └── android/local.properties
└── Updated
    └── .gitconfig

1ae7ed5 - Add error handling to setup.sh
└── Updated
    └── setup.sh
```

If a commit touches no files (empty commit), print the header line followed by `└── (no file changes)`.

## Anti-patterns

- Adding `Co-Authored-By: Claude …` or any "Generated with Claude Code" line.
- Writing a multi-paragraph body explaining what the diff already shows.
- Bundling unrelated changes "to save a commit."
- Using `--amend` to retrofit changes into a prior commit without the user asking.
- Skipping hooks with `--no-verify`.
- Force-pushing or otherwise rewriting shared history without explicit instruction.

## Quick checklist

- [ ] Changes grouped into modular, logical commits
- [ ] Each message is 1–2 sentences, matching the user's recent style
- [ ] No extended description body
- [ ] No Claude attribution anywhere
- [ ] Author is the machine's configured git user
- [ ] Hooks ran; commit verified with `git log`
