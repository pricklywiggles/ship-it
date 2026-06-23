#!/usr/bin/env bash
# Reconcile shipped OpenSpec changes into the canonical specs, post-merge. This is
# the openspec author-reconcile doc job's reconcile step. Merged-gated: it archives
# only changes whose feature PR has merged (a change folder reaches the default
# branch only when its PR merges), then opens one batched archive PR.
#
# Docs-only and runs in a throwaway worktree, so the repo's pre-commit/pre-push hooks
# are skipped with --no-verify (there are no installed deps there and nothing to lint).
#
# Usage (run from inside the repo):
#   openspec-archive.sh add-foo move-bar     # specific change ids
#   openspec-archive.sh --all-shipped        # every merged, un-archived change
#   openspec-archive.sh --dry-run --all-shipped
#   openspec-archive.sh --no-pr add-foo
set -euo pipefail

MAIN="$(git rev-parse --show-toplevel)"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
DEFAULT_BRANCH="$(git -C "$MAIN" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

ALL=0; DRYRUN=0; NOPR=0; names=()
for a in "$@"; do
  case "$a" in
    --all-shipped) ALL=1 ;;
    --dry-run) DRYRUN=1 ;;
    --no-pr) NOPR=1 ;;
    -h|--help) rg '^#' "$0" | rg -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) names+=("$a") ;;
  esac
done

git -C "$MAIN" fetch --quiet origin "$DEFAULT_BRANCH"
ref="origin/$DEFAULT_BRANCH"
changes_on_main() { git -C "$MAIN" ls-tree -d --name-only "$ref:openspec/changes" 2>/dev/null | rg -v '^archive$'; }
is_on_main()  { changes_on_main | rg -qx -- "$1"; }
is_archived() { git -C "$MAIN" ls-tree -d --name-only "$ref:openspec/changes/archive" 2>/dev/null | rg -q -- "-$1$"; }

targets=()
if [ "$ALL" -eq 1 ]; then while IFS= read -r n; do [ -n "$n" ] && targets+=("$n"); done < <(changes_on_main); fi
for n in "${names[@]:-}"; do [ -n "$n" ] && targets+=("$n"); done
if [ "${#targets[@]}" -eq 0 ]; then echo "Nothing to archive. Pass change ids or --all-shipped. See --help." >&2; exit 2; fi

eligible=(); skipped_unmerged=(); skipped_archived=()
for n in "${targets[@]}"; do
  if is_archived "$n"; then skipped_archived+=("$n")
  elif is_on_main "$n"; then eligible+=("$n")
  else skipped_unmerged+=("$n")
  fi
done
echo "=== archive plan (default branch: $DEFAULT_BRANCH) ==="
echo "eligible (merged):      ${eligible[*]:-(none)}"
echo "skipped (not merged):   ${skipped_unmerged[*]:-(none)}"
echo "skipped (already done): ${skipped_archived[*]:-(none)}"
if [ "${#eligible[@]}" -eq 0 ]; then echo "No merged, un-archived changes to archive."; exit 0; fi
if [ "$DRYRUN" -eq 1 ]; then echo "(dry run: nothing archived)"; exit 0; fi

ts="$(date +%Y%m%d-%H%M%S)"
branch="chore/openspec-archive-$ts"
tmp="$MAIN/.claude/worktrees/_archive-$ts"
git -C "$MAIN" worktree add -b "$branch" "$tmp" "$ref" >/dev/null
cleanup() { git -C "$MAIN" worktree remove --force "$tmp" 2>/dev/null || true; }
trap cleanup EXIT

archived=()
for n in "${eligible[@]}"; do
  ( cd "$tmp" && openspec archive "$n" -y )
  archived+=("$n")
  echo "archived: $n"
done

git -C "$tmp" add -A
git -C "$tmp" commit -q --no-verify -m "chore(openspec): archive shipped changes (${archived[*]})"
git -C "$tmp" push --no-verify -u origin "$branch" >/dev/null
if [ "$NOPR" -eq 1 ]; then echo "pushed branch $branch (no PR opened; --no-pr)"; exit 0; fi

body="Archive the OpenSpec changes shipped in the last batch, reconciling their delta specs into openspec/specs/. Docs only, no behavior change.

Archived:
$(printf -- '- %s\n' "${archived[@]}")"
pr_url="$(cd "$tmp" && gh pr create -R "$REPO" --base "$DEFAULT_BRANCH" --head "$branch" \
  --title "Archive shipped OpenSpec changes (${archived[*]})" --body "$body")"
echo "archive PR: $pr_url"
