---
name: workday-shutdown
description: Use at the end of the workday or before logging off — scans all your local git repos under configured roots for stranded work (uncommitted changes, unpushed commits, WIP branches with no PR), checks GitHub for unsubmitted PR reviews and your stale draft PRs, splits work vs personal, offers to push or open draft PRs per item with confirmation, and carries unfinished work into todo.sh so the next morning-rundown resurfaces it.
---

# Workday Shutdown

The end-of-day bookend to morning-rundown. Makes sure no work is stranded — unpushed/uncommitted locally, or left pending on GitHub — before you log off, and feeds anything unfinished into todo.sh so it resurfaces tomorrow.

## Prerequisites

- `gh` CLI authenticated (`gh auth status`).
- `git`, `python3` on PATH.
- The [morning-rundown](../morning-rundown/SKILL.md) skill installed — this skill reuses its `sync-todos.sh` for carryover and shares its `RUNDOWN_*` / `TODO_*` config. If `sync-todos.sh` is not present, skip the carryover step and tell the user.
- `todo.sh` configured (same setup as morning-rundown).

## Configuration

| Var | Default | What it controls |
| --- | --- | --- |
| `SHUTDOWN_REPO_ROOTS` | `$project_dirs` | Colon-separated dirs walked for git repos. If unset, uses your exported `$project_dirs`. There is intentionally **no** broad fallback to `$SRCPATH`/`$HOME/src` — scanning your whole source tree pulls in archived/unrelated repos. If neither is set, the scan errors instead of sweeping blindly. |
| `SHUTDOWN_DRAFT_STALE_DAYS` | `7` | A draft PR untouched longer than this is flagged stale. |
| `SHUTDOWN_PERSONAL_TAG` | `@personal` | todo.sh context tag for personal carryover. |
| `RUNDOWN_CONTEXT_TAG` | `@work` | (shared) tag on work carryover. |
| `RUNDOWN_PERSONAL_REPO_PATTERNS` | _empty_ | (shared) comma-separated `owner/repo` globs that mark a repo personal. |
| `TODO_BIN` / `TODO_CFG` / `TODO_FILE` | (as morning-rundown) | (shared) todo.sh wiring. |

## Procedure

### 1. Local git sweep

Run the helper and parse its output (one finding per line, `<type>|<repo_path>|<owner/repo>|<branch>|<detail>`):

```bash
~/.claude/skills/workday-shutdown/scan-repos.sh
```

`type` is `dirty` (N changed files), `ahead` (N unpushed commits, has upstream), or `branch-no-upstream` (committed branch never pushed). `owner/repo` is empty for non-GitHub or origin-less repos.

### 2. GitHub-side signals

Capture your login once, then run these:

```bash
ME=$(gh api user --jq .login)
```

**Unsubmitted PR reviews** — open PRs where you started a review but never submitted it (state `PENDING`, visible only to you):

```bash
gh search prs --involves=@me --state=open --archived=false \
  --json url,number,repository --limit 50
# For each result <owner/repo>#<number>:
gh api "repos/<owner>/<repo>/pulls/<number>/reviews" \
  --jq ".[] | select(.user.login==\"$ME\" and .state==\"PENDING\") | .html_url" 2>/dev/null
```

Any PR that returns a URL has a pending review by you → finding "unsubmitted review."

**Stale draft PRs** — your own draft PRs untouched beyond the threshold:

```bash
STALE=$(python3 -c "from datetime import date,timedelta;print(date.today()-timedelta(days=${SHUTDOWN_DRAFT_STALE_DAYS:-7}))")
gh search prs --author=@me --draft --state=open --archived=false \
  --json url,title,repository,updatedAt --limit 50
```

Keep entries whose `updatedAt` date is older than `$STALE`.

**WIP branches with no PR** — for each `ahead` or `branch-no-upstream` finding from step 1 that has a non-empty `owner/repo` and `branch`, check whether any PR already exists for that branch:

```bash
gh pr list --repo <owner/repo> --head <branch> --state all --json url --jq '.[].url'
```

Empty output → no PR exists for that branch → finding "WIP branch, no PR" (offer a draft PR). Non-empty → a PR already exists; the push offer covers it.

### 3. Classify work vs personal

