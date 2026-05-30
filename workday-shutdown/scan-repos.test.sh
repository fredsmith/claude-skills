#!/usr/bin/env bash
# Dependency-free test harness for scan-repos.sh (no bats).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/scan-repos.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
present() { # desc, fixed-substring, output
  if printf '%s\n' "$3" | grep -qF "$2"; then echo "ok   - $1"
  else echo "FAIL - $1"; echo "       expected substring: $2";
       printf '%s\n' "$3" | sed 's/^/         > /'; fail=1; fi
}
absent() { # desc, fixed-substring, output
  if printf '%s\n' "$3" | grep -qF "$2"; then echo "FAIL - $1 (unexpected: $2)"; fail=1
  else echo "ok   - $1"; fi
}
git_init() { git -C "$1" init -q -b main; git -C "$1" config user.email t@t; git -C "$1" config user.name t; }
commit_all() { git -C "$1" add -A; git -C "$1" commit -qm "${2:-c}"; }

ROOT="$TMP/roots"; mkdir -p "$ROOT"

# clean repo with pushed upstream → no findings
mkdir -p "$ROOT/clean"; git_init "$ROOT/clean"; echo a >"$ROOT/clean/a"; commit_all "$ROOT/clean"
git init -q --bare "$TMP/clean-origin.git"
git -C "$ROOT/clean" remote add origin "$TMP/clean-origin.git"
git -C "$ROOT/clean" push -q -u origin HEAD

# dirty repo (committed, then uncommitted edit)
mkdir -p "$ROOT/dirty"; git_init "$ROOT/dirty"; echo a >"$ROOT/dirty/a"; commit_all "$ROOT/dirty"
echo more >>"$ROOT/dirty/a"

# ahead repo: pushed upstream, then one unpushed commit
mkdir -p "$ROOT/ahead"; git_init "$ROOT/ahead"; echo a >"$ROOT/ahead/a"; commit_all "$ROOT/ahead"
git init -q --bare "$TMP/ahead-origin.git"
git -C "$ROOT/ahead" remote add origin "$TMP/ahead-origin.git"
git -C "$ROOT/ahead" push -q -u origin HEAD
echo c >"$ROOT/ahead/c"; commit_all "$ROOT/ahead" second

OUT=$(SHUTDOWN_REPO_ROOTS="$ROOT" bash "$SCRIPT")

present "dirty repo emits a dirty line" "dirty|$ROOT/dirty|" "$OUT"
absent  "clean repo emits nothing"      "|$ROOT/clean|"      "$OUT"
present "ahead repo emits an ahead line" "ahead|$ROOT/ahead|" "$OUT"

exit $fail
