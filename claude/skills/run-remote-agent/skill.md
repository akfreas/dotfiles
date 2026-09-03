---
name: run-remote-agent
description: >-
  Delegate a long-running task to a background Claude session on Meghan's MacBook Pro via SSH,
  freeing this computer's CPU. The remote session runs autonomously with the safety classifier
  intact (--permission-mode auto, never --dangerously-skip-permissions). Results are written to
  a known temp file on the remote machine and retrievable at any time via SSH. Use when the user
  says "run this on the remote", "delegate to meghan's machine", "offload this", or invokes
  /run-remote-agent.
---

# Run Remote Agent

Delegate work to a background Claude session on Meghan's MacBook Pro (`meghans-mbp` over Tailscale SSH). The remote session runs independently — this machine can sleep, disconnect, or continue other work. Results are retrievable at any time.

## Preflight (mandatory, every invocation)

1. **Check Tailscale** — run `tailscale status 2>&1 | grep -i meghan`. If the machine is not `active`, stop and tell the user the remote is offline.
2. **Check SSH** — run `ssh -o ConnectTimeout=10 meghans-mbp 'hostname'`. If this times out, stop.
3. **Check claude** — run `ssh -o ConnectTimeout=10 meghans-mbp 'source ~/.zshrc 2>/dev/null; which claude'`. It should be at `/Users/akfreas/.local/bin/claude`. If not found, tell the user to install/login on that machine.

All three must pass before proceeding.

## Launch pattern

Generate a unique run ID: `remote-$(date +%s)` (e.g. `remote-1725364800`).

The remote claude session must:
- Run in background mode (`--bg`) so it survives SSH disconnection
- Use `--permission-mode auto` (safety classifier active, routine ops auto-approved)
- Write its final output to `/tmp/claude-remote-<run-id>.md` on the remote machine
- Be instructed to write progress markers to `/tmp/claude-remote-<run-id>.progress` as it works

### Repository and branch context (mandatory)

Before building the prompt, determine:
1. **Remote repo path** — the path to the repository on the remote machine. SSH in and find it if unknown: `ssh meghans-mbp 'find ~ -maxdepth 4 -name "project.yml" -o -name "*.xcodeproj" 2>/dev/null | grep -i <project-name> | head -3'`
2. **Branch** — the branch this session is working on (check `git branch --show-current` locally). The remote prompt must instruct claude to `cd` into the repo and `git checkout <branch>` before doing any work, so it operates on the same code.

Both must appear in every remote prompt. The remote claude has zero context about what we're working on.

### SSH command template

```bash
ssh -o ConnectTimeout=10 meghans-mbp 'source ~/.zshrc 2>/dev/null; claude --bg --permission-mode auto' <<'PROMPT'
## Setup (do this first — abort on ANY failure)
cd <remote-repo-path> || { echo "ABORT: repo not found at <remote-repo-path>" >> /tmp/claude-remote-<run-id>.progress; echo "# ABORTED\n\nRepo not found at \`<remote-repo-path>\`" > /tmp/claude-remote-<run-id>.md; exit 1; }
git fetch origin
git checkout <branch> || { echo "ABORT: branch <branch> not found" >> /tmp/claude-remote-<run-id>.progress; echo "# ABORTED\n\nBranch \`<branch>\` not found. Available branches:\n$(git branch -a | head -20)" > /tmp/claude-remote-<run-id>.md; exit 1; }
git pull origin <branch>
If the cd, checkout, or pull fails, write the failure to both the progress and output files and STOP IMMEDIATELY. Do not attempt the task.

## Task
<task description here>

## Output instructions (follow exactly)
When you are done, write your complete final report to /tmp/claude-remote-<run-id>.md using the Write tool.
As you work, append one-line status updates to /tmp/claude-remote-<run-id>.progress using Bash (echo "step description" >> /tmp/claude-remote-<run-id>.progress).
PROMPT
```

This returns immediately with a **session ID** (a short hex string like `b152dcc5`).