A finding is **personal** if its `owner/repo` matches any glob in `RUNDOWN_PERSONAL_REPO_PATTERNS`, or if it has no `owner/repo` (origin-less repos can't be work follow-ups). Everything else is **work**. Keep the two sets separate throughout the report and carryover.

### 4. Report

Print the report, omitting empty sections. Work and Personal are separate top-level groupings:

```
## Workday Shutdown — <YYYY-MM-DD>

### Work
#### 🚧 Uncommitted changes (N)
- <repo-name> on <branch> — N files changed
#### ⬆️ Unpushed commits (N)
- <repo-name>/<branch> — N ahead            [offer: push]
#### 📂 WIP branches, no PR (N)
- <repo-name>/<branch>                       [offer: open draft PR]
#### 💬 Unsubmitted PR reviews (N)
- <owner/repo>#<num>                          [submit or discard]
#### 📝 Stale draft PRs (N)
- <owner/repo>#<num> — <title> (untouched Nd)

### Personal
#### 🚧 Uncommitted changes (N)
- <repo-name> on <branch> — N files changed
#### ⬆️ Unpushed commits (N)
- <repo-name>/<branch> — N ahead            [offer: push]
#### 📂 WIP branches, no PR (N)
- <repo-name>/<branch>                       [offer: open draft PR]

### ✅ Carryover synced to todo.sh (N)
- @work: <text>
- @personal: <text>
```

`<repo-name>` is the basename of `<repo_path>`.

### 5. Offers (per item, confirm each — run BEFORE carryover)

Surface the actionable findings and, for each, ask before acting. Running offers first means anything you push/PR tonight is no longer stranded and is excluded from carryover.

- `dirty` → **flag only**, no offer (you write your own commits).
- `ahead` → offer: `git -C <repo_path> push`
- `branch-no-upstream` → offer: `git -C <repo_path> push -u origin <branch>`
- WIP-branch-no-PR (after a push, or any pushed branch with no PR) → offer: `gh pr create --repo <owner/repo> --head <branch> --draft --fill`
- `unsubmitted review` / `stale draft PR` → flag only (act in the browser).

Never auto-commit a dirty tree, and never push/PR without explicit confirmation.

### 6. Carryover to todo.sh (automatic, for still-stranded items)

After offers, build todo lines for work that is **still** stranded (items you didn't push/PR, dirty trees, and unsubmitted reviews) and pipe them through morning-rundown's sync helper. Work items get `RUNDOWN_CONTEXT_TAG` (`@work`); personal items get `SHUTDOWN_PERSONAL_TAG` (`@personal`). `sync-todos.sh` dedups by `url:` (or full text when there's no URL), so re-running nightly is safe.

Line formats (`$TAG` is `@work` for work findings, `@personal` for personal):

| Finding | todo line |
| --- | --- |
| dirty | `(A) Commit & push uncommitted changes in <repo-name> $TAG` |
| ahead (declined push) | `(A) Push <branch> in <repo-name> $TAG` |
| branch-no-upstream (declined) | `(A) Push <branch> in <repo-name> $TAG` |
| WIP-branch-no-PR (declined) | `(B) Open draft PR for <branch> in <repo-name> $TAG` |
| unsubmitted review | `(A) Submit or discard pending review on <owner/repo>#<num> +<repo-name> $TAG url:<pr url>` |

```bash
cat <<'EOF' | ~/.claude/skills/morning-rundown/sync-todos.sh
(A) Commit & push uncommitted changes in repo-a @work
(B) Open draft PR for feature-x in repo-b @work
(A) Fix typo in personal-site @personal
EOF
```

`sync-todos.sh` prints each newly-added entry on stdout and an `added=N skipped=M` summary on stderr. Report that count in the Carryover section. Stale draft PRs do **not** carry over (already on GitHub, not stranded). Personal carryover uses `@personal` so it never pollutes the `@work` queue; note that morning-rundown's reconcile only tracks `@work` items, so `@personal` reminders are yours to clear.

## Notes

- If `gh` is unauthenticated or rate-limited, surface that explicitly — don't present empty GitHub sections as "all clear."
- The scan covers only `SHUTDOWN_REPO_ROOTS` (or `$project_dirs`) — never the whole `$HOME/src`. If neither is set, `scan-repos.sh` exits non-zero with a message; surface it and ask the user to set `SHUTDOWN_REPO_ROOTS` rather than scanning blindly. Note `$project_dirs` must be **exported** for the helper to see it; if the report looks empty or wrong, run the scan with `SHUTDOWN_REPO_ROOTS="$project_dirs" ~/.claude/skills/workday-shutdown/scan-repos.sh` to forward it explicitly.
- Repos with no `origin` are still scanned for local state and classified personal; no GitHub-side checks run for them.
- The helper finds git repos (including worktrees, whose `.git` is a file) up to 4 levels deep under each root, follows symlinked roots, and prunes inside each repo. Worktrees kept under a gitignored `.worktrees/` are scanned too — stranded work there still surfaces.
