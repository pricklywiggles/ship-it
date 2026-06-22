---
name: init
description: Configure ship-it for this project. Detects the package manager, verify command, CI system, issue tracker, doc tools, and installed reviewers from the repo, asks only for what it cannot infer, then writes ship-it.config and generates doc-job skills for any docs without a built-in. Use to set up ship-it on a new project ("set up ship-it here", "configure ship-it", "ship-it init") or to reconfigure. Run once per project before using the ship-issues orchestrator.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, AskUserQuestion, Skill, ToolSearch
---

# init: configure ship-it for this project

Produce a `ship-it.config` that adapts the generic engine to this project. Detect first, ask only for the gaps, generate doc-job skills for anything without a built-in. This is the one place all the interactive questions live; everything downstream runs from the config non-interactively.

The full config schema is in the plugin's `CONTRACTS.md`; the keys are summarized in step 5.

## 0. Welcome and explain the plan

Before touching anything, open with a short welcome that orients a first-time user. Cover four things, briefly and skimmably: a **welcome**, **what ship-it does**, **the stages it covers**, and **what is about to happen** in this setup. Something like:

> **Welcome to ship-it.** It takes your work from a tracker issue (or just your current changes) all the way to a merged pull request, and keeps your living docs in step as it goes. It is configurable per project, and every stage is also a standalone skill you can run on its own.
>
> **The stages** (the named skills below also run on their own, and `init` configures or swaps each):
>
> - **implement** (`fix-one-issue`): make the change in a branch, verify, commit.
> - **comment cleanup** (`comment-cleanup`): a pass that verifies and corrects comment overuse and verbosity in the change, keeping the non-obvious why and dropping narration.
> - **review** (`review-and-address`): run your configured reviewers over the diff and apply the warranted feedback.
> - **open the PR** (`open-pr`): push the branch and open the PR with a QA-ready body.
> - **docs**: parallel doc jobs keep your living docs current (specs, design system, architecture, generated wikis, whatever you configure).
> - **CI** (`ci-fix`): watch the PR's checks and fix failures.
>
> The **ship-issues** orchestrator runs these across a batch, working out which work-units can run in parallel and which must run sequentially (overlapping work is stacked on dependent branches so the PRs never collide); `init` adapts all of it to your project.
>
> **Right now, setup:** I'll (1) **detect** your project by reading the repo (read-only), (2) **ask** only what I cannot infer, explaining each question, (3) **check prerequisites** (tracker access, `gh` auth, doc-tool binaries), (4) **generate** a small doc-job skill for any doc you keep that has no built-in, and (5) **write and validate** `ship-it.config.json`. The only things I create are that config and any generated skills; nothing else changes.

Adapt the wording to the project, keep it skimmable, then proceed to detection.

## 1. Detect (read-only)