### Parallel subagents on the remote machine

If the task has independent parts that benefit from parallelism, instruct the remote claude to spawn subagents with the Agent tool. Include this in the prompt:

```
Launch these as parallel subagents using the Agent tool (all in one message):
1. Agent "label-1": <task 1>
2. Agent "label-2": <task 2>
...
Wait for all agents, then compile a unified report to /tmp/claude-remote-<run-id>.md.
```

## Tracking (critical)

After launching, write a reconnection record to the **scratchpad directory** so this session (and any resumed session) knows how to check back:

Write a file at `<scratchpad>/remote-agent-<run-id>.json`:
```json
{
  "runId": "<run-id>",
  "remoteHost": "meghans-mbp",
  "remoteSessionId": "<session-id from --bg output>",
  "remoteRepoPath": "<path to repo on remote machine>",
  "branch": "<branch name>",
  "outputFile": "/tmp/claude-remote-<run-id>.md",
  "progressFile": "/tmp/claude-remote-<run-id>.progress",
  "launchedAt": "<ISO timestamp>",
  "task": "<one-line summary of what was delegated>",
  "status": "running"
}
```

Tell the user: the remote agent is running, here's the run ID, and they can say **"check on the remote"** to get status.

## Checking status

When the user says "check on the remote", "how's the remote doing", or "get remote results":

1. Read the most recent `remote-agent-*.json` from the scratchpad (or the one matching the run ID the user mentions).
2. SSH in and check three things in parallel:
   - **Progress:** `ssh meghans-mbp 'cat /tmp/claude-remote-<run-id>.progress 2>/dev/null || echo "no progress file yet"'`
   - **Output:** `ssh meghans-mbp 'cat /tmp/claude-remote-<run-id>.md 2>/dev/null || echo "not finished yet"'`
   - **Session status:** `ssh meghans-mbp 'source ~/.zshrc 2>/dev/null; claude agents --json 2>/dev/null' | grep <session-id>` (look for `"state": "done"`)

3. If the session is done and the output file exists:
   - Read the output file content via SSH and report it to the user
   - **Automatically clean up** — do all of this without asking:
     - Remove temp files on the remote: `ssh meghans-mbp 'rm -f /tmp/claude-remote-<run-id>.md /tmp/claude-remote-<run-id>.progress'`
     - Archive the remote session: `ssh meghans-mbp 'source ~/.zshrc 2>/dev/null; claude rm <session-id>'`
     - Update the tracking JSON: set `"status": "archived"` and add `"completedAt"`

4. If still running:
   - Show the progress file content
   - Report session state
   - Tell the user to check back later

## Cleanup

Cleanup is automatic — it happens as part of step 3 above whenever a completed result is picked up. There is no separate cleanup step. The principle: once the originator retrieves the results, the remote artifacts are ephemeral and should not linger.

If cleanup fails (SSH timeout, etc.), log the failure in the tracking JSON as `"status": "completed-cleanup-failed"` and note what remains. The next "check on the remote" should retry cleanup.

## Rules

1. **Never use `--dangerously-skip-permissions`.** Always `--permission-mode auto`. The safety classifier must stay active on the remote machine.
2. **Always run `--bg`.** Never block on a long SSH session — the point is to offload and disconnect.
3. **Always write the tracking JSON.** Without it, reconnection after compaction or session resume is impossible.
4. **Always instruct the remote to write output to the temp file.** Don't rely on `claude logs` as the primary output channel — it returns raw ANSI. The temp file is the clean contract.
5. **Use a local fork** to handle the SSH launch and initial tracking, so the preflight/launch noise stays out of the main context.
6. **Prompt the remote claude fully.** It starts with zero context — no knowledge of this repo, this conversation, or this machine. Include everything it needs: what to do, what files to look at (with paths on *that* machine), and the output instructions.
7. **TCC restrictions apply.** The remote machine's terminal may not have access to Desktop, Documents, Downloads, etc. Prefer `/tmp` or paths the SSH shell can access without macOS privacy gates.
