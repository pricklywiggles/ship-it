# ship-it

Ship your work end to end. A Claude Code plugin: a configurable orchestrator that drives a batch of issues (or your current local changes) through implement, review, comment cleanup, and PR, keeping living docs in sync. The same steps are also standalone, individually callable skills, so you can run just the CI fix, just the review, or push the current diff through the flow without a tracker.

Adapt it to a project with `init`, which detects what it can (package manager, verify command, CI system, issue tracker, doc tools, reviewers) and asks for the rest, producing a `ship-it.config`. Docs are kept current by pluggable jobs that run in parallel: built-ins for OpenSpec, graphify, and impeccable, plus jobs `init` can generate for any other doc you need to keep up to date.

## Install

```shell
/plugin marketplace add pricklywiggles/fractally-claude-marketplace
/plugin install ship-it@fractally-claude-marketplace
```

Then adapt it to your project once:

```shell
/ship-it:init
```

Every skill auto-activates when Claude judges it relevant, or you can invoke one explicitly as `/ship-it:<skill>` (e.g. `/ship-it:ship-issues`).

## Skills

| Skill | Role |
|---|---|
| `ship-issues` | **Orchestrator.** Ship a batch of work-units (tracker issues or your current local changes) concurrently — plan, implement, clean comments, review and address, then open a PR for each — keeping living docs in sync. |
| `init` | Configure ship-it for a project: detect the package manager, verify command, CI, issue tracker, docs, and reviewers; write `ship-it.config`. Run once per project before the orchestrator. |
| `plan-one-issue` | Produce a comprehensive, reviewable implementation plan for a single work-unit before any code is written. |
| `fix-one-issue` | Implement a single work-unit end to end in its branch: explore, make the smallest correct change, verify, commit. |
| `review-and-address` | Run the project's configured reviewers in parallel over a branch or diff, merge their findings, and apply the warranted ones. |
| `comment-cleanup` | Audit code comments against the "explain non-obvious *why*, never narrate *what*" standard and propose concrete fixes. |
| `open-pr` | Push a finished branch and open its pull request with a complete, QA-ready body (summary, tracker link, verification checklist). |
| `ci-fix` | Watch a pull request's CI to completion and fix any failures in its branch — bounded and cause-only. |

Each stage is usable on its own; `ship-issues` is for taking a whole batch through the flow in one pass. The stage skills also compose: the orchestrator chains them per work-unit.

## How it works

ship-it is three layers (see [CONTRACTS.md](CONTRACTS.md) for the full design spec):

1. **Orchestrator** — generic and project-agnostic. It owns lane grouping, the concurrent Workflow fan-out, the worktree lifecycle, and the post-PR CI watchers. It contains no project specifics.
2. **Stage skills** — reusable units of work. Each operates on one **work-unit** (a tracker issue, or ad-hoc local work) and is individually callable, both from an orchestrator's parallel workers and by you on its own.
3. **Per-project config** (`ship-it.config`) — the values, command strings, and adapter references that adapt the generic engine to your project. Produced by `init` and validated by a bundled JSON-schema check.

All human interaction is front-loaded into `init` and the plan checkpoint, so the workers run non-interactively and parallelize. Reviewers and doc jobs are parallel fan-outs over their configured lists.

## Configuration

`init` writes `ship-it.config` (JSON or JSONC) to `.claude/ship-it/config.json` (the repo root or `.claude/ship-it.config.json` also work as loader fallbacks). It captures the repo's main branch and merge strategy, the work-unit source (a tracker such as Linear, or your local changes), the verify command, CI settings, the reviewers to run, and the doc jobs to keep current. See [`ship-it.config.example.jsonc`](ship-it.config.example.jsonc) for a filled-in instance.

## Layout

- `skills/` — the eight individually callable skills
- `scripts/` — the engine's shell helpers (config loader and validator, worktree setup/cleanup, CI and merge watchers, doc-job reconcilers)
- `CONTRACTS.md` — the design spec: the stable interfaces and the `ship-it.config` shape
- `ship-it.config.example.jsonc` — a worked example config
- `.claude-plugin/plugin.json` — the plugin manifest
