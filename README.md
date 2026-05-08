# claude-skills

Claude Code skills — both daily-driver workflows and one-shot builders that turn your professional history into personalized AI tools.

## Skills

### [morning-rundown](morning-rundown/SKILL.md)

Assembles a "what to tackle first" briefing from GitHub (PRs awaiting your review, assigned issues, mentions, your own open PRs grouped by who-to-pester) and Google Workspace (today's calendar plus action items addressed to you in the most recent meeting's notes). Reconciles previously-tracked todos in [todo.sh](https://github.com/todotxt/todo.txt-cli) — items whose PRs/issues have closed get marked done — and syncs new actionable items back, deduped by URL.

**What you get:** A morning-of briefing in priority order, plus a self-maintaining work queue in `todo.txt` that survives across sessions. Configurable context tag, name pattern, and timezone via env vars.

**Data sources:** GitHub (`gh` CLI), Google Workspace calendar + Drive (any CLI with JSON output works; written against [`gws`](https://crates.io/crates/gws)), todo.sh.

### [building-expert-code-reviewer](expert-code-reviewer/SKILL.md)

Builds a code review agent that reviews PRs the way you do. Exports your GitHub review history and Slack discussions, extracts recurring patterns via parallel analysis, and compiles them into a reviewer agent with testable heuristics.

**What you get:** A reviewer agent with 25-35 heuristics derived from your actual reviews, validated against historical PRs across 3-4 iteration rounds.

**Data sources:** GitHub PRs (`gh` CLI), Slack (`slackdump`), optionally Confluence/wiki/blog posts.

### [building-personal-writing-tone](personal-writing-tone/SKILL.md)

Builds a voice profile so Claude writes content that sounds like you. Analyzes your writing across multiple sources, extracts sentence patterns and vocabulary, and packages them as a reusable style guide with an anti-AI checklist.

**What you get:** A voice profile with sentence-level patterns, banned AI vocabulary list, 30-50 categorized writing samples, and a checklist that catches AI voice in output.

**Data sources:** GitHub reviews, Slack, blog posts, documentation, email.

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`) authenticated to your org (all skills)
- [slackdump](https://github.com/rusq/slackdump) for Slack workspace export (builder skills)
- Python 3 for data compaction (builder skills)
- [todo.txt-cli](https://github.com/todotxt/todo.txt-cli) (`todo.sh`) and a Google Workspace CLI (morning-rundown)
- Claude Code for the analysis and agent-building phases

## Usage

These are Claude Code skills. Each SKILL.md contains instructions Claude follows to build the artifact. The expert-code-reviewer skill includes bundled scripts for GitHub export and data compaction.

The skills cross-reference each other where processes overlap (GitHub/Slack export), so you only need to export your data once.
