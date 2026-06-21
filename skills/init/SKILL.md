---
name: init
description: Configure ship-it for this project. Detects the package manager, verify command, CI system, issue tracker, doc tools, and installed reviewers from the repo, asks only for what it cannot infer, then writes ship-it.config and generates doc-job skills for any docs without a built-in. Use to set up ship-it on a new project ("set up ship-it here", "configure ship-it", "ship-it init") or to reconfigure. Run once per project before using the ship-issues orchestrator.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, Skill, ToolSearch
---

# init: configure ship-it for this project

Produce a `ship-it.config` that adapts the generic engine to this project. Detect first, ask only for the gaps, generate doc-job skills for anything without a built-in. This is the one place all the interactive questions live; everything downstream runs from the config non-interactively.

The full config schema is in the plugin's `CONTRACTS.md`; the keys are summarized in step 5.

## 0. Explain the plan first

Before touching anything, tell the user what init will do and in what order, so they know what is coming and that it is safe. Something like:

> I'll set up ship-it for this project in five steps: (1) **detect** your setup (package manager, verify command, CI, issue tracker, doc tools, installed reviewers) by reading the repo, this is read-only; (2) **ask** you only what I cannot infer, with the reason for each question; (3) **check prerequisites** (tracker access, `gh` auth, doc-tool binaries); (4) **generate** a small doc-job skill for any doc you keep that has no built-in; (5) **write** `ship-it.config.json`. The only things I create are that config and any generated doc-job skills; nothing else is changed.

Keep it to a short preview, then proceed to detection.

## 1. Detect (read-only)

Read the repo and record what you find:
- **package manager + install**: from the lockfile (`pnpm-lock.yaml` -> pnpm, `package-lock.json` -> npm, `yarn.lock` -> yarn, `bun.lockb` -> bun; `Cargo.toml` -> cargo).
- **verify command(s)**: from `package.json` scripts (lint / typecheck / test / build), a `Makefile` / `justfile`, or framework defaults. Prefer the fast, deterministic checks (lint + typecheck).
- **CI**: `.github/workflows/*.yml` (note the PR check job and its steps) or `.gitlab-ci.yml`.
- **main branch + repo slug**: `git symbolic-ref refs/remotes/origin/HEAD` and `gh repo view --json nameWithOwner`.
- **house rules**: `AGENTS.md` / `CLAUDE.md` (if present, plan `houseRules: "@AGENTS.md"`).
- **tracker (note availability, do not pick one yet)**: record which trackers are *available*, not which one to use: a GitHub remote (`gh repo view` succeeds), the Linear MCP connected (ToolSearch `linear issues`), a Jira config. The Linear MCP is an ambient, account-level signal (it is connected in every repo), so treat it as "Linear is available here," never as "this project uses Linear." The user picks in the interview.
- **doc tools**: `openspec/` (-> an openspec author-reconcile job), `DESIGN.md` + `.impeccable/` (-> an impeccable curate-serial job), `graphify-out/` (-> a graphify regenerate job), other notable docs (`ARCHITECTURE.md`, `docs/`).
- **installed reviewers**: scan available skills/agents for `pr-review-toolkit`, `vercel-react-best-practices`, and similar.

## 2. Interview (only the gaps)

