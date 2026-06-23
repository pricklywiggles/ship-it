#!/usr/bin/env bash
# Pre-create lane-head worktrees for a ship-it batch, branch checked out, and (if a
# prepare command is given) made runnable. Reads one line per worktree on stdin:
#   <id>|<branch>|<base>
# Creates worktrees sequentially: concurrent `git worktree add` races the index lock.
#
# Options:
#   --root <dir>       worktree root (default: <repo>/.claude/worktrees)
#   --prepare "<cmd>"  run per worktree to make it runnable; {wt} and {main} are
#                      substituted (e.g. the project's install + setup). Optional.
#
# Usage (run from inside the repo):
#   setup-worktrees.sh --prepare ".claude/ship-it/prepare-worktree.sh {wt} {main}" <<'EOF'
#   issue-1|you/issue-1-slug|main
#   issue-2|you/issue-2-slug|main
#   EOF
set -euo pipefail

MAIN="$(git rev-parse --show-toplevel)"
DEFAULT_BRANCH="$(git -C "$MAIN" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
WT_ROOT="$MAIN/.claude/worktrees"
PREPARE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root) WT_ROOT="$2"; shift 2 ;;
    --prepare) PREPARE="$2"; shift 2 ;;
    -h|--help) rg '^#' "$0" | rg -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
case "$WT_ROOT" in /*) ;; *) WT_ROOT="$MAIN/$WT_ROOT" ;; esac

while IFS='|' read -r id branch base; do
  [ -n "${id:-}" ] || continue
  base="${base:-$DEFAULT_BRANCH}"
  wt="$WT_ROOT/$id"
  if [ -d "$wt" ]; then
    echo "exists: $wt"
  elif git -C "$MAIN" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$MAIN" worktree add "$wt" "$branch" >/dev/null
  else
    git -C "$MAIN" worktree add -b "$branch" "$wt" "$base" >/dev/null
  fi
  if [ -n "$PREPARE" ]; then
    cmd="${PREPARE//\{wt\}/$wt}"; cmd="${cmd//\{main\}/$MAIN}"
    # Prepare runs IN the worktree so a plain install lands there; {wt}/{main} are
    # still substituted for prepare commands that need the explicit paths.
    ( cd "$wt" && eval "$cmd" )
    # Keep prepare's artifacts out of git's view so they never surface as untracked and
    # leak into a feature diff. The worktree is fresh off a clean base, so anything
    # untracked after prepare is prepare's doing (linked sidecars, generated files).
    excl="$(git -C "$MAIN" rev-parse --git-path info/exclude)"
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      grep -qxF "/$p" "$excl" 2>/dev/null || printf '/%s\n' "$p" >>"$excl"
    done < <(git -C "$wt" ls-files --others --exclude-standard)
  fi
  echo "ready: $wt -> $(git -C "$wt" rev-parse --abbrev-ref HEAD)"
done

echo "=== worktrees ==="
git -C "$MAIN" worktree list
