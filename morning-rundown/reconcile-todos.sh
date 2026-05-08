#!/bin/bash
# Reconcile tagged todos against current GitHub state.
# For each active todo with a GitHub url:, check if the PR/issue is closed/merged.
# If so, mark it done in todo.sh. Print resolved items to stdout, one per line:
#   <state>|<url>|<task text>
#
# Configuration (env vars, all optional):
#   RUNDOWN_CONTEXT_TAG   todo.txt context tag to filter on (default: @work)
#   TODO_BIN              path to todo.sh   (default: /opt/homebrew/bin/todo.sh)
#   TODO_CFG              todo.sh config    (default: $HOME/.todo.cfg)
#   TODO_FILE             todo.txt path     (default: $HOME/Documents/todo/todo.txt)
set -euo pipefail

TAG=${RUNDOWN_CONTEXT_TAG:-@work}
TODO_BIN=${TODO_BIN:-/opt/homebrew/bin/todo.sh}
TODO_CFG=${TODO_CFG:-$HOME/.todo.cfg}
TODO_FILE=${TODO_FILE:-$HOME/Documents/todo/todo.txt}

[ -f "$TODO_FILE" ] || exit 0

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n+1))
  # Skip already-completed lines (todo.sh marks them with leading "x ")
  case "$line" in
    "x "*) continue ;;
  esac
  # Filter to the configured context tag
  echo "$line" | grep -qF "$TAG" || continue
  # Extract URL value
  url=$(echo "$line" | grep -oE 'url:https://github\.com/[^ ]+' | head -1 | sed 's/^url://' || true)
  [ -n "$url" ] || continue

  state=""
  if echo "$url" | grep -q '/pull/'; then
    state=$(gh pr view "$url" --json state -q .state 2>/dev/null || true)
  elif echo "$url" | grep -q '/issues/'; then
    state=$(gh issue view "$url" --json state -q .state 2>/dev/null || true)
  fi

  case "$state" in
    MERGED|CLOSED)
      # Strip metadata for display
      title=$(echo "$line" \
        | sed -E 's/ +\+[^ ]+//g; s/ +@[^ ]+//g; s/ +url:[^ ]+//g; s/ +meeting:[^ ]+//g')
      printf '%d|%s|%s|%s\n' "$n" "$state" "$url" "$title" >> "$tmp"
      ;;
  esac
done < "$TODO_FILE"

# Mark done in reverse line-number order so earlier line numbers remain valid
# even if TODOTXT_AUTO_ARCHIVE=1 shifts the file.
sort -t'|' -k1,1nr "$tmp" | while IFS='|' read -r num state url title; do
  if "$TODO_BIN" -d "$TODO_CFG" do "$num" >/dev/null 2>&1; then
    printf '%s|%s|%s\n' "$state" "$url" "$title"
  fi
done