First show the user a short summary of everything you detected (the values you will use), so they see how much is already inferred and only the gaps remain. Then ask the gaps, batched into `AskUserQuestion` (a few at a time). **Never ask a bare question.** Each question carries its context: one line on what the setting controls, why ship-it needs it, and what each option means or trades off. Write the option descriptions concretely, for example, for merge strategy spell out that squash vs merge changes how stacked PRs and the post-merge archive behave; for reviewers, say what each one checks; for doc jobs, what "keep current" means for that doc. The gaps to cover:
- **tracker**: ask the user to choose via `AskUserQuestion`, never pre-pick. Order the options: the trackers you detected as **available** first (for this repo, GitHub Issues and Linear), then other built-in trackers you did not detect (e.g. Jira), up to the 4-option limit; the harness adds **Other** automatically for a custom tracker (which becomes a custom resolver skill named in `source.tracker`). After they choose: Linear needs the project + team + id prefix; GitHub Issues needs the "todo" label; a custom one needs how to list and fetch its issues.
- **merge strategy**: squash / merge / rebase. It cannot be fully detected and it changes stacked-PR and archive behavior, so propose a default from the repo's allowed methods (`gh api repos/{owner}/{repo} -q '{squash: .allow_squash_merge, merge: .allow_merge_commit, rebase: .allow_rebase_merge}'`), then confirm with the user.
- **reviewers**: which to run on each diff (multi-select from detected + known). Default to `pr-review-toolkit`; if it is not installed, offer the install command or let them point at another. More than one is fine.
- **doc jobs**: which docs to keep current and the mechanic for each (regenerate / author-reconcile / curate-serial). Built-ins for openspec, graphify, impeccable; for any other doc, capture its path, mechanic, and how to update it (step 4 generates the job).
- **safety rails**: any hard constraints workers must carry (e.g. "no personal data", "code-only verification").
- **worktrees**: on or off, and the root. The **prepare** command runs *in the worktree*, so for a plain dependency setup emit the package manager's frozen offline install (e.g. `pnpm install --frozen-lockfile --offline`). If the project needs more to be runnable (for example a `src-tauri/` Tauri app must link its bundled sidecar resources, or a monorepo needs a workspace install), reference an existing project prepare script if one is present, otherwise scaffold `.claude/ship-it/prepare-worktree.sh` that does the install plus those steps and reference it as `.claude/ship-it/prepare-worktree.sh {wt} {main}`, asking the user for the extra steps if you cannot infer them. Never emit a prepare that silently drops required steps.
- **concurrency**: max parallel lanes.
- **releases (optional)**: whether to set up release management at all; if yes, capture the version source, tag format, notes style, and build to watch, and set `release.enabled` true; if no, omit the `release` block.

Confirm the detected values in bulk rather than re-asking them, and ask only what is genuinely unknown, but always with the context above so the user understands each choice rather than guessing.

## 3. Prerequisite and auth check

Check and report (warn, do not fail):
- tracker reachable (Linear MCP connected, or `gh auth status` for github-issues),
- `gh` authenticated,
- doc-tool binaries on PATH (`openspec`, `graphify`) for the chosen doc jobs,
- chosen reviewers installed (print the install command for any missing, e.g. `claude plugin install pr-review-toolkit@claude-plugins-official`, `npx skills add vercel-labs/agent-skills`).

## 4. Generate doc-job skills for novel docs

For each doc the user named that has no built-in job, invoke **skill-creator** (Skill tool) to write a **project-local** skill (in this project's `.claude/skills/`, not the plugin) that updates that doc by the chosen mechanic, given the shipped changes. Ensure the generated skill declares `allowed-tools` (at least Bash, Read, Edit) so it can compute the diff and edit its doc. Register it in the config's `docs.jobs` by its bare name. Built-in docs (openspec, graphify, impeccable) need no generation; reference them directly.

## 5. Write ship-it.config

Write `ship-it.config.json` at the project root (or `.claude/ship-it.config.json`) as plain JSON conforming to the schema. Keys: `repo` (mainBranch, mergeStrategy, slug), `source` (default + tracker), `houseRules`, `safety`, `verify`, `worktree` (enabled, root, prepare), `concurrency.maxLanes`, `review.reviewers`, `ci` (watch, fixAttempts), `docs.jobs`, `prTemplate`, `release`. Fill detected values; use the interview answers for the rest. Show the user the written config.

## 6. Summary

Tell the user the config is written, list any unmet prerequisites with their install commands, and point them at the next step: run `ship-it:ship-issues` for a batch, or any stage skill standalone (`ship-it:ci-fix`, `ship-it:review-and-address`, `ship-it:fix-one-issue`, `ship-it:comment-cleanup`).
