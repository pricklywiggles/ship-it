---
name: review-and-address
description: Review a branch or the current diff with the project's configured reviewers run in parallel, merge their findings, and apply the warranted ones. Use for "review my changes", "review this PR/branch", "run the reviewers on the current diff with main", "review and fix the warranted feedback". Runs every reviewer in ship-it.config review.reviewers (e.g. pr-review-toolkit, vercel-react-best-practices). Also the review stage of the ship-it orchestrator. Not for watching or fixing CI (use ci-fix) or comment-only cleanup (use comment-cleanup).
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, Skill
---

# review-and-address: fan out reviewers, merge findings, apply warranted

Review a diff with every configured reviewer in parallel, merge the findings, and (when asked or configured) apply the warranted ones. Reviewers only read; the one write step is the address.

## 1. Resolve the target and the diff

- **PR, branch, or worktree given** (an argument, or passed by the ship-it orchestrator as a work-unit): review its diff, `git diff <base>...HEAD` (base defaults to `repo.mainBranch`, usually `main`).
- **Nothing given** (standalone): review the current changes, the working-tree diff against `main`, or the current branch's diff with `main`. This is the "current diff with main" case.
- Note the changed files; reviewers and the address step operate only on this diff.

## 2. Read config, else defaults

Load the resolved config via `${CLAUDE_PLUGIN_ROOT}/scripts/load-config.sh` (defaults applied, `@FILE` refs inlined); read keys with `jq`:
- `review.reviewers` (the list; if absent, default to a single `pr-review-toolkit` agent reviewer),
- `review.applyWarranted` (default: true in the orchestrator; for a standalone run, report unless asked to apply),
- `verify`, `houseRules`, `safety` (for the address step).

## 3. Fan out the reviewers (parallel, read-only)

Run every reviewer in `review.reviewers` over the diff concurrently: spawn one subagent per reviewer in a single message so they run in parallel. Each reviews ONLY the diff and returns structured findings. Dispatch by `kind`:
- **`agent`**: spawn the Agent tool with `subagent_type` = the reviewer's `ref` (e.g. `pr-review-toolkit:code-reviewer`), prompting it to review the diff and return findings.
- **`skill`**: spawn a general subagent that invokes the Skill tool with the reviewer's `ref` (e.g. `vercel-react-best-practices`) scoped to the diff, and return its findings.
- **`command`**: run the reviewer's `ref` via Bash against the changed files; parse its output into findings.

If a reviewer is not installed, skip it and note it (do not fail the whole review). If `review.reviewers` is empty, there is nothing to review; say so and stop.

Each finding: `{ severity, file, location?, issue, recommendation, reviewer }`.

## 4. Merge and de-duplicate

Combine all reviewers' findings. Collapse items that flag the same file and location into one, keeping the highest severity and listing every reviewer that raised it. Order by severity.

## 5. Address (apply the warranted ones)

Apply only when `review.applyWarranted` is true, or when this run was explicitly asked to fix:
- Apply real, in-scope fixes: all blocker / high / medium, plus clearly-correct low / nit. Skip out-of-scope, incorrect, or noise items and record why.
- Edit only within the target working copy and the diff's scope.
- Re-verify with the `verify` commands; fix anything you broke.
- Commit (concise imperative subject; honor `houseRules`: no em dashes, no AI attribution).

A report-only run (standalone, not asked to fix) stops after the merged findings; it does not edit.

## Hard rules

Reviewers are read-only. The address step applies only genuine, correct, in-scope fixes, never a change that just silences a finding. Stay within the diff. When run by the orchestrator, run non-interactively: apply per `applyWarranted` and record skips rather than asking.

## Output

- **Standalone**: the merged findings (severity, file, issue, which reviewers), and, if you applied, what you applied and what you skipped with reasons.
- **Called by the orchestrator**: a structured result, `{ findings: [...], applied: [...], skipped: [...] }`, for finalize to push.