Read the repo and record what you find:
- **package manager + install**: from the lockfile (`pnpm-lock.yaml` -> pnpm, `package-lock.json` -> npm, `yarn.lock` -> yarn, `bun.lockb` -> bun; `Cargo.toml` -> cargo).
- **runtime/build artifacts (for the worktree prepare)**: anything the app needs to *run* that is not committed and a plain install does not produce, so a fresh worktree would lack it. Detect the project type and its generated artifacts: e.g. a Tauri app (`src-tauri/` + `tauri.conf.json`) whose config bundles `resources/` or a sidecar; generated code (protobuf, an ORM client); a prebuilt asset bundle. Record what you find; most projects have none, in which case prepare is just the install.
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
- **merge strategy**: squash / merge / rebase. It cannot be fully detected and it changes stacked-PR and archive behavior, so propose a default, then confirm. **Recommend `merge`**: it preserves the base branch's commits, so stacked PRs (overlapping issues) retarget cleanly; squash rewrites those commits into one and strands the stacked child, which then needs workarounds. Use the repo's allowed methods (`gh api repos/{owner}/{repo} -q '{squash: .allow_squash_merge, merge: .allow_merge_commit, rebase: .allow_rebase_merge}'`) to rule out options the repo disallows, but lead with merge unless the team wants a linear history and accepts the stacking cost.
- **reviewers**: which to run on each diff (multi-select from detected + known). Default to `pr-review-toolkit`; if it is not installed, offer the install command or let them point at another. More than one is fine. The `ref` you write is the reviewer's **invocation** name, which can differ from the skill's folder name: Vercel's React Best Practices sits in the skills folder as `react-best-practices` but is invoked as `vercel-react-best-practices`, so detect it by the folder name and write `vercel-react-best-practices` as the `ref`.
- **doc jobs**: which docs to keep current and the mechanic for each (regenerate / author-reconcile / curate-serial). Built-ins for openspec, graphify, impeccable; for any other doc, capture its path, mechanic, and how to update it (step 4 generates the job).
- **safety rails**: any hard constraints *workers* must carry (e.g. "no personal data"). When `verify` is static-only (lint/typecheck with no run or serve step), include a **code-only** rail ("verification is code-only; never start a dev server; visual/runtime QA is the human's") so a runnable worktree does not tempt a worker into launching the app. Human run/QA caveats are not worker rails: those go in `worktree.qaNotes` (below).
- **worktrees**: on or off, and the root (**default `.claude/worktrees`**, it sits under the conventionally tool-ignored `.claude/`, so linters and VCS skip the worktree copies; prefer it unless the project says otherwise). The **prepare** command runs *in the worktree* and must leave it both **safe** (a plain worktree install can repoint the main repo's package store, so use the **detected** package manager's safe offline install; for pnpm that is `CI=true pnpm install --frozen-lockfile --offline`) and **runnable** (reproduce the non-git runtime/build artifacts you detected in step 1, *if any*). The runnable part is **detection-driven and project-specific**: add a step only when the project actually needs it. For example, *if* you detected a Tauri app that bundles a sidecar, the prepare links its `resources/` (`sidecar.tar.gz` + `sidecar.version`); a project with none needs only the install. When unsure, ask the user. This stack-specific logic lives only in the project's prepare script, never in ship-it itself. The script must live at a **project-owned, ship-it-independent path** so it survives even if the project later retires whatever skill it came from. Resolve it in this order:
  1. If `.claude/ship-it/prepare-worktree.sh` already exists, reference it as-is: `.claude/ship-it/prepare-worktree.sh {wt} {main}`.
  2. Else look for an existing prepare script (`fd -i prepare-worktree .claude`). If a complete one lives **inside a directory ship-it supersedes** (e.g. `.claude/skills/ship-issues/`), do **not** reference it in place (it vanishes when that skill is removed): copy it to `.claude/ship-it/prepare-worktree.sh`, make the install worktree-safe (add `CI=true` if missing), and reference the copy.
  3. Else scaffold `.claude/ship-it/prepare-worktree.sh` from scratch: the safe offline install plus every runnable step (port the extras from any existing script, or ask the user).
  Never drop `CI=true` or a required build resource, and never reference a prepare script inside a directory ship-it will delete. Finally, capture any **run/QA caveats** for the runnable worktrees as `worktree.qaNotes` (e.g. "only one app instance at a time, shared DB lock; quit others first"); the orchestrator surfaces these when it hands the worktrees back for QA. They are human notes, not worker rails.
- **concurrency**: max parallel lanes.

Confirm the detected values in bulk rather than re-asking them, and ask only what is genuinely unknown, but always with the context above so the user understands each choice rather than guessing.

## 3. Prerequisite and auth check

Check and report (warn, do not fail):
- tracker reachable (Linear MCP connected, or `gh auth status` for github-issues),
- `gh` authenticated,
- doc-tool binaries on PATH (`openspec`, `graphify`) for the chosen doc jobs,
- chosen reviewers installed (print the install command for any missing, e.g. `claude plugin install pr-review-toolkit@claude-plugins-official`, `npx skills add vercel-labs/agent-skills`).

