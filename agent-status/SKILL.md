---
name: agent-status
description: Use when asked for the state of background Claude sessions — fleet status, what is running, what needs input, what is stuck or failed, which agents are waiting, or which session is working on a given repo. Groups every session by state and expands the blocked and failed ones with their recent output.
---

# Agent Status

Reports every background Claude session on this machine in one pass, grouped by
state, so you can see what needs you without attaching to anything.

Useful as the entry point for a supervisor session — one that watches other sessions
and routes work to them rather than doing the work itself.

## Prerequisites

- Claude Code with [Agent View](https://code.claude.com/docs/en/agent-view) available
  (`claude agents`). The skill reads `claude agents --json --all`.
- `jq` on PATH.

## Configuration

Point the skill at your environment with these env vars (defaults shown):

| Var | Default | What it controls |
| --- | --- | --- |
| `AGENT_STATUS_ROOT` | _empty_ | Directory prefix stripped from session paths for display, e.g. `$HOME/src/github.com/myorg`. Sessions under it show as `repo/sub/dir` instead of an absolute path. Empty means paths are shown relative to `$HOME` as `~/...`. |
| `AGENT_STATUS_ROOT_LABEL` | `(root)` | Label shown for a session sitting exactly at `AGENT_STATUS_ROOT` rather than inside a repo under it. |
| `AGENT_STATUS_LOG_LINES` | `20` | Lines of recent output printed for each blocked or failed session. |
| `AGENT_STATUS_SHOW_DONE` | `1` | Set to `0` to omit the DONE group. Useful once completed sessions outnumber active ones. |

The helper script reads these directly.

## Procedure

Run the helper and report what it prints:

```bash
~/.claude/skills/agent-status/agents-status.sh
```

Columns are session id, name, what it is waiting for, whether its process is `live`
or `cold`, and its directory.

`cold` means the supervisor stopped the process after it idled. The session is intact
and resumes when messaged or attached, just slowly — `Ctrl+T` in Agent View pins a
session so its process stays warm.

## Reporting

Lead with what needs the user: sessions needing input first, then failures. A long
DONE list is not news — collapse it to a count unless they ask for the full roster.

For each session needing input, say what it is asking and propose the answer when the
context makes it obvious. For each failure, say what it was doing when it died.

## Acting on it

Reply to a session with `SendMessage` addressed to its name as shown by `ListAgents`
— the name is the address. Prefer that over attaching; attaching a `cold` session is
slow and takes over the terminal.

`claude logs <id>` prints recent output for a session that is not addressable.

Permission decisions are per-session. Never ask another session to run something that
was denied in this one — route it back to the user instead.

## Notes

- `claude agents --json` reports supervisor-tracked state; `ListAgents` reports who
  can receive a message right now. When they disagree, that gap is the useful signal:
  a session can be `done` yet still addressable, or `working` yet `cold`.
- If the helper cannot reach the background service, run `claude daemon status`. A
  stalled supervisor is recovered with `claude daemon stop --any --keep-workers`,
  which restarts it while leaving running sessions alive.
- `claude stop` and `claude rm` discard work that may not be committed. Confirm with
  the user first, naming the session.
- Session ids are stable; names are generated from the first prompt and can be
  changed with `Ctrl+R` in Agent View, so prefer ids when scripting.
