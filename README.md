# claude-skills

Claude Code skills for building personalized AI tools from your professional history.

## Skills

### [building-expert-code-reviewer](expert-code-reviewer/SKILL.md)

Builds a code review agent that reviews PRs the way you do. Exports your GitHub review history and Slack discussions, extracts recurring patterns via parallel analysis, and compiles them into a reviewer agent with testable heuristics.

**What you get:** A reviewer agent with 25-35 heuristics derived from your actual reviews, validated against historical PRs across 3-4 iteration rounds.

**Data sources:** GitHub PRs (`gh` CLI), Slack (`slackdump`), optionally Confluence/wiki/blog posts.

### [building-personal-writing-tone](personal-writing-tone/SKILL.md)

Builds a voice profile so Claude writes content that sounds like you. Analyzes your writing across multiple sources, extracts sentence patterns and vocabulary, and packages them as a reusable style guide with an anti-AI checklist.

**What you get:** A voice profile with sentence-level patterns, banned AI vocabulary list, 30-50 categorized writing samples, and a checklist that catches AI voice in output.

**Data sources:** GitHub reviews, Slack, blog posts, documentation, email.

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`) authenticated to your org
- [slackdump](https://github.com/rusq/slackdump) for Slack workspace export
- Python 3 for data compaction
- Claude Code for the analysis and agent-building phases

## Usage

These are Claude Code skills. Each SKILL.md contains instructions Claude follows to build the artifact. The expert-code-reviewer skill includes bundled scripts for GitHub export and data compaction.

The skills cross-reference each other where processes overlap (GitHub/Slack export), so you only need to export your data once.
