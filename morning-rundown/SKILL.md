---
name: morning-rundown
description: Use when starting the workday or returning after time away — assembles a prioritized list of actionable items from GitHub (open PRs awaiting review, assigned issues, recent mentions) and Google Workspace (today's calendar plus any action items addressed to you in the most recent past meeting's notes doc). Also reconciles previously-tracked todos in todo.sh (marks resolved GitHub items done) and syncs new actionable items into todo.sh under a configurable context tag.
---

# Morning Rundown

Produces a "what to tackle first" briefing by pulling from GitHub and Google Workspace, then reconciles state with todo.sh so you have one persistent list of open work across sessions.

## Prerequisites

- `gh` CLI authenticated (verify with `gh auth status`)
- A Google Workspace CLI on PATH that can list calendar events and export Drive docs. The procedure below is written against [`gws`](https://crates.io/crates/gws), but any tool with equivalent JSON output works — adapt the commands as needed.
- `todo.sh` from [todo.txt-cli](https://github.com/todotxt/todo.txt-cli) installed and configured. The two helper scripts in this skill's directory wrap it:
  - `reconcile-todos.sh` — checks each tagged todo with a GitHub `url:` against current PR/issue state and marks done any that are merged/closed.
  - `sync-todos.sh` — reads newline-separated todo entries on stdin, dedups against the existing list, and adds new ones.

## Configuration

Point the skill at your environment with these env vars (defaults shown):

| Var | Default | What it controls |
| --- | --- | --- |
| `RUNDOWN_CONTEXT_TAG` | `@work` | The todo.txt context tag stamped on every synced item. Filters reconcile to just these todos. |
| `RUNDOWN_USER_NAME` | `Me` | Name pattern grepped in meeting notes to find action items addressed to you (matches `[<name>]`, `* <name>:`, or full name). |
| `RUNDOWN_TZ` | system local | IANA timezone for today's calendar window (e.g. `America/New_York`). |
| `RUNDOWN_PERSONAL_REPO_PATTERNS` | _empty_ | Comma-separated owner globs to skip in the "your open PRs" bucket (e.g. `youruser/*,scratch-*/*`). |
| `TODO_BIN` | `/opt/homebrew/bin/todo.sh` | Path to the `todo.sh` binary. |
| `TODO_CFG` | `$HOME/.todo.cfg` | todo.sh config file. |
| `TODO_FILE` | (from `TODO_CFG`) `$HOME/Documents/todo/todo.txt` | Active todo list file. |

The shell scripts read these env vars directly. The procedure below references them inline.

## User vocabulary (optional)

If you've wired todo.sh up with kanban-style fish/bash helpers (e.g. `now`, `next`, `someday`, `snooze`, `wake`), use those verbs when summarizing. The skill assumes a priority mapping where `(A)` = "now" (in progress), `(B)` = "next" (pull next), `(C)` = "someday" (backlog), and snoozed items hold a `t:YYYY-MM-DD` threshold tag that hides them from default lists. Adjust the priority mapping in step 6 if your kanban convention differs.

## Procedure

Fetch GitHub and calendar in parallel.

### 1. GitHub: live actionable items

**Do not use `gh api /notifications` for review/assignment buckets.** That endpoint returns the unread *notification inbox* — a `review_requested` entry from two weeks ago stays in the inbox even after the PR is merged or closed, so filtering by `reason` produces stale results. Use `gh search` with `--state=open` instead — it queries GitHub for items currently in those states.

Always pass `--archived=false` so PRs/issues from archived repos (read-only, can't be acted on) don't pollute the buckets. Without this, stale `review-requested` entries from long-archived projects keep appearing forever.

Run these in parallel:

```bash
# Needs your review (open PRs only)
gh search prs --review-requested=@me --state=open --archived=false \
  --json url,title,repository,updatedAt --limit 50

# Assigned PRs (open only)
gh search prs --assignee=@me --state=open --archived=false \
  --json url,title,repository,updatedAt --limit 50

# Assigned issues (open only — note: gh search issues includes PRs, so filter)
gh search issues --assignee=@me --state=open --archived=false \
  --json url,title,repository,updatedAt,isPullRequest --limit 50

# Mentions in open PRs/issues with recent activity (last 14 days)
# IMPORTANT: use python for date math — `date -v` (BSD) and `date -d` (GNU)
# are mutually exclusive, and PATH may have either. Don't substitute back.
DATE_14D_AGO=$(python3 -c 'from datetime import date,timedelta;print(date.today()-timedelta(days=14))')
gh search prs --mentions=@me --state=open --archived=false --updated=">$DATE_14D_AGO" \
  --json url,title,repository,updatedAt --limit 50
gh search issues --mentions=@me --state=open --archived=false --updated=">$DATE_14D_AGO" \
  --json url,title,repository,updatedAt,isPullRequest --limit 50
```

For the assigned-issues and mentioned-issues queries, drop entries where `isPullRequest == true` (those already appear in the PR query and would dedupe-noisy the issue bucket).

Buckets:
- review-requested PRs → "Needs your review"
- assigned PRs + assigned non-PR issues → "Assigned to you"
- mentioned PRs/issues (last 14 days) → "Mentions / active threads"

`gh search` returns web URLs in the `url` field — no conversion needed. Format each entry as `<repo nameWithOwner>#<number> — <title> — <url>`. Sort each bucket by `updatedAt` descending.

Skip the notifications API entirely unless the user explicitly asks for "what's in my inbox" — for the rundown, live state always beats inbox state.

### 1b. Your own open PRs — who to pester

Show your *own* open non-draft PRs grouped by status, so you know who to nudge for review.

```bash
# List your open non-draft PRs (last ~90 days)
DATE_90D_AGO=$(python3 -c 'from datetime import date,timedelta;print(date.today()-timedelta(days=90))')
gh search prs --author=@me --state=open --draft=false --archived=false \
  --updated=">$DATE_90D_AGO" \
  --json url,title,repository,updatedAt --limit 50
```

Older PRs (>90 days, no recent activity) are usually abandoned — skip them in the main bucket but mention the count at the bottom (e.g. "5 older PRs not shown").

For each PR returned, fetch review state:

```bash
gh pr view <url> --json url,reviewDecision,reviewRequests,latestReviews \
  --jq '{url, decision: .reviewDecision,
         pending: [.reviewRequests[].login // empty],
         reviewed: [.latestReviews[] | {who: .author.login, state: .state}]}'
```

Bucket by outcome:
- **Approved → ready to merge**: `decision == "APPROVED"`. Surface first; these are wins you can just close out.
- **Pester these reviewers**: `pending` is non-empty. Group PRs by reviewer login so you see "ping octocat about these 2" rather than scattered names. Filter out null entries (deleted users) and bot accounts (`copilot-*`, `dependabot[bot]`, etc.).
- **No reviewer requested yet**: `decision == "REVIEW_REQUIRED"` AND `pending` is empty AND no human reviews yet. These are PRs you opened and forgot to assign — flag them as "you need to actually ask someone."
- **Changes requested back to you**: `decision == "CHANGES_REQUESTED"`. Surface as "ball is in your court."

Skip PRs whose `repository.nameWithOwner` matches any glob in `RUNDOWN_PERSONAL_REPO_PATTERNS` — the rundown is about work follow-ups, not personal projects.

### 2. Today's calendar

Use your Google Workspace CLI to list today's events for the primary calendar in `RUNDOWN_TZ`. Equivalent of:

```bash
gws calendar events list --params '{
  "calendarId":"primary",
  "timeMin":"<today 00:00 in RUNDOWN_TZ>",
  "timeMax":"<tomorrow 00:00 in RUNDOWN_TZ>",
  "singleEvents":true,
  "orderBy":"startTime",
  "maxResults":50
}' --format json
```

Filter the `items[]` array:
- Skip `eventType == "workingLocation"` and `eventType == "outOfOffice"`.
- Skip self-blocks whose `summary` starts with `Busy:` or `Hold:` (these are personal blocks, not meetings).
- For each remaining event, format as `HH:MM–HH:MM TZ — <summary>`. Include `hangoutLink` if present.
- Note any event with `attachments[]` — those usually point at the meeting notes doc.

### 3. Action items from the most recent past meeting

Find the most recent past meeting whose notes contain action items.

**Strategy A (preferred): use the attached doc.**
If today's first meeting has an attachment with `mimeType: "application/vnd.google-apps.document"`, that doc is almost always the rolling notes for the recurring meeting. Export it as plain text:

```bash
gws drive files export \
  --params '{"fileId":"<attachment fileId>","mimeType":"text/plain"}' \
  --output /tmp/rundown-notes.txt
```

(`gws drive files export` writes to `download.txt` in CWD by default — clean it up after, or pass `--output` to redirect.)

**Strategy B (fallback):** if there's no attached doc, list events in the last 14 days, find the most recent event with a non-empty `description`, and use that.

Once you have the text, find items addressed to you. The default convention is `[<RUNDOWN_USER_NAME>] action item text`:

```bash
NAME="${RUNDOWN_USER_NAME:-Me}"
grep -n -E "\\[$NAME\\]|^\\* $NAME:|$NAME " /tmp/rundown-notes.txt
```

Also surface a top-level `Pending` or `Carryover` section if one exists (those persist across weeks). Capture each matched line, stripping leading bullets/whitespace.

If the doc has multiple meetings stacked (rolling notes), only pull from the most recent meeting's `Action Items` and `Upcoming Changes` (or equivalent) sections. Older entries are already-handled history. Detect section boundaries by date headers like `Apr 27, 2026 | <meeting name>`.

### 4. Reconcile existing tracked todos

Before building the rundown output, check what's already in todo.sh and resolve any GitHub items that have closed since the last run:

```bash
~/.claude/skills/morning-rundown/reconcile-todos.sh
```

The script walks `todo.txt`, finds active (non-`x `) lines tagged with `RUNDOWN_CONTEXT_TAG` and a GitHub `url:`, calls `gh pr view` / `gh issue view` to check state, and marks any `MERGED` / `CLOSED` items done in todo.sh. Stdout is one line per resolved item:

```
<state>|<url>|<task text>
```

Capture this output — you'll surface it in the rundown's "Resolved since last rundown" section. Empty stdout means nothing resolved.

### 4b. Build the snoozed-URL map

Before formatting the rundown, build a map of `{url → wake_date}` for every active todo whose `t:YYYY-MM-DD` threshold is in the future. Use this to peel snoozed items out of their normal GitHub buckets and route them to the dedicated "Snoozed" section below — the user has explicitly asked to *not* see these in the active buckets, but does want a running list of what's hidden.

```bash
awk -v today="$(date +%Y-%m-%d)" '
  !/^x / {
    if (match($0, /t:[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
      thresh = substr($0, RSTART+2, 10)
      if (thresh > today && match($0, /url:[^ ]+/)) {
        url = substr($0, RSTART+4, RLENGTH-4)
        print url "\t" thresh
      }
    }
  }
' "${TODO_FILE:-$HOME/Documents/todo/todo.txt}"
```

Each output line is `<url>\t<wake_date>`. For each GitHub item the rundown gathered in step 1/1b, check if its URL is in this map. If yes → drop it from its normal bucket and add it to the snoozed list with its wake date. The reconcile pass already ran in step 4, so any snoozed item still in the map is genuinely open on GitHub.

### 5. Synthesize the rundown

Output in this order, omitting empty sections:

```
## Morning Rundown — <YYYY-MM-DD>

### Today's meetings
- HH:MM–HH:MM TZ — <title> [Meet link if present]

### Action items from <Meeting Title> (<date>)
- <item addressed to you>

### Pending / carryover
- <items from Pending section that mention you or are unowned>

### ✅ Resolved since last rundown (N)
- <STATE> <repo>#<num> — <title> (URL)

### GitHub — needs your review (N)
- <repo>#<num> — <title> — <web url>

### GitHub — assigned to you (N)
- <repo>#<num> — <title> — <web url>

### Your open PRs — ready to merge (N)
- <repo>#<num> — <title> (approved by <reviewer>)

### Your open PRs — pester these reviewers
- **<reviewer login>**: <repo>#<num>, <repo>#<num>

### Your open PRs — no reviewer assigned (N)
- <repo>#<num> — <title>

### GitHub — mentions / active threads (N)
- <repo>#<num> — <title> — <web url>

### Suggested first move
<one-line recommendation>

### 💤 Snoozed (N)
- <repo>#<num> — <title> — wake YYYY-MM-DD
- [Carryover] <text> — wake YYYY-MM-DD
```

The Snoozed section combines two sources, sorted by wake date ascending:

1. **GitHub items the rundown surfaced that you've snoozed** — pulled from the snoozed-URL map built in step 4b. Format `<repo>#<num> — <title> — wake <date>`.
2. **Non-URL todos that are sleeping** (e.g. action items, carryover with a `t:` tag) — read directly from `todo.txt`. Format the leading bracket tag plus the item text plus wake date.

Omit the Snoozed section entirely if zero. Suggested implementation: build the GitHub list from step 4b's map intersected with the rundown's gathered URLs; for non-URL items, the awk one-liner below extracts them:

```bash
TAG="${RUNDOWN_CONTEXT_TAG:-@work}"
awk -v today="$(date +%Y-%m-%d)" -v tag="$TAG" '
  !/^x / && match($0, /t:[0-9]{4}-[0-9]{2}-[0-9]{2}/) {
    thresh = substr($0, RSTART+2, 10)
    if (thresh > today && $0 !~ /url:/) {
      line = $0
      sub(/ +t:[0-9]{4}-[0-9]{2}-[0-9]{2}/, "", line)
      sub(/^\([A-Z]\) /, "", line)
      sub(/^[0-9]{4}-[0-9]{2}-[0-9]{2} /, "", line)
      gsub(" +" tag, "", line)
      print thresh "\t" line
    }
  }
' "${TODO_FILE:-$HOME/Documents/todo/todo.txt}" | sort
```

The "Suggested first move" picks whichever single item has the highest staleness × external-dependency score. Default heuristic, in order:
1. Any of your PRs in the "ready to merge" bucket (instant wins, no one else needed).
2. The oldest open PR awaiting your review (someone is blocked on you).
3. Prep needed for the earliest meeting today (if it's within 2 hours and has an agenda doc).
4. The first action item from the prior meeting addressed to you.

### 6. Sync new actionable items to todo.sh

Build a list of todo.sh entries from the rundown's actionable buckets and pipe through `sync-todos.sh`. The script dedups by `url:` (or by full text if no URL), so it's safe to re-run on every rundown.

Each entry gets a priority prefix mapped to a kanban convention: `(A)` = "now", `(B)` = "next", `(C)` = "someday". Items without a priority are untriaged.

**Priority mapping** (each row becomes one todo line; `$TAG` = `RUNDOWN_CONTEXT_TAG`):

| Bucket                                               | Format                                                                             |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Your PR ready-to-merge                               | `(A) Merge <repo>#<num>: <title> +<repo> $TAG url:<url>`                           |
| Your PR — changes requested back                     | `(A) Address feedback on <repo>#<num>: <title> +<repo> $TAG url:<url>`             |
| Action item — source meeting recurs **today**        | `(A) [<Meeting Title> YYYY-MM-DD] <action item text> $TAG`                         |
| Needs your review                                    | `(B) Review <repo>#<num>: <title> +<repo> $TAG url:<url>`                          |
| Action item — source meeting recurs **tomorrow**     | `(B) [<Meeting Title> YYYY-MM-DD] <action item text> $TAG`                         |
| Assigned to you (PRs + non-PR issues)                | `(C) <repo>#<num>: <title> +<repo> $TAG url:<url>`                                 |
| Your PR — no reviewer assigned                       | `(C) Assign reviewer for <repo>#<num>: <title> +<repo> $TAG url:<url>`             |
| Pester reviewer (per pending login)                  | `(C) Ping <login> on <repo>#<num>: <title> +<repo> $TAG url:<url>`                 |
| Action item — meeting later this week / no recurrence | `(C) [<Meeting Title> YYYY-MM-DD] <action item text> $TAG`                         |
| Pending / carryover                                  | `(C) [Carryover] <item text> $TAG`                                                 |

**Do not** include calendar events or the "mentions / active threads" bucket — those aren't real todos.

The `+<repo>` token uses just the repo name (not `owner/repo`), e.g. `+repo-a`, `+repo-b`. Strip the owner prefix from `nameWithOwner`.

**Determining "meeting recurs today/tomorrow":** the source meeting comes from step 3 (the rolling-notes doc you found action items in). To classify priority, check whether that meeting title appears on today's or tomorrow's calendar. Today's events are already in scope from step 2; for tomorrow, run a quick second `gws calendar events list` over `[tomorrow 00:00, tomorrow 23:59]` and grep the `summary` fields. If the source title matches an event today → `(A)`. Else tomorrow → `(B)`. Else `(C)`.

Pipe the entries through the sync helper:

```bash
cat <<'EOF' | ~/.claude/skills/morning-rundown/sync-todos.sh
(B) Review repo-a#476: Add SLA monitoring +repo-a @work url:https://github.com/org/repo-a/pull/476
(A) Merge repo-b#864: Fix navbar regression +repo-b @work url:https://github.com/org/repo-b/pull/864
(B) [Tech Sync 2026-04-23] Send Q2 estimates to engineering @work
EOF
```

Stdout shows newly-added entries (one `+ <entry>` per line); stderr has an `added=N skipped=N` summary. Mention the `added=N skipped=N` count to the user after the rundown ("Synced N new tasks to todo.sh, M already tracked"). Note that dedup is by URL only — if a PR's priority should change between runs (e.g. it just got approved and is now ready-to-merge), the existing todo keeps its old priority. Mention the change in the rundown so the user can manually re-prioritize.

### Snooze convention (interop)

Synced entries can be snoozed by appending a `t:YYYY-MM-DD` threshold tag to a line. The standard todo.txt convention is to hide such items from default lists when their threshold is in the future. The reconcile and sync scripts both ignore the `t:` tag — a snoozed PR that gets merged still gets reconciled to done; a snoozed item that the rundown re-encounters still dedups by URL and won't be re-added.

A common helper pattern (in fish, bash, or zsh) is a `snooze N [days|YYYY-MM-DD]` function that appends the threshold tag for line N, plus a `wake N` function that strips it. Pair with `hide_snoozed` filtering in `~/.todo.cfg` to keep snoozed items out of default listings.

## Notes

- Use `RUNDOWN_TZ` (or system local) consistently for `timeMin`/`timeMax` and for displaying event times.
- `gws drive files export` writes to `download.txt` in the current directory by default. Either pass `--output /tmp/...` or `rm download.txt` after reading.
- If `gh search` returns 401 / hits rate limits, surface that explicitly rather than presenting an empty list.
- Don't silently skip the calendar step if the Google Workspace CLI is missing or unauthenticated — tell the user how to fix it.
- **Todo.sh format conventions for this skill**: every synced entry has the `RUNDOWN_CONTEXT_TAG` (context). PR/issue tasks also carry `+<repo>` (project) and `url:<github web url>` (used for both dedup and reconcile). Meeting/carryover tasks use `[<Meeting Title> <YYYY-MM-DD>]` or `[Carryover]` as a leading bracket tag instead of a URL. Keep this format stable — `reconcile-todos.sh` and `sync-todos.sh` both depend on it.
- The reconcile script processes resolutions in reverse line-number order so it stays correct whether `TODOTXT_AUTO_ARCHIVE` is on or off.