## 4. Generate doc-job skills for novel docs

For each doc the user named that has no built-in job, create a **project-local** skill: a directory at `.claude/skills/<name>/SKILL.md` (never a flat `.claude/skills/<name>.md`, which does not load as a skill), in the repo, not in the plugin. It updates that doc by its chosen mechanic from the shipped changes.

**Write this `SKILL.md` yourself, now, in this step**, then continue. It is a static file; nothing runs asynchronously and there is nothing to wait for. If you call the **skill-creator** skill for a richer scaffold, understand the Skill tool only *loads its authoring steps into your own context*, it does not spawn a background worker: follow those steps yourself and `Write` the file in this same turn. Never pause waiting for skill-creator (or any invoked skill) to "finish" on its own.

The file must:
- declare `allowed-tools` (at least `Bash, Read, Edit`) so it can diff the change and edit its doc,
- carry a description that triggers both from the ship-it doc phase and from a manual "update `<doc>` for this change",
- classify whether a given diff is in scope for the doc, then act by mechanic (curate-serial: edit only the affected sections; regenerate: run the command; author-reconcile: author the per-unit artifact),
- include a brief project-context section so the skill is grounded in this repo,
- obey `config.houseRules` in everything it contains, including text the skill prints at runtime: no em dashes (and not `--` as a substitute; use a comma, colon, or rewrite), no AI attribution.

Register it in `docs.jobs` by its bare name (`<name>`). Built-in docs (openspec, graphify, impeccable) need no generation; reference them directly.

## 5. Write and validate ship-it.config

Write the config to **`.claude/ship-it/config.json`** (ship-it's project home, beside the worktree prepare script; the loader also accepts `ship-it.config.json` at the repo root or `.claude/ship-it.config.json`, prefer one of those if the repo gitignores `.claude/`) as plain JSON. **Model it exactly on `${CLAUDE_PLUGIN_ROOT}/ship-it.config.example.jsonc`**, the same keys, nesting, and value *shapes*, swapping in this project's detected and interviewed values. Do not invent alternative key names or shapes. The shapes the engine reads (it reads these exact paths):
- `repo`: `{ mainBranch, mergeStrategy (squash|merge|rebase), slug }`.
- `source`: `{ default, tracker: {...} }`. `tracker` is an **object** with a `type` (`linear` -> project/team/idPrefix; `github-issues` -> the todo label); tracker fields live **inside** `source.tracker`, never in a sibling key.
- `verify`: an **array** of command strings (not `{commands:[...]}`); use direct binaries, not package-manager run-scripts, which misbehave in a worktree (`node_modules/.bin/biome check {changedFiles}`, not `pnpm lint`).
- `safety`: array of worker rails.
- `worktree`: `{ enabled, root, prepare, qaNotes }`.
- `review.reviewers`: array of `{ name, kind (agent|skill|command), ref }`; `ref` is the **invocation** name (`pr-review-toolkit:code-reviewer`, `vercel-react-best-practices`).
- `ci`: `{ watch (boolean on/off, default true; never a workflow path), fixAttempts }`.
- `docs.jobs`: array of `{ name, mechanic (regenerate|author-reconcile|curate-serial), ref, target, appliesWhen }`; `ref` is the command/skill, `appliesWhen` the docNeed that triggers it (a regenerate job may omit `appliesWhen`).
- `prTemplate`: `{ sections, verification }`.

**Then validate in a loop.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.sh <path>` and fix every error it reports, re-running until it prints `OK`. The validator (schema in `scripts/config.schema.jq`) is the schema of record; the config is not done until it passes. Resolve warnings too, or note why not. Then show the user the final, validated config.

## 6. Summary

Tell the user the config is written, list any unmet prerequisites with their install commands, and point them at the next step: run `ship-it:ship-issues` for a batch, or any stage skill standalone (`ship-it:fix-one-issue`, `ship-it:comment-cleanup`, `ship-it:review-and-address`, `ship-it:open-pr`, `ship-it:ci-fix`).
