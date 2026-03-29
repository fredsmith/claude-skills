---
name: building-personal-writing-tone
description: Builds a personal voice profile from the user's actual writing across GitHub reviews, Slack messages, blog posts, and documentation. Extracts sentence patterns, vocabulary, tone, and anti-patterns, then compiles into a reusable style guide with an anti-AI checklist. Use when the user wants Claude to write content that sounds like them instead of like AI.
---

# Building a Personal Writing Tone Profile

Build a voice profile from the user's real writing so Claude produces content in their voice.

```
Progress:
- [ ] Phase 1: Gather writing from multiple sources
- [ ] Phase 2: Extract voice patterns (parallel analysis per source)
- [ ] Phase 3: Build the voice profile document
- [ ] Phase 4: Test on real content and iterate
- [ ] Phase 5: Deploy as style guide reference
```

## Phase 1: Gather writing

Collect writing samples from as many sources as available. Different sources reveal different voice facets.

**GitHub reviews** — structured technical feedback. If the user already ran the export from the [expert-code-reviewer](../expert-code-reviewer/SKILL.md) skill, reuse `compacted_reviews.jsonl`. Otherwise, run those export/compact scripts first.

**Slack messages** — best single source for natural voice. Export with [slackdump](https://github.com/rusq/slackdump):

```bash
slackdump -export-type sqlite -output slackdump.sqlite
```

Query for substantive messages:

```sql
SELECT m.text, c.name as channel
FROM messages m JOIN channels c ON m.channel_id = c.id
WHERE m.user_id = 'USER_ID' AND length(m.text) > 80
  AND m.text NOT LIKE '%has joined%'
ORDER BY m.ts DESC;
```

**Email** (optional) — via `gws`: `gws gmail messages list --query "from:me" --format json`

**Long-form writing** — ask the user for blog posts, Confluence pages, ADRs, runbooks, READMEs. Copy into a `writing_samples/` directory.

## Phase 2: Extract voice patterns

Analyze each source separately in parallel, then merge. Focus on HOW they write, not WHAT they write about.

For each source, extract:
1. **Sentence patterns** — length, structure, fragments, compound sentences
2. **Vocabulary** — characteristic words/phrases, filler words, transitions
3. **Tone** — how they deliver corrections, praise, uncertainty
4. **Formatting** — lists vs. prose, emphasis, code blocks
5. **Personality markers** — humor, self-deprecation, recurring phrases

Provide 3+ direct quotes as evidence for each pattern.

## Phase 3: Build the voice profile

Merge parallel analyses into a single document. Structure as a practical style guide. See [PROFILE_TEMPLATE.md](PROFILE_TEMPLATE.md) for the recommended sections.

The most actionable section is **words to avoid** (AI tells) — words that appear in AI output but never in the user's writing. This single section produces the biggest improvement in output quality.

Also compile 30-50 representative quotes into a separate writing samples file, organized by voice category (pushback, explanations, suggestions, self-corrections, humor, operational).

## Phase 4: Test on real content

Test immediately on content the user actually needs — not synthetic exercises.

1. Pick a real piece of content (blog post, doc, email)
2. Draft it using the voice profile as style guide
3. Ask the user: does this sound like you?
4. Note every sentence that feels off and why
5. Update the profile

Common first-test issues:
- Recommendations section sounds generic (user's actual philosophy is more specific)
- Hedging is miscalibrated
- Examples are generic instead of from real experience
- Paragraph rhythm is too uniform

Two rounds usually gets to 80-90% accuracy.

## Phase 5: Deploy

Copy the voice profile to `docs/voice-profile.md` in the user's content repo. Add a CLAUDE.md reference:

```markdown
All content must follow the voice profile in docs/voice-profile.md.
```

Keep the source-of-truth copy in the archive repo; the content repo copy is a working reference. Revisit every 6-12 months to update banned words, check for tone shifts, and add new samples.
