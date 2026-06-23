#!/usr/bin/env bash
# Locate, parse, and resolve this project's ship-it.config, printing it as JSON on
# stdout: defaults applied, and @FILE string references inlined (e.g. houseRules:
# "@AGENTS.md" becomes the file's text). ship-it skills load it once and read keys
# with jq, instead of locating and parsing the config themselves.
#
#   config="$("${CLAUDE_PLUGIN_ROOT}/scripts/load-config.sh")"
#   echo "$config" | jq -r '.verify[]'
#   echo "$config" | jq -r '.review.reviewers[].ref'
#
# Searched (first wins): ./.claude/ship-it/config.json, ./ship-it.config.json,
# ./.claude/ship-it.config.json. With no config file it prints the defaults and warns
# on stderr, so callers always get usable JSON.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

defaults='{
  "repo": { "mainBranch": "main", "mergeStrategy": "squash" },
  "source": { "default": "tracker" },
  "safety": [],
  "verify": [],
  "worktree": { "enabled": true, "root": ".claude/worktrees" },
  "concurrency": { "maxLanes": 4 },
  "planning": { "enabled": true, "postBack": true, "depth": "adaptive" },
  "review": { "reviewers": [], "applyWarranted": true },
  "ci": { "watch": true, "fixAttempts": 2 },
  "docs": { "enabled": true, "jobs": [] }
}'

cfg=""
for p in "$ROOT/.claude/ship-it/config.json" "$ROOT/ship-it.config.json" "$ROOT/.claude/ship-it.config.json"; do
  [ -f "$p" ] && { cfg="$p"; break; }
done

if [ -z "$cfg" ]; then
  echo "ship-it: no ship-it.config.json found; using defaults (run ship-it:init to create one)" >&2
  echo "$defaults"
  exit 0
fi

# Deep-merge defaults under the file (file wins; nested objects merge, arrays replace).
merged="$(jq -s '.[0] * .[1]' <(echo "$defaults") "$cfg")"

# Inline an @FILE reference in houseRules (the common case).
hr="$(echo "$merged" | jq -r '.houseRules // empty')"
if [ "${hr#@}" != "$hr" ]; then
  f="$ROOT/${hr#@}"
  [ -f "$f" ] && merged="$(echo "$merged" | jq --rawfile content "$f" '.houseRules = $content')"
fi

echo "$merged"
