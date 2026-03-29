#!/usr/bin/env bash
set -euo pipefail

# Export all GitHub review interactions for a user across an org.
# Requires: gh CLI authenticated to the target org.
#
# Usage: USER=myuser ORG=myorg ./export_github.sh [OUTDIR]

USER="${USER:?Set USER to your GitHub username}"
ORG="${ORG:?Set ORG to the GitHub org to export from}"
OUTDIR="${1:-./github_export}"

mkdir -p "$OUTDIR/reviews"
COUNT=0

echo "Exporting $USER's reviews from $ORG → $OUTDIR"

# 1. Search for all PRs the user interacted with
gh search prs --reviewed-by="$USER" --owner="$ORG" --limit=1000 \
  --json repository,number,title,state,createdAt,updatedAt,url > "$OUTDIR/prs_reviewed.json"

gh search prs --author="$USER" --owner="$ORG" --limit=1000 \
  --json repository,number,title,state,createdAt,updatedAt,url,body > "$OUTDIR/prs_authored.json"

gh search prs --commenter="$USER" --owner="$ORG" --limit=1000 \
  --json repository,number,title,url > "$OUTDIR/prs_commented.json"

# 2. Deduplicate PR URLs
jq -r '.[].url' "$OUTDIR/prs_reviewed.json" "$OUTDIR/prs_authored.json" \
  "$OUTDIR/prs_commented.json" | sort -u > "$OUTDIR/all_pr_urls.txt"

TOTAL=$(wc -l < "$OUTDIR/all_pr_urls.txt" | tr -d ' ')
echo "Found $TOTAL unique PRs"

# 3. Fetch detailed review data for each PR
while IFS= read -r pr_url; do
  COUNT=$((COUNT + 1))
  repo=$(echo "$pr_url" | sed -E 's|https://github.com/([^/]+/[^/]+)/pull/[0-9]+|\1|')
  number=$(echo "$pr_url" | sed -E 's|.*/pull/([0-9]+)|\1|')
  safe_repo=$(echo "$repo" | tr '/' '_')
  outfile="$OUTDIR/reviews/${safe_repo}_pr${number}.json"

  [ -f "$outfile" ] && continue

  echo "[$COUNT/$TOTAL] $repo#$number"

  {
    echo '{'
    echo '"pr":'
    gh api "repos/$repo/pulls/$number" \
      --jq '{title,body,state,created_at,updated_at,merged_at,user:.user.login,head:.head.ref,base:.base.ref,additions,deletions,changed_files}' 2>/dev/null || echo 'null'
    echo ','
    echo '"reviews":'
    gh api "repos/$repo/pulls/$number/reviews" --paginate \
      --jq '[.[] | select(.user.login=="'"$USER"'") | {state,body,submitted_at}]' 2>/dev/null || echo '[]'
    echo ','
    echo '"review_comments":'
    gh api "repos/$repo/pulls/$number/comments" --paginate \
      --jq '[.[] | select(.user.login=="'"$USER"'") | {body,path,diff_hunk,created_at}]' 2>/dev/null || echo '[]'
    echo ','
    echo '"issue_comments":'
    gh api "repos/$repo/issues/$number/comments" --paginate \
      --jq '[.[] | select(.user.login=="'"$USER"'") | {body,created_at}]' 2>/dev/null || echo '[]'
    echo '}'
  } > "$outfile"

  # Rate limit: pause every 10 PRs
  if [ $((COUNT % 10)) -eq 0 ]; then
    sleep 1
  fi
done < "$OUTDIR/all_pr_urls.txt"

echo "Done. $(ls "$OUTDIR/reviews/"*.json 2>/dev/null | wc -l | tr -d ' ') PR files in $OUTDIR/reviews/"
