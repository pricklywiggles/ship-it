#!/usr/bin/env bash
# Validate a ship-it.config against the schema in config.schema.jq and report precise,
# fixable errors. Built for an edit -> validate -> fix loop: run it after writing or
# editing the config and fix every error until it prints OK. Dependency-free beyond jq
# (already required by load-config.sh). Exit 0 = conforms, 1 = errors, 2 = no config.
#
# Usage:
#   validate-config.sh [path-to-config]   # defaults to the repo's ship-it.config.json
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
schema="$here/config.schema.jq"

cfg="${1:-}"
if [ -z "$cfg" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  for c in "$root/.claude/ship-it/config.json" "$root/ship-it.config.json" "$root/.claude/ship-it.config.json"; do
    if [ -f "$c" ]; then cfg="$c"; break; fi
  done
fi
if [ -z "$cfg" ] || [ ! -f "$cfg" ]; then
  echo "validate-config: no config found; pass a path" >&2
  exit 2
fi

if ! jq -e . "$cfg" >/dev/null 2>&1; then
  echo "INVALID: $cfg is not valid JSON" >&2
  jq . "$cfg" 2>&1 | head -3 >&2
  exit 1
fi

result="$(jq -f "$schema" "$cfg")"
nerr="$(printf '%s' "$result" | jq '.errors | length')"
nwarn="$(printf '%s' "$result" | jq '.warnings | length')"

if [ "$nwarn" -gt 0 ]; then
  printf '%s' "$result" | jq -r '.warnings[] | "  warning: \(.)"'
fi

if [ "$nerr" -gt 0 ]; then
  echo "INVALID: $cfg ($nerr error(s)):" >&2
  printf '%s' "$result" | jq -r '.errors[] | "  - \(.)"' >&2
  echo "Fix the above and re-run: $(basename "$0") $cfg" >&2
  exit 1
fi

echo "OK: $cfg conforms to the ship-it config schema ($nwarn warning(s))"
exit 0
