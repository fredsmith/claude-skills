# claude-skills

Claude Code skills — both daily-driver workflows and one-shot builders that turn your professional history into personalized AI tools.

## Installation

Skills live in `~/.claude/skills/<name>/` and are picked up by Claude Code globally. Each skill below has its own one-liner — install only what you want. Re-run any one-liner to update that skill.

If you'd rather track them all with `git pull`, see [Install all skills via clone + symlink](#install-all-skills-via-clone--symlink) at the bottom.

## Skills

### [morning-rundown](morning-rundown/SKILL.md)

Assembles a "what to tackle first" briefing from GitHub (PRs awaiting your review, assigned issues, mentions, your own open PRs grouped by who-to-pester) and Google Workspace (today's calendar plus action items addressed to you in the most recent meeting's notes). Reconciles previously-tracked todos in [todo.sh](https://github.com/todotxt/todo.txt-cli) — items whose PRs/issues have closed get marked done — and syncs new actionable items back, deduped by URL.

**What you get:** A morning-of briefing in priority order, plus a self-maintaining work queue in `todo.txt` that survives across sessions. Configurable context tag, name pattern, and timezone via env vars.

**Data sources:** GitHub (`gh` CLI), Google Workspace calendar + Drive (any CLI with JSON output works; written against [`gws`](https://crates.io/crates/gws)), todo.sh.

**Install:**

```bash
mkdir -p ~/.claude/skills && curl -fsSL https://github.com/fredsmith/claude-skills/archive/refs/heads/main.tar.gz | tar -xz -C ~/.claude/skills --strip-components=1 claude-skills-main/morning-rundown
```

**Recommended todo.sh setup (zsh/bash):**

The skill works against a stock `todo.sh` install but the workflow assumes a few conventions. Add to your shell rc (`~/.zshrc` or `~/.bashrc`):

```bash
# todo.sh built-ins
export TODOTXT_DEFAULT_ACTION=list                          # bare `todo.sh` lists instead of printing usage
export TODOTXT_AUTO_ARCHIVE=1                               # completed items move to done.txt automatically
export TODOTXT_CFG_FILE="$HOME/Documents/todo/todo.cfg"     # or wherever your todo.cfg lives

# morning-rundown skill knobs
export RUNDOWN_CONTEXT_TAG="@work"                          # context tag stamped on synced items
export RUNDOWN_USER_NAME="YourFirstName"                    # name grepped in meeting notes for action items
# export RUNDOWN_TZ="America/New_York"                      # optional, defaults to system local
```

Then add a snooze filter to your `todo.cfg` so items with a future `t:YYYY-MM-DD` threshold are hidden from default lists. The skill writes these tags when you snooze, and reconcile/sync ignore them — so a snoozed PR that gets merged still gets marked done, and a snoozed action item still dedups by URL.

```bash
# In ~/Documents/todo/todo.cfg (path matches TODOTXT_CFG_FILE above)
hide_snoozed() {
  awk -v today="$(date +%Y-%m-%d)" '
    { if (match($0, /t:[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
        thresh = substr($0, RSTART+2, 10)
        if (thresh > today) next
      }
      print
    }
  '
}
export -f hide_snoozed
export TODOTXT_FINAL_FILTER=hide_snoozed
```

`todo.cfg` is sourced by `todo.sh` (a bash script), so `export -f` works regardless of your interactive shell.

**Optional kanban helpers (zsh/bash):**

The skill's `(A)/(B)/(C)` priorities map to a "now / next / someday" kanban, and the rundown can surface a `Snoozed` section. These functions give you matching verbs at the shell:

```bash
alias t='todo.sh'

now()     { [ $# -gt 0 ] && todo.sh add "(A) $*" || todo.sh lsp A; }   # in progress
next()    { [ $# -gt 0 ] && todo.sh add "(B) $*" || todo.sh lsp B; }   # pull-next
someday() { [ $# -gt 0 ] && todo.sh add "(C) $*" || todo.sh lsp C; }   # backlog
all()     { TODOTXT_FINAL_FILTER=cat todo.sh ls "$@"; }                # bypass hide_snoozed

# snooze N [days|YYYY-MM-DD]   default 7 days
snooze() {
  local item=$1 when=${2:-7} date file="$HOME/Documents/todo/todo.txt"
  if [[ $when =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    date=$when
  elif date -v+1d +%Y-%m-%d >/dev/null 2>&1; then
    date=$(date -v+"${when}d" +%Y-%m-%d)            # BSD/macOS
  else
    date=$(date -d "+$when days" +%Y-%m-%d)         # GNU/Linux
  fi
  local current stripped
  current=$(sed -n "${item}p" "$file")
  stripped=$(echo "$current" | sed -E 's/ +t:([0-9]{4}-[0-9]{2}-[0-9]{2})?//g')
  todo.sh replace "$item" "$stripped t:$date"
}

wake() {
  local item=$1 file="$HOME/Documents/todo/todo.txt"
  local current stripped
  current=$(sed -n "${item}p" "$file")
  stripped=$(echo "$current" | sed -E 's/ +t:([0-9]{4}-[0-9]{2}-[0-9]{2})?//g')
  todo.sh replace "$item" "$stripped"
}

snoozed() {
  awk -v today="$(date +%Y-%m-%d)" '
    !/^x / && match($0, /t:[0-9]{4}-[0-9]{2}-[0-9]{2}/) {
      thresh = substr($0, RSTART+2, 10)
      if (thresh > today) printf "%4d  wake:%s  %s\n", NR, thresh, $0
    }
  ' "$HOME/Documents/todo/todo.txt" | sort -k2,2
}
```

### [building-expert-code-reviewer](expert-code-reviewer/SKILL.md)

Builds a code review agent that reviews PRs the way you do. Exports your GitHub review history and Slack discussions, extracts recurring patterns via parallel analysis, and compiles them into a reviewer agent with testable heuristics.

**What you get:** A reviewer agent with 25-35 heuristics derived from your actual reviews, validated against historical PRs across 3-4 iteration rounds.

**Data sources:** GitHub PRs (`gh` CLI), Slack (`slackdump`), optionally Confluence/wiki/blog posts.

**Install:**

```bash
mkdir -p ~/.claude/skills && curl -fsSL https://github.com/fredsmith/claude-skills/archive/refs/heads/main.tar.gz | tar -xz -C ~/.claude/skills --strip-components=1 claude-skills-main/expert-code-reviewer
```

### [building-personal-writing-tone](personal-writing-tone/SKILL.md)

Builds a voice profile so Claude writes content that sounds like you. Analyzes your writing across multiple sources, extracts sentence patterns and vocabulary, and packages them as a reusable style guide with an anti-AI checklist.

**What you get:** A voice profile with sentence-level patterns, banned AI vocabulary list, 30-50 categorized writing samples, and a checklist that catches AI voice in output.

**Data sources:** GitHub reviews, Slack, blog posts, documentation, email.

**Install:**

```bash
mkdir -p ~/.claude/skills && curl -fsSL https://github.com/fredsmith/claude-skills/archive/refs/heads/main.tar.gz | tar -xz -C ~/.claude/skills --strip-components=1 claude-skills-main/personal-writing-tone
```

## Install all skills via clone + symlink

If you want every skill, tracked against upstream so `git pull` updates them in place:

```bash
git clone https://github.com/fredsmith/claude-skills.git ~/src/claude-skills
mkdir -p ~/.claude/skills
for d in ~/src/claude-skills/*/; do
  ln -sfn "$d" ~/.claude/skills/"$(basename "$d")"
done
```

Update later with `git -C ~/src/claude-skills pull`.

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`) authenticated to your org (all skills)
- [slackdump](https://github.com/rusq/slackdump) for Slack workspace export (builder skills)
- Python 3 for data compaction (builder skills)
- [todo.txt-cli](https://github.com/todotxt/todo.txt-cli) (`todo.sh`) and a Google Workspace CLI (morning-rundown)
- Claude Code for the analysis and agent-building phases

## Usage

These are Claude Code skills. Each SKILL.md contains instructions Claude follows to build the artifact. The expert-code-reviewer skill includes bundled scripts for GitHub export and data compaction.

The skills cross-reference each other where processes overlap (GitHub/Slack export), so you only need to export your data once.
