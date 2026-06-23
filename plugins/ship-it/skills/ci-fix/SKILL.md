---
name: ci-fix
description: Watch a pull request's CI to completion and fix any failures in its branch, bounded and cause-only. Use when CI is red on a PR or branch and you want it driven to green ("fix the CI on this PR", "CI is failing, sort it out", "watch the checks and fix what breaks"). Acts on a PR number, URL, or branch you name, or the current branch's open PR if you name none. Also called by the ship-it orchestrator's post-PR phase, one watcher per PR. Not for reviewing code quality (use a reviewer) or fixing local errors with no PR/CI (just fix those directly).
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# ci-fix: watch CI and fix failures

Drive a pull request's CI to green by watching it and fixing the cause of any failure in the PR's branch. Bounded, cause-only, and it never games a check.

## 1. Resolve the target

- **PR number, URL, or branch given** (an argument, or passed by the ship-it orchestrator as a work-unit carrying `prNumber` / `branch` / `worktree`): use it.
- **Nothing given** (standalone): resolve the current branch's open PR with `gh pr view --json number,headRefName,url`. If the branch has no PR, say so and stop, there is nothing to watch.
- The working copy to fix in is the work-unit's `worktree` when set, otherwise the current checkout.

## 2. Read config, else defaults

Load the resolved config: `config="$("${CLAUDE_PLUGIN_ROOT}/scripts/load-config.sh")"` (it locates `ship-it.config.json`, applies defaults, and inlines `@FILE` refs). Read keys with `jq`:
- `ci.fixAttempts` (default 2),
- `verify` (commands to re-run after a fix; if absent, detect from package.json, e.g. lint + typecheck),
- `houseRules` / `safety` (carry these into every edit and commit: no em dashes, no AI attribution, plus any project rails).

No config means use the defaults and proceed.

## 3. Watch, then fix

1. **Watch** (give the Bash call the 10-minute max timeout; if it is killed while CI is still pending, run it again):
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/ci-watch.sh" <pr>
   ```
   Exit 0 = all checks passed: report green, done. Exit 1 = at least one check failed, with the failing checks and the failed-step logs on stdout.

2. **On failure, fix the cause** (bounded to `ci.fixAttempts`):
   - Read the dumped logs; diagnose in the target working copy.
   - Make the smallest change that fixes the real cause; match surrounding style.
   - Re-verify locally where feasible: the `verify` commands, plus the specific failing command when you can run it. Some checks (a full build, a broad smoke suite) may not reproduce cleanly in a worktree, so it is fine to fix from the logs and let the pushed CI re-verify.
   - Commit on the target branch (concise imperative subject; honor `houseRules`).
   - Push. CI cancel-in-progress supersedes the prior run.
   - Re-run `ci-watch.sh`. Repeat until green or the attempt budget is spent.

3. **Stop and escalate** when: still red after `ci.fixAttempts`; or the failure is infrastructure or flaky, not your diff; or the only way to green would weaken a check. Report the diagnosis and what you tried.

## Hard rule

Never go green by deleting or skipping a test, loosening an assertion, or `@ts-ignore`-ing a real type error. Fix the cause or surface it. All edits stay inside the target working copy. When run by the orchestrator, run non-interactively: escalate rather than ask.

## Output

- **Standalone**: tell the user the outcome, green (and what you fixed) or escalated (the diagnosis and remaining failures).
- **Called by the orchestrator**: return a structured result, `{ pr, status: "green" | "escalated", attempts, fixed: [...], remaining: [...] }`.
