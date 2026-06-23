#!/usr/bin/env bash
# Verify a ship-it init produced the right files in the right places: the config
# (present + schema-valid), the worktree prepare script (present + executable, when
# referenced), and each generated doc-job skill passed as an argument (a real
# directory .claude/skills/<slug>/SKILL.md whose top-level `name` and docs.jobs `ref`
# both equal the slug, declaring a top-level `allowed-tools`). Warns on empty/orphan
# skill dirs, e.g. a folder stranded by an earlier run that chose a different name.
#
# Usage: verify-init.sh [generated-skill-slug ...]
#   Run at the end of init with the slug(s) it generated this run (none if every doc
#   used a built-in). Runnable standalone any time after.
# Exit 0 = ok (warnings allowed), 1 = one or more FAILs.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

fails=0
warns=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
warn() { printf '  warn  %s\n' "$1"; warns=$((warns + 1)); }

echo "ship-it init verification (root: $root)"

# 1. config present + schema-valid
cfg=""
for c in "$root/.claude/ship-it/config.json" "$root/ship-it.config.json" "$root/.claude/ship-it.config.json"; do
  [ -f "$c" ] && { cfg="$c"; break; }
done
if [ -z "$cfg" ]; then
  fail "config not found (expected .claude/ship-it/config.json)"
else
  pass "config present: ${cfg#"$root"/}"
  if bash "$here/validate-config.sh" "$cfg" >/dev/null 2>&1; then
    pass "config conforms to the schema"
  else
    fail "config does not conform (run scripts/validate-config.sh ${cfg#"$root"/})"
  fi
fi

# 2. worktree prepare script (when worktree.prepare references a .sh file)
if [ -n "$cfg" ]; then
  prep="$(jq -r '.worktree.prepare // empty' "$cfg" | awk '{print $1}')"
  if [ -n "$prep" ] && [ "${prep##*.}" = "sh" ]; then
    if [ -f "$root/$prep" ]; then
      pass "worktree prepare present: $prep"
      [ -x "$root/$prep" ] || fail "worktree prepare is not executable: $prep (chmod +x)"
    else
      fail "worktree.prepare references a missing file: $prep"
    fi
  fi
fi

# 3. each generated doc-job skill passed as an argument
for slug in "$@"; do
  dir="$root/.claude/skills/$slug"
  skill="$dir/SKILL.md"
  [ -f "$root/.claude/skills/$slug.md" ] && fail "skill is a flat file .claude/skills/$slug.md (must be $slug/SKILL.md)"
  if [ ! -d "$dir" ]; then
    fail "generated skill dir missing: .claude/skills/$slug/"
    continue
  fi
  if [ ! -f "$skill" ]; then
    fail "generated skill has no SKILL.md: .claude/skills/$slug/"
    continue
  fi
  pass "generated skill present: .claude/skills/$slug/SKILL.md"
  nm="$(awk -F': *' '/^name:/{print $2; exit}' "$skill")"
  [ "$nm" = "$slug" ] || fail "front-matter name '$nm' != slug '$slug' in $slug/SKILL.md"
  awk '/^allowed-tools:/{ok=1} END{exit !ok}' "$skill" || fail "$slug/SKILL.md: allowed-tools must be a top-level key (not nested under metadata)"
  if [ -n "$cfg" ]; then
    jq -e --arg r "$slug" '[.docs.jobs[]?.ref] | index($r)' "$cfg" >/dev/null 2>&1 || fail "generated skill '$slug' is not referenced by any docs.jobs[].ref"
  fi
done

# 4. orphan/empty skill dirs (warn only)
if [ -d "$root/.claude/skills" ]; then
  shopt -s nullglob
  for d in "$root"/.claude/skills/*/; do
    [ -f "${d}SKILL.md" ] || warn "empty skill dir, no SKILL.md (stale? rmdir it): .claude/skills/$(basename "$d")/"
  done
  shopt -u nullglob
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "PASS: init artifacts verified ($warns warning(s))."
  exit 0
fi
echo "FAIL: $fails problem(s), $warns warning(s). Fix the FAILs above."
exit 1
