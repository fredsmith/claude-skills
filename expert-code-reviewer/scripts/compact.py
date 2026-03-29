#!/usr/bin/env python3
"""Compact GitHub review exports into a single JSONL file.

Reads individual PR JSON files from a reviews/ directory, filters to
substantive text content (drops empty approvals, bot noise, CI updates),
and writes one JSON record per line to compacted_reviews.jsonl.

Usage: python compact.py [REVIEWS_DIR] [OUTPUT_FILE]
"""
import json
import os
import sys

reviews_dir = sys.argv[1] if len(sys.argv) > 1 else "./github_export/reviews"
output_file = sys.argv[2] if len(sys.argv) > 2 else "./github_export/compacted_reviews.jsonl"

total = with_text = parse_errors = 0

with open(output_file, "w") as out:
    for fname in sorted(os.listdir(reviews_dir)):
        if not fname.endswith(".json"):
            continue
        total += 1
        try:
            with open(os.path.join(reviews_dir, fname)) as f:
                data = json.load(f)
        except (json.JSONDecodeError, UnicodeDecodeError):
            parse_errors += 1
            continue

        pr = data.get("pr") or {}
        reviews = data.get("reviews") or []
        review_comments = data.get("review_comments") or []
        issue_comments = data.get("issue_comments") or []

        if not reviews and not review_comments and not issue_comments:
            continue

        # Keep only comments with actual text
        text_reviews = [
            {"state": r.get("state"), "body": r.get("body"), "submitted_at": r.get("submitted_at")}
            for r in reviews if r.get("body")
        ]
        text_rc = [
            {"body": r.get("body"), "path": r.get("path")}
            for r in review_comments if r.get("body")
        ]
        text_ic = [
            {"body": r.get("body")}
            for r in issue_comments if r.get("body")
        ]

        if not (text_reviews or text_rc or text_ic):
            continue
        with_text += 1

        record = {
            "file": fname.replace(".json", ""),
            "pr": {
                "title": pr.get("title"), "state": pr.get("state"),
                "user": pr.get("user"), "base": pr.get("base"),
                "created_at": pr.get("created_at"), "merged_at": pr.get("merged_at"),
                "additions": pr.get("additions"), "deletions": pr.get("deletions"),
                "changed_files": pr.get("changed_files"),
            },
            "reviews": text_reviews,
            "reviews_approve_only": [r.get("state") for r in reviews if not r.get("body")],
            "review_comments": text_rc,
            "issue_comments": text_ic,
        }
        out.write(json.dumps(record) + "\n")

print(f"Total files: {total}")
if parse_errors:
    print(f"Parse errors: {parse_errors}")
print(f"With substantive text: {with_text}")
print(f"Output: {output_file} ({os.path.getsize(output_file) / 1024:.0f}K)")
