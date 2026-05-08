#!/bin/bash
# Read newline-separated todo entries on stdin. Dedup against existing todo.txt
# (by url:VALUE if present, otherwise by substring), then add new ones via todo.sh.
# Stdout: lines of "+ <added entry>" for each new task.
# Stderr: "added=N skipped=N" summary.
#
# Configuration (env vars, all optional):
#   TODO_BIN   path to todo.sh   (default: /opt/homebrew/bin/todo.sh)
#   TODO_CFG   todo.sh config    (default: $HOME/.todo.cfg)
#   TODO_FILE  todo.txt path     (default: $HOME/Documents/todo/todo.txt)
set -euo pipefail

TODO_BIN=${TODO_BIN:-/opt/homebrew/bin/todo.sh}
TODO_CFG=${TODO_CFG:-$HOME/.todo.cfg}
TODO_FILE=${TODO_FILE:-$HOME/Documents/todo/todo.txt}

existing_urls=""
if [ -f "$TODO_FILE" ]; then
  existing_urls=$(grep -oE 'url:[^ ]+' "$TODO_FILE" || true)
fi

added=0
skipped=0

while IFS= read -r entry; do
  [ -z "$entry" ] && continue

  url_tag=$(echo "$entry" | grep -oE 'url:[^ ]+' | head -1 || true)

  if [ -n "$url_tag" ]; then
    # Exact-line match against extracted url:VALUE tokens (avoids prefix collisions)
    if printf '%s\n' "$existing_urls" | grep -qxF "$url_tag"; then
      skipped=$((skipped+1)); continue
    fi
  else
    # No URL — substring match against todo.txt (todo.sh prepends a date on add,
    # so substring is the right comparison)
    if [ -f "$TODO_FILE" ] && grep -qF -- "$entry" "$TODO_FILE"; then
      skipped=$((skipped+1)); continue
    fi
  fi

  "$TODO_BIN" -d "$TODO_CFG" add "$entry" >/dev/null
  added=$((added+1))
  echo "+ $entry"

  # Track in-batch so we don't add the same URL twice in one run
  if [ -n "$url_tag" ]; then
    existing_urls=$(printf '%s\n%s' "$existing_urls" "$url_tag")
  fi
done

echo "added=$added skipped=$skipped" >&2
