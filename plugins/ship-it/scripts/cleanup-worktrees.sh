#!/usr/bin/env bash
# Clean up ship-it batch worktrees. Safe by default: refuses to remove a worktree
# unless its branch's PR is MERGED and the worktree has no uncommitted tracked
# changes. --force overrides. For each target it removes the worktree, deletes the
# local branch, deletes the remote branch if it still exists, and prunes.
#
# Options:
#   --root <dir>     worktree root (default: <repo>/.claude/worktrees)
#   --all-merged     every worktree under the root whose PR is merged
#   --force          skip the merged/clean checks (deletes unmerged work)
#
# Usage (run from inside the repo):
#   cleanup-worktrees.sh <id>            # one (the worktree dir name)
#   cleanup-worktrees.sh <id> <id>       # several
#   cleanup-worktrees.sh --all-merged    # sweep merged ones
set -euo pipefail

MAIN="$(git rev-parse --show-toplevel)"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
WT_ROOT=""; FORCE=0; ALL=0; ids=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) WT_ROOT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --all-merged) ALL=1; shift ;;
    -h|--help) rg '^#' "$0" | rg -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ids+=("$1"); shift ;;
  esac
done
WT_ROOT="${WT_ROOT:-$MAIN/.claude/worktrees}"
case "$WT_ROOT" in /*) ;; *) WT_ROOT="$MAIN/$WT_ROOT" ;; esac
CLEANED=0; FAILED=()

branch_for_worktree() { git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null; }
pr_state_for_branch() { gh pr list -R "$REPO" --head "$1" --state all --limit 1 --json state -q '.[0].state' 2>/dev/null; }

cleanup_one() {
  local id="$1" wt="$WT_ROOT/$1" br state dirty
  if ! git -C "$MAIN" worktree list --porcelain | rg -qx "worktree $wt"; then echo "skip $id: no worktree at $wt"; return 0; fi
  br="$(branch_for_worktree "$wt")"
  [ -n "$br" ] || { echo "skip $id: could not resolve a branch for $wt (detached HEAD?)"; return 0; }
  if [ "$FORCE" -ne 1 ]; then
    dirty="$(git -C "$wt" status --porcelain --untracked-files=no)"
    if [ -n "$dirty" ]; then echo "REFUSE $id: worktree has uncommitted tracked changes. Commit/stash or pass --force." >&2; return 1; fi
    state="$(pr_state_for_branch "$br")"
    if [ "$state" != "MERGED" ]; then echo "REFUSE $id: PR for $br is '${state:-none found}', not MERGED. Pass --force to override." >&2; return 1; fi
    echo "ok $id: PR is MERGED, worktree clean -> removing"
  else
    echo "force $id: skipping merged/clean checks"
  fi
  if ! git -C "$MAIN" worktree remove --force "$wt"; then echo "FAIL $id: git worktree remove exited non-zero" >&2; FAILED+=("$id"); return 1; fi
  git -C "$MAIN" branch -D "$br" 2>/dev/null || echo "    (local branch $br already gone)"
  if git -C "$MAIN" ls-remote --exit-code --heads origin "$br" >/dev/null 2>&1; then git -C "$MAIN" push origin --delete "$br"; else echo "    (remote branch $br already gone)"; fi
  echo "done $id"; CLEANED=$((CLEANED + 1))
}

git -C "$MAIN" worktree prune
if [ "$ALL" -eq 1 ]; then
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    cleanup_one "$(basename "$wt")" || true
  done < <(git -C "$MAIN" worktree list --porcelain | rg '^worktree ' | sed 's/^worktree //' | rg -F "$WT_ROOT/")
fi
for raw in "${ids[@]:-}"; do
  [ -n "$raw" ] || continue
  cleanup_one "$raw" || true
done
if [ "$ALL" -ne 1 ] && [ "${#ids[@]}" -eq 0 ]; then echo "Nothing to do. Pass a worktree id or --all-merged. See --help." >&2; exit 2; fi

git -C "$MAIN" worktree prune
echo "=== remaining worktrees ==="
git -C "$MAIN" worktree list
[ "${#FAILED[@]}" -gt 0 ] && echo "FAILED: ${FAILED[*]} (not removed)" >&2 || true
