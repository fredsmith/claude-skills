#!/usr/bin/env bash
# scan-repos.sh — walk configured roots; emit one line per local-git finding.
#   <type>|<repo_path>|<owner/repo>|<branch>|<detail>
#   type ∈ dirty | ahead | branch-no-upstream
set -uo pipefail

resolve_roots() {
  if   [ -n "${SHUTDOWN_REPO_ROOTS:-}" ]; then printf '%s' "$SHUTDOWN_REPO_ROOTS"
  elif [ -n "${project_dirs:-}" ];        then printf '%s' "$project_dirs"
  fi
}

parse_owner_repo() { # $1=repo dir → owner/repo for github origins, else empty
  local url
  url=$(git -C "$1" remote get-url origin 2>/dev/null) || return 0
  case "$url" in
    *github.com[:/]*)
      url=${url#*github.com}; url=${url#:}; url=${url#/}; url=${url%.git}
      printf '%s' "$url" ;;
  esac
}

scan_repo() { # $1 = repo working dir
  local repo=$1 ownerrepo branch n ahead
  branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null) || branch=""
  ownerrepo=$(parse_owner_repo "$repo")

  n=$(git -C "$repo" status --porcelain 2>/dev/null | grep -c .)
  if [ "$n" -gt 0 ]; then
    printf 'dirty|%s|%s|%s|%s\n' "$repo" "$ownerrepo" "$branch" "$n"
  fi

  git -C "$repo" rev-parse HEAD >/dev/null 2>&1 || return 0
  [ -n "$branch" ] || return 0

  if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    ahead=$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
    if [ "$ahead" -gt 0 ]; then
      printf 'ahead|%s|%s|%s|%s\n' "$repo" "$ownerrepo" "$branch" "$ahead"
    fi
  else
    printf 'branch-no-upstream|%s|%s|%s|\n' "$repo" "$ownerrepo" "$branch"
  fi
}

main() {
  local roots root repo gitdir
  roots=$(resolve_roots)
  if [ -z "$roots" ]; then
    echo "scan-repos.sh: no repo roots configured. Set SHUTDOWN_REPO_ROOTS (colon-separated) or export \$project_dirs." >&2
    return 2
  fi
  local IFS=:
  for root in $roots; do
    case "$root" in "~"*) root="${HOME}${root#\~}";; esac
    [ -n "$root" ] && [ -d "$root" ] || continue
    while IFS= read -r gitdir; do
      repo=$(dirname "$gitdir")
      scan_repo "$repo"
    done < <(find -L "$root" -maxdepth 4 -name .git \( -type d -o -type f \) -prune 2>/dev/null)
  done
}

main "$@"
