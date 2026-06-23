#!/usr/bin/env bash
# Watch a batch's feature PRs until they are all merged (or closed), then run a
# reconcile command. The generic in-session merge-watcher for ship-it author-reconcile
# doc jobs: once the PRs are terminal it runs --reconcile (e.g. the openspec-archive
# helper), which opens the batched docs PR. On timeout it prints the reconcile command.
#
# In-session only: it lives as long as the session that launched it. Close the session
# and you run the reconcile yourself, the same fallback as a timeout.
#
# A PR is terminal when MERGED or CLOSED, so one rejected PR will not hang the wait.
#
# Usage (normally via run_in_background):
#   watch-merges.sh --prs 211,212,213 --reconcile '<command>'
#   watch-merges.sh --prs 211 --reconcile '<command>' --timeout-min 360 --interval-min 15
#   watch-merges.sh --prs 211,212 --dry-run    # poll once, report, no wait, no reconcile
set -uo pipefail

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
PRS=""; RECONCILE=""; TIMEOUT_MIN=360; INTERVAL_MIN=15; DRYRUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prs) PRS="$2"; shift 2 ;;
    --reconcile) RECONCILE="$2"; shift 2 ;;
    --timeout-min) TIMEOUT_MIN="$2"; shift 2 ;;
    --interval-min) INTERVAL_MIN="$2"; shift 2 ;;
    --dry-run) DRYRUN=1; shift ;;
    -h|--help) rg '^#' "$0" | rg -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$PRS" ] || { echo "need --prs <csv of PR numbers>" >&2; exit 2; }

IFS=',' read -r -a pr_list <<< "$PRS"
pr_state() { gh pr view "$1" -R "$REPO" --json state -q .state 2>/dev/null || echo "UNKNOWN"; }

# Sets M (merged), T (terminal), N (total), OPEN (string of still-open prs).
poll() {
  M=0; T=0; N=0; OPEN=""
  local st
  for n in "${pr_list[@]}"; do
    N=$((N + 1))
    st="$(pr_state "$n")"
    case "$st" in
      MERGED) M=$((M + 1)); T=$((T + 1)) ;;
      CLOSED) T=$((T + 1)) ;;
      *) OPEN="$OPEN #$n($st)" ;;
    esac
  done
}

if [ "$DRYRUN" -eq 1 ]; then
  poll
  echo "merged=$M closed=$((T - M)) open=$((N - T)) total=$N"
  [ -n "$OPEN" ] && echo "open:$OPEN"
  exit 0
fi

deadline=$(( $(date +%s) + TIMEOUT_MIN * 60 ))
while true; do
  poll
  echo "[$(date +%H:%M)] merged=$M terminal=$T/$N"
  if [ "$T" -eq "$N" ]; then
    if [ "$M" -gt 0 ] && [ -n "$RECONCILE" ]; then
      echo "all PRs terminal; running reconcile"
      eval "$RECONCILE"
    else
      echo "nothing to reconcile (none merged, or no --reconcile given)"
    fi
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "TIMEOUT after ${TIMEOUT_MIN}m; still open:${OPEN:- none}"
    [ -n "$RECONCILE" ] && { echo "Run the reconcile yourself once they merge:"; echo "  $RECONCILE"; }
    exit 3
  fi
  sleep $(( INTERVAL_MIN * 60 ))
done
