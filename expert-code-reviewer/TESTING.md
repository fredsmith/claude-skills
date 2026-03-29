# Testing the Reviewer Agent

## Selecting test PRs

Pick 15-25 PRs covering different scenarios from the compacted JSONL (sort by review comment count to find the most opinionated reviews):

- **Strong objections** (5-8): PRs with requested changes, blocked merges, multi-comment reviews
- **Approvals with comments** (3-5): Approved but with suggestions — tests blocker vs. nice-to-have distinction
- **Clean diffs** (3-5): Approved with no comments — tests for false positives
- **Mixed domains**: Spread across infrastructure, CI/CD, config, application code
- **Mixed authors**: Review style may vary by author experience level

## Running each test

For each PR:

```bash
# Get the diff
gh pr diff <number> --repo <org>/<repo>

# Get the user's actual review for comparison
gh api repos/<org>/<repo>/pulls/<number>/reviews \
  --jq '[.[] | select(.user.login=="USERNAME") | {state,body}]'
gh api repos/<org>/<repo>/pulls/<number>/comments \
  --jq '[.[] | select(.user.login=="USERNAME") | {body,path}]'
```

Run the agent against the diff, then compare output to the actual review side-by-side.

## Scoring

For each test PR, score three dimensions:

| PR | Repo | User findings | Agent caught | Agent missed | False positives | Notes |
|----|------|--------------|-------------|-------------|----------------|-------|
| #N | repo | count | count | list | count | details |

- **Recall**: % of actual findings the agent also caught
- **Precision**: % of agent findings that are legitimate
- **Severity alignment**: Did it correctly distinguish blockers from suggestions?

## Key gotcha: merged PRs show final state

`gh pr diff` returns the final merged diff. If the user flagged something and the author fixed it before merge, the agent won't see the original problem.

Best test cases:
- PRs where the objection changed the overall approach
- PRs where issues were NOT fixed before merge
- Open PRs (diff shows exactly what was reviewed)

If all test PRs are merged with fixes applied, supplement with synthetic tests — take a clean diff and introduce a known pattern violation.

## Iteration cycle

After each round:

1. **Categorize misses**: Missing heuristic? Too-narrow trigger? Data limitation?
2. **Add or refine heuristics**: Each miss produces a concrete agent change
3. **Investigate false positives**: Narrow trigger conditions or add exceptions
4. **Re-test**: Same PRs plus 2-3 new ones. Check for regressions.

Expected progression:
- **Round 1**: 50-60% recall, several false positives
- **Round 2**: 70-80% recall after adding 3-5 heuristics
- **Round 3**: 80-90% recall. Remaining misses are usually data limitations
- **Round 4** (optional): Polish severity levels, output formatting, tone

## Done criteria

- Zero false-positive *problems* (suggestions and questions are fine)
- 80%+ recall on important findings
- Remaining misses require external data the agent can't access, and it asks questions instead of asserting
- Output tone matches the user's actual feedback style
