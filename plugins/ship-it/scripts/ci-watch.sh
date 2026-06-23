#!/usr/bin/env bash
# Watch a pull request's CI to completion and report PASS/FAIL, dumping the
# failed-step logs on failure. The ship-it `ci-fix` skill runs this; on FAIL it
# diagnoses and fixes the cause in the PR's branch, then re-runs this. Exit 0 =
# all checks passed (or none to run); 1 = at least one check failed.
#
# Watch only: this script never edits code. Fixing is the skill's job, and it
# must fix the cause, never weaken or skip a check to go green.
#
# CI is usually capped at a few minutes. If an outer timeout kills this while CI
# is still pending, run it again (gh re-attaches to the in-flight run).
#
# Usage: ci-watch.sh <pr-number | url | branch>
set -uo pipefail

pr="${1:?usage: ci-watch.sh <pr-number | url | branch>}"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

gh pr checks "$pr" -R "$REPO" --watch --interval 20 >/dev/null 2>&1 || true

fails="$(gh pr checks "$pr" -R "$REPO" --json name,bucket -q '[.[] | select(.bucket=="fail")] | length' 2>/dev/null || echo 0)"
if [ "${fails:-0}" -eq 0 ]; then
  echo "CI PASS for PR #$pr"
  exit 0
fi

echo "CI FAIL for PR #$pr ($fails failing check(s)):"
gh pr checks "$pr" -R "$REPO" --json name,bucket,link -q '.[] | select(.bucket=="fail") | "  - \(.name)  \(.link)"' 2>/dev/null || true

branch="$(gh pr view "$pr" -R "$REPO" --json headRefName -q .headRefName 2>/dev/null || echo "")"
if [ -n "$branch" ]; then
  run_id="$(gh run list -R "$REPO" --branch "$branch" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || echo "")"
  if [ -n "$run_id" ]; then
    echo "=== failed step logs (run $run_id, tail) ==="
    gh run view "$run_id" -R "$REPO" --log-failed 2>/dev/null | tail -200 || true
  fi
fi
exit 1
