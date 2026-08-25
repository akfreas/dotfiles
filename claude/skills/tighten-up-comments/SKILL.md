---
name: tighten-up-comments
description: >-
  Scrub authoring-narrative comments out of a branch, PR, or diff. Judges every
  comment added or touched by the change against "does this read to someone who
  never saw the ticket or the session", removes ticket IDs and process narration,
  and rewrites the survivors as short factual documentation of the code as it now
  stands. Does not commit or push.
---

# Tighten up comments

Use this skill when the work is done and the comments read like a diary of how it got done. It operates on a **diff**, never the whole repo, and it leaves the working tree dirty — committing is a separate, explicit step.

## Scope

Comments **added or modified by the change under review**. Nothing else. Untouched files are out of scope even if their comments are worse.

Resolve the diff range in this order:

1. The user named one — a PR URL or number, a commit SHA, a branch, a worktree path. Use it.
2. A PR URL/number: `gh pr diff <n>`, and get the file list with `gh pr diff <n> --name-only`.
3. Otherwise the current branch against its base: `git diff origin/main...HEAD --name-only` (substitute the repo's actual default branch).

If the user names a worktree, `cd` there first and do all the work at that absolute path — do not edit the same-named files in the main checkout.

If the range is genuinely ambiguous (detached HEAD, no upstream, several candidate bases), ask. Otherwise decide and say which range you used.

## The test

A comment survives only if it is **readable by someone with no knowledge of the ticket, the PR, or the session that produced it**. If it needs that context to parse, it goes.

Default to **removal or sharp shortening**. A comment has to earn its lines. When torn between rewriting and deleting, delete.

### Cut

- Anything that narrates the change: "we used to do X, now we do Y", "this was moved out of Z", "previously this crashed".
- Ticket and PR references: `ENC-82`, `PASGAI-196`, `#225`, "per the ticket", "as discussed". `// PASGAI-196 adds three routing modes` becomes `// Adds three routing modes` — or nothing, if the code already says it.
- Justifications aimed at a reviewer rather than a reader: why the change was needed, why this approach over another, what the alternative would have cost.
- Measurements and observations from a specific run: "observed 51s on the rig", "fails ~1 in 5", counts of attempts.
- Restatements of what the code plainly says.
- Section banners and scaffolding left over from drafting: `// --- Step 3 ---`, `// TODO(me): check this`, commented-out earlier attempts.

### Keep

- Constraints a future reader would otherwise re-break.
- Non-obvious ordering or lifecycle requirements.
- Framework or platform behavior that contradicts a reasonable expectation.
- Why the surrounding call stack forces this shape.
- Doc comments that tell a caller what it needs to know to use the thing correctly, phrased in terms of the calling code.

### Rewrite, don't recount

State the invariant, not the discovery.

- Before: `// We found that the index write was landing after the reconcile, which is why the album never showed up on the second device.`
- After: `// Index write must complete before reconcile; reconcile diffs by id and drops unknown entries.`

Short, factual, and about the code around it and the call stack that invokes it.

### Not comments

Assertion messages, failure strings, log lines, and error copy are **output**, not comments. Naming likely causes there is useful and stays. Do not scrub them.

Commit messages, PR descriptions, and Markdown docs are also out of scope unless the user asks.

## Procedure

1. Resolve the diff range and get the changed file list.
2. For each changed file, read its diff (`git diff <base>...HEAD -- <path>`) and locate every comment in the added/changed hunks — `//`, `/* */`, `#`, docstrings, doc comments (`///`, `/** */`, `"""`).
3. Judge each one against the test above. Decide: keep, rewrite, or delete. Be willing to conclude that a file's comments are all fine.
4. Apply the edits.
5. Build or run the relevant tests if the language makes comments syntactically load-bearing (docstrings, attributes, pragma-like comments) or if edits strayed into code. A pure comment scrub in Swift/TS/Python does not need a full suite run — say so rather than skipping silently.
6. Report as a per-file list: what was deleted, what was rewritten (before → after for the non-obvious ones), and what was deliberately kept and why. Give a net line count.

**Do not commit. Do not push.** Leave the changes in the working tree for review. If the user wants them committed, they will invoke `/modular-commits` themselves.

## Anti-patterns

- Bulk-deleting every comment in the diff without judging them one at a time. "Remove all the comments added in this PR" still means the keepers stay.
- Widening scope to files the change never touched.
- Replacing a narrative comment with a slightly shorter narrative comment.
- Rewriting a comment to explain the *removal* ("simplified for clarity").
- Editing the main checkout when the user pointed at a worktree.
- Touching assertion messages or log output.
- Committing, pushing, or opening a PR as part of this skill.

## Checklist

- [ ] Diff range resolved and stated
- [ ] Only files changed by the diff were touched
- [ ] Every added/changed comment judged individually
- [ ] No ticket or PR identifiers remain in comments
- [ ] Survivors read without knowledge of the ticket or session
- [ ] Assertion/log strings untouched
- [ ] Working tree left dirty — nothing committed or pushed
