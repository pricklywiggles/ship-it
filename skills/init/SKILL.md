---
name: init
description: Configure ship-it for this project. Detects the package manager, verify command, CI system, issue tracker, doc tools, and installed reviewers from the repo, asks only for what it cannot infer, then writes ship-it.config and generates doc-job skills for any docs without a built-in. Use to set up ship-it on a new project ("set up ship-it here", "configure ship-it", "ship-it init") or to reconfigure. Run once per project before using the ship-issues orchestrator.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, Skill, ToolSearch
---

# init: configure ship-it for this project

Produce a `ship-it.config` that adapts the generic engine to this project. Detect first, ask only for the gaps, generate doc-job skills for anything without a built-in. This is the one place all the interactive questions live; everything downstream runs from the config non-interactively.

The full config schema is in the plugin's `CONTRACTS.md`; the keys are summarized in step 5.

## 1. Detect (read-only)

Read the repo and record what you find:
- **package manager + install**: from the lockfile (`pnpm-lock.yaml` -> pnpm, `package-lock.json` -> npm, `yarn.lock` -> yarn, `bun.lockb` -> bun; `Cargo.toml` -> cargo).
- **verify command(s)**: from `package.json` scripts (lint / typecheck / test / build), a `Makefile` / `justfile`, or framework defaults. Prefer the fast, deterministic checks (lint + typecheck).
- **CI**: `.github/workflows/*.yml` (note the PR check job and its steps) or `.gitlab-ci.yml`.
- **main branch + repo slug**: `git symbolic-ref refs/remotes/origin/HEAD` and `gh repo view --json nameWithOwner`.
- **house rules**: `AGENTS.md` / `CLAUDE.md` (if present, plan `houseRules: "@AGENTS.md"`).
- **tracker**: is the Linear MCP connected (ToolSearch `linear issues`)? a GitHub remote (-> github-issues)? a Jira config?
- **doc tools**: `openspec/` (-> an openspec author-reconcile job), `DESIGN.md` + `.impeccable/` (-> an impeccable curate-serial job), `graphify-out/` (-> a graphify regenerate job), other notable docs (`ARCHITECTURE.md`, `docs/`).
- **installed reviewers**: scan available skills/agents for `pr-review-toolkit`, `vercel-react-best-practices`, and similar.

## 2. Interview (only the gaps)

Present what you detected, then batch the open questions into `AskUserQuestion` (a few at a time):
- **tracker**: confirm the type; for Linear, the project + team + id prefix; for github-issues, the "todo" label.
- **merge strategy**: squash / merge / rebase (cannot be detected reliably; it changes stacked-PR and archive behavior).
- **reviewers**: which to run on each diff (multi-select from detected + known). Default to `pr-review-toolkit`; if it is not installed, offer the install command or let them point at another. More than one is fine.
- **doc jobs**: which docs to keep current and the mechanic for each (regenerate / author-reconcile / curate-serial). Built-ins for openspec, graphify, impeccable; for any other doc, capture its path, mechanic, and how to update it (step 4 generates the job).
- **safety rails**: any hard constraints workers must carry (e.g. "no personal data", "code-only verification").
- **worktrees**: on or off, the root, and the prepare command (a project script when prep is more than a plain install).
- **concurrency**: max parallel lanes.

Keep it short: confirm detections in bulk, ask only what is genuinely unknown.

## 3. Prerequisite and auth check

Check and report (warn, do not fail):
- tracker reachable (Linear MCP connected, or `gh auth status` for github-issues),
- `gh` authenticated,
- doc-tool binaries on PATH (`openspec`, `graphify`) for the chosen doc jobs,
- chosen reviewers installed (print the install command for any missing, e.g. `claude plugin install pr-review-toolkit@claude-plugins-official`, `npx skills add vercel-labs/agent-skills`).

## 4. Generate doc-job skills for novel docs

For each doc the user named that has no built-in job, invoke **skill-creator** (Skill tool) to write a **project-local** skill (in this project's `.claude/skills/`, not the plugin) that updates that doc by the chosen mechanic, given the shipped changes. Register it in the config's `docs.jobs` by its name. Built-in docs (openspec, graphify, impeccable) need no generation; reference them directly.

## 5. Write ship-it.config

Write `ship-it.config.json` at the project root (or `.claude/ship-it.config.json`) as plain JSON conforming to the schema. Keys: `repo` (mainBranch, mergeStrategy, slug), `source` (default + tracker), `houseRules`, `safety`, `verify`, `worktree` (enabled, root, prepare), `concurrency.maxLanes`, `review.reviewers`, `ci` (watch, fixAttempts), `docs.jobs`, `prTemplate`, `release`. Fill detected values; use the interview answers for the rest. Show the user the written config.

## 6. Summary

Tell the user the config is written, list any unmet prerequisites with their install commands, and point them at the next step: run `ship-it:ship-issues` for a batch, or any stage skill standalone (`ship-it:ci-fix`, `ship-it:review-and-address`, `ship-it:fix-one-issue`, `ship-it:comment-cleanup`).
