---
name: open-pr
description: Push a finished branch and open its pull request with a complete, QA-ready body. Use for "open a PR for my branch", "push this and open the PR", "finalize this work-unit". Builds the PR body from ship-it.config prTemplate: a Summary, a tracker link, and a two-part Verification (automated checks run, plus a followable manual-QA checklist). The finalize stage of the ship-it orchestrator, and usable standalone on the current branch. Not for implementing (fix-one-issue), reviewing (review-and-address), or CI (ci-fix); it assumes the branch is already final and committed.
allowed-tools: Bash, Read, Grep, Glob
---

# open-pr: push the branch, open a complete PR

Take a finished branch and open its PR with a body a reviewer and a QA tester can actually act on. The finalize stage: it pushes what is already committed and opens the PR. It does not implement, apply review, or edit code; earlier stages did that.

## 1. Resolve the target

- **Orchestrated**: you are given a work-unit (`id`, `title`, `desc`, `branch`, `base`/`prBase`, `worktree`, `url`). Operate inside the worktree; `prBase` is the PR base (the parent branch for a stacked child, else `mainBranch`).
- **Standalone**: no work-unit given. Use the current branch (or a named one) against `repo.mainBranch`. Derive the title and summary from the branch's diff and commit messages.

## 2. Read config

Load the resolved config via `${CLAUDE_PLUGIN_ROOT}/scripts/load-config.sh`; read with `jq`:
- `repo.mainBranch` and the repo slug (`gh repo view --json nameWithOwner -q .nameWithOwner`),
- `prTemplate` (the body shape: `sections` + the `verification` rule),
- `houseRules` / `safety` (carried into the body: no em dashes, no AI attribution, plus any privacy rail).

## 3. Confirm the branch is final

The branch should already be implemented, comment-cleaned, reviewed, and committed by the earlier stages (or, standalone, by you before invoking this). Confirm there are commits to ship: `git -C <worktree> log <prBase>..HEAD --oneline`. If nothing is ahead of the base, say so and stop, there is no PR to open.

## 4. Push

```bash
git -C <worktree> push -u origin <branch>
```
Retry once on a transient failure.

## 5. Build the PR body from `prTemplate`

Read the branch diff (`git -C <worktree> diff <prBase>...HEAD`) to ground the body. Produce the `prTemplate.sections` (default: Summary, the tracker link, Verification):

- **Summary**: what changed and why, scoped to this diff.
- **Tracker link**: if the work-unit has an `id`/`url`, the link line that lets the merge auto-close the issue (e.g. a `## Linear` line linking `id` to `url`). Omit for ad-hoc work.
- **Verification** (the load-bearing section): expand `prTemplate.verification` into **two parts**.
  1. **Automated (done)**: the `verify` checks you actually ran and their result (e.g. biome, tsc, plus build/smoke when relevant).
  2. **Manual QA**: a GitHub checkbox list (`- [ ] ...`) of concrete steps a QA tester follows to verify the change in the running app, each step stating the action and the expected result, with a fenced code block of the exact commands (shell, queries, curl, devtools snippets) wherever a step needs them. Never write "left to the reviewer". If the change has no visual surface (pure API, types, ingest), give functional steps instead (curl with expected status, a query or smoke test). Honor every `safety` rail: keep private/personal values out of the PR (prefer counts, status codes, positions).

No em dashes and no AI attribution anywhere in the title or body.

## 6. Open the PR

```bash
cd <worktree> && gh pr create -R <repo> --base <prBase> --head <branch> --title "<concise imperative title>" --body "<body>"
```
Retry once on failure. Read the resulting PR URL and number.

## Output

- **Standalone**: the PR URL plus a one-line note of what it covers.
- **Called by the orchestrator**: a structured result, `{ issueId, pushed, prUrl, prNumber, finalSummary, verification }`. If push or PR creation fails after one retry, return `pushed: false`, `prUrl: ""`, and the error in `notes`, so the batch degrades rather than crashing.

## Hard rules

- Honor `houseRules` + `safety` in the title and body: no em dashes, no AI attribution, no private values.
- Do not edit code or apply review findings here, that is `review-and-address`. Push what is committed and open the PR.
- `prBase` is the parent branch for a stacked child; GitHub auto-retargets the PR to `mainBranch` once the parent merges.
