---
name: building-expert-code-reviewer
description: Builds a personalized code review agent from the user's GitHub PR reviews, Slack messages, and documentation. Exports review history, compacts to substantive comments, extracts recurring patterns via parallel analysis, compiles into a reviewer agent with heuristics, then validates against historical PRs. Use when the user wants to create a code review agent that mimics their review style.
---

# Building an Expert Code Reviewer

Build a personalized reviewer agent from the user's real review history across 5 phases.

```
Progress:
- [ ] Phase 1: Export data (GitHub, Slack, other sources)
- [ ] Phase 2: Compact to substantive text
- [ ] Phase 3: Extract review patterns (parallel analysis)
- [ ] Phase 4: Build reviewer agent definition
- [ ] Phase 5: Test against historical PRs (3-4 rounds)
```

## Phase 1: Export data

### GitHub reviews

Run [scripts/export_github.sh](scripts/export_github.sh) after the user sets `USER` and `ORG` variables. Requires `gh` CLI authenticated to the target org. Exports all PRs the user reviewed, authored, or commented on, then fetches detailed review data per PR.

Output: `reviews/` directory with one JSON file per PR.

### Slack messages

Export with [slackdump](https://github.com/rusq/slackdump):

```bash
slackdump -export-type sqlite -output slackdump.sqlite
```

### Other sources (optional)

Ask the user for Confluence pages, ADRs, runbooks, or blog posts they've authored. These provide longer-form technical opinions that enrich the profile.

## Phase 2: Compact the data

Run [scripts/compact.py](scripts/compact.py) against the `reviews/` directory. Filters out empty approvals, bot noise, and CI updates — keeps only comments with substantive text.

Expected: ~20-25% of PRs have substantive text. Output: `compacted_reviews.jsonl`.

## Phase 3: Extract review patterns

Split `compacted_reviews.jsonl` into 2-3 chunks by line count. Analyze chunks in parallel — for each, extract:

1. Pattern name
2. The specific rule or opinion enforced
3. Frequency (instance count)
4. 2-3 direct quotes as evidence

Separately, query Slack for the user's technical messages (length > 100 chars, excluding join/leave). Analyze for patterns that reinforce or extend GitHub findings.

Ask the user which patterns they already knew about. Separate "known" from "discovered." Resolve contradictions between stated opinions and actual practice.

Merge parallel results into a single review profile: name, rule, frequency, evidence, rationale per pattern.

## Phase 4: Build the reviewer agent

Convert the profile into an agent definition:

1. **Numbered heuristics** — one per pattern, applied to diffs
2. **Tone guidance** — match the user's actual feedback style
3. **Scope boundaries** — what they review vs. leave to others
4. **Workflow** — read diff, understand change, apply heuristics, output findings

The profile is a reference doc. The agent is an executable definition with workflow and scope rules. Keep them separate.

## Phase 5: Test against historical PRs

See [TESTING.md](TESTING.md) for the full testing process.

Select 15-25 test PRs across categories: strong objections, approvals with comments, clean diffs, mixed domains and authors. Run the agent against each via `gh pr diff`, compare to actual reviews, score recall/precision/severity alignment.

Key gotcha: `gh pr diff` shows final merged state — issues fixed before merge are invisible. Best tests are PRs where objections changed the approach, or open PRs.

Iterate 3-4 rounds. Done when: zero false-positive problems, 80%+ recall on important findings, remaining misses are data limitations (and agent asks questions instead of guessing).
