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

# github origin, committed, no upstream → branch-no-upstream + owner/repo parsed
mkdir -p "$ROOT/ghbranch"; git_init "$ROOT/ghbranch"; echo a >"$ROOT/ghbranch/a"; commit_all "$ROOT/ghbranch"
git -C "$ROOT/ghbranch" remote add origin git@github.com:acme/widget.git

# no origin, committed, no upstream → branch-no-upstream, empty owner/repo
mkdir -p "$ROOT/noorigin"; git_init "$ROOT/noorigin"; echo a >"$ROOT/noorigin/a"; commit_all "$ROOT/noorigin"

# worktree of an existing repo (its .git is a FILE), with an uncommitted edit → must be scanned
git -C "$ROOT/ahead" worktree add -q "$ROOT/ahead-wt" -b wtbranch 2>/dev/null
echo wt >"$ROOT/ahead-wt/wtfile"

# upstream existed then was pruned ([gone]): branch was pushed, merged, and the
# remote branch deleted. Clean tree, in sync — NOT stranded, must emit nothing.
mkdir -p "$ROOT/gone"; git_init "$ROOT/gone"; echo a >"$ROOT/gone/a"; commit_all "$ROOT/gone"
git init -q --bare "$TMP/gone-origin.git"
git -C "$ROOT/gone" remote add origin "$TMP/gone-origin.git"
git -C "$ROOT/gone" push -q -u origin main
git -C "$ROOT/gone" checkout -q -b feature
echo b >"$ROOT/gone/b"; commit_all "$ROOT/gone" feat
git -C "$ROOT/gone" push -q -u origin feature
git -C "$ROOT/gone" push -q origin --delete feature
git -C "$ROOT/gone" fetch -q --prune

OUT=$(SHUTDOWN_REPO_ROOTS="$ROOT" bash "$SCRIPT")

present "dirty repo emits a dirty line" "dirty|$ROOT/dirty|" "$OUT"
present "worktree (.git file) is scanned" "$ROOT/ahead-wt|" "$OUT"
absent  "clean repo emits nothing"      "|$ROOT/clean|"      "$OUT"
present "ahead repo emits an ahead line" "ahead|$ROOT/ahead|" "$OUT"
present "github no-upstream parses owner/repo" "branch-no-upstream|$ROOT/ghbranch|acme/widget|" "$OUT"
present "no-origin no-upstream has empty owner/repo" "branch-no-upstream|$ROOT/noorigin||" "$OUT"
absent  "pruned ([gone]) upstream is not treated as stranded" "$ROOT/gone|" "$OUT"

# Fallback: SHUTDOWN_REPO_ROOTS unset → use $project_dirs
OUT_PD=$(env -u SHUTDOWN_REPO_ROOTS project_dirs="$ROOT" bash "$SCRIPT")
present "falls back to \$project_dirs when SHUTDOWN_REPO_ROOTS unset" "dirty|$ROOT/dirty|" "$OUT_PD"

# No broad fallback: with neither SHUTDOWN_REPO_ROOTS nor project_dirs set, the
# scanner must NOT scan $SRCPATH or ~/src — it errors instead of sweeping broadly.
OUT_NR=$(env -u SHUTDOWN_REPO_ROOTS -u project_dirs SRCPATH="$ROOT" HOME="$ROOT" bash "$SCRIPT" 2>"$TMP/err_nr"); rc_nr=$?
ERR_NR=$(cat "$TMP/err_nr")
absent "does NOT fall back to \$SRCPATH" "dirty|$ROOT/dirty|" "$OUT_NR"
if [ "$rc_nr" -ne 0 ]; then echo "ok   - nonzero exit when no roots configured"; else echo "FAIL - expected nonzero exit when no roots, got 0"; fail=1; fi
if printf '%s\n' "$ERR_NR" | grep -qF "SHUTDOWN_REPO_ROOTS"; then echo "ok   - error names SHUTDOWN_REPO_ROOTS"; else echo "FAIL - missing helpful error naming SHUTDOWN_REPO_ROOTS"; fail=1; fi

# Missing root in the list is skipped without error
OUT_MISS=$(SHUTDOWN_REPO_ROOTS="$ROOT:/nonexistent/xyz123" bash "$SCRIPT"); rc=$?
present "still scans real roots when a listed root is missing" "dirty|$ROOT/dirty|" "$OUT_MISS"
if [ "$rc" -eq 0 ]; then echo "ok   - exits 0 despite missing root"; else echo "FAIL - nonzero exit ($rc) on missing root"; fail=1; fi

# symlinked root must be traversed (find -L)
ln -s "$ROOT" "$TMP/rootlink"
OUT_LINK=$(SHUTDOWN_REPO_ROOTS="$TMP/rootlink" bash "$SCRIPT")
present "symlinked root is traversed" "dirty|$TMP/rootlink/dirty|" "$OUT_LINK"

exit $fail
