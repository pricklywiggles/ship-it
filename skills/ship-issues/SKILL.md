---
name: ship-issues
description: Ship a batch of work-units (tracker issues, or the current local changes) end to end and concurrently: implement, comment-cleanup, review and address, then push and open a PR for each, keeping the project's living docs current. Use for "ship all the todo issues", "knock out fra-111 through 120", "batch-fix these tickets and open PRs", "clear the todo column", "run the multi-issue workflow". Resolves the work-unit set from config.source, groups into concurrent lanes, and chains the ship-it stage skills per work-unit. Checkpoints on a plan first. Not for a single existing PR (use the stage skills directly), cutting a release (cut-release), or just listing issues.
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, Agent, Workflow, Skill, ToolSearch
---

# ship-issues: batch orchestrator

Drive a set of work-units to open PRs concurrently, chaining the ship-it stage skills per work-unit, then keep the project's living docs current. Generic: every project specific lives in `ship-it.config`; the flow does not. Load the resolved config once up front with `${CLAUDE_PLUGIN_ROOT}/scripts/load-config.sh` (defaults applied, `@FILE` refs like `houseRules: @AGENTS.md` inlined) and read keys with `jq`. Read `references/workflow.md` before Phase 5 (the lane algorithm and the Workflow template to adapt).

## Phase 1: Resolve the work-units

**If the trigger names no issue selection, ask first** (do not default to a status like "all todo"): use `AskUserQuestion` to ask what to ship, a status, a range, specific ids, or the current changes, then resolve. When a selection is given, read `config.source` and expand it into concrete work-units:
- **`tracker`**: list/get issues via the tracker adapter (`config.source.tracker`: type + project/team/idPrefix, or a custom resolver skill). A status ("all todo"), a range ("fra-111-120"), or an explicit list. Each work-unit carries `id`, `title`, `desc`, `branch` (the tracker's branch name, which carries the auto-close link), `url`.
- **`working-tree` / `branch` / `pr` / `describe`**: build a single work-unit from local state or a description.

Read each item's full intent. If any is ambiguous in a way that changes the implementation, batch the open questions into one `AskUserQuestion` now. All interactivity is front-loaded here and at the Phase 3 checkpoint. See `references/sources.md` for the source dispatch, the built-in tracker adapters (`github-issues`, `linear`), the local sources (working-tree / branch / pr / describe), and the custom-tracker extension point.

**Trigger tokens.** Two optional switches, anywhere in the trigger: a **skip-confirmation** token (`skip confirm`, `no confirm`, `no checkpoint`, `without asking`, `just do it`, `yolo`, `-y`, `--yes`) turns off the Phase 3 checkpoint; a **skip-docs** token (`no docs`, `skip docs`, `code only`, `no specs`) turns off the whole documentation phase (Phase 6) for this run, regardless of `config.docs.enabled`.

## Phase 2: Scope and group into lanes

1. **Scope pass** (parallel, read-only): one `Explore` subagent per work-unit to predict the files it touches, a one-line approach, and a preliminary doc classification (which of `config.docs.jobs` it triggers). Locate, do not implement.
2. **Group into lanes** by the overlap-graph algorithm in `references/workflow.md` (connected components of "edit the same file"). Lanes run concurrently; within a lane, work-units run sequentially on stacked branches.
3. Branch + base per work-unit: lane head off `config.repo.mainBranch`; a stacked child off its parent branch.

## Phase 3: Checkpoint on the plan

Unless a skip-confirmation token is in the trigger, show the plan and wait: the resolved work-units, the lanes (concurrent vs stacked), the predicted files, the predicted doc jobs, and a note that verification is `config.verify` and any `config.safety` rails apply. Apply corrections. Under a skip token, print the plan anyway and proceed without pausing.

## Phase 4: Pre-create lane-head worktrees

If `config.worktree.enabled`, create each lane head's worktree under `config.worktree.root`, **sequentially** (concurrent `git worktree add` races the index lock), and make each runnable with `config.worktree.prepare`. Stacked children are created lazily by their own `fix-one-issue` step off the parent branch, after the parent commits. Use `${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktrees.sh --root <config.worktree.root> --prepare "<config.worktree.prepare>"`, feeding one `<id>|<branch>|<base>` line per lane head on stdin.

## Phase 5: Run the batch

Adapt the Workflow template in `references/workflow.md` (fill in the resolved lanes and the path to `ship-it.config`), then launch it with the **Workflow** tool. Per work-unit the pipeline chains the stage skills (it never reimplements them):

1. **`ship-it:fix-one-issue`** (creating the worktree first if a stacked child), commit. Returns `addedComments` and `docNeed`.
2. **`ship-it:comment-cleanup`** in apply mode, scoped to the work-unit's commit range, only if `addedComments`. Code-modifying, so sequential within a lane; concurrent across lanes.
3. **`ship-it:review-and-address`** over the work-unit's diff (fans out `config.review.reviewers`, merges findings, applies warranted per `config.review.applyWarranted`).
4. **`ship-it:open-pr`**: push the branch and open a PR per `config.prTemplate` (base `main` for a lane head, the parent branch for a stacked child; GitHub auto-retargets a stacked PR to main when its parent merges).

Each result carries `docNeed` (the doc jobs it triggers) for Phase 6.

## Phase 6: Documentation (doc-job fan-out)

**Skip this entire phase if a skip-docs token was in the trigger**, or if `config.docs.enabled` is false. Otherwise read `references/doc-jobs.md` for the mechanics and built-in jobs. After the Workflow returns, run the doc phase: for each job in `config.docs.jobs`, run the ones whose trigger (`appliesWhen`) matched a shipped work-unit, in parallel (each owns a different file). By mechanic:
- **regenerate**: deferred to Phase 7 (post-merge), because the doc is re-derived from the merged code, not the pre-merge base. Do not run it here.
- **author-reconcile**: the per-work-unit artifact was authored on its branch during the run (or author it now); reconcile into canonical docs post-merge (Phase 7).
- **curate-serial**: update the shared prose doc once, serially (e.g. `impeccable` for DESIGN.md). If several work-units are visual, one consolidated pass.

Skip jobs with no matching change. Do not over-document.

## Phase 7: Post-PR watchers (in-session, optional)

If `config.ci.watch`, spawn one **`ship-it:ci-fix`** background watcher per PR. If there are author-reconcile **or regenerate** doc jobs, launch the merge watcher `${CLAUDE_PLUGIN_ROOT}/scripts/watch-merges.sh --prs <csv> --reconcile "<cmd>"`, where `<cmd>` composes the post-merge work joined with `&&`: any author-reconcile reconcile (e.g. `${CLAUDE_PLUGIN_ROOT}/scripts/openspec-archive.sh <change-ids>`) and any regenerate command (e.g. `graphify update .`). It polls until the PRs are merged (timeout), then runs that command against the merged code (archiving specs, regenerating derived docs) and opens the batched docs PR. On timeout, it prints the manual command. See `references/doc-jobs.md`.

## Phase 8: Summarize

Print a table: work-unit, PR link, lane, what changed, review items applied/skipped, doc outcome, blockers. Point the user at the post-merge follow-ups, both merged-gated: the doc reconcile (Phase 7) and worktree cleanup via `${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-worktrees.sh --all-merged`.

## Guardrails

- Edit only inside each work-unit's worktree; never the main checkout.
- Honor `config.houseRules` + `config.safety` everywhere (commits, PR text, edits).
- Verification is `config.verify`.
- Create worktrees sequentially, then fan out.
- Front-load all interactivity to Phase 1 and Phase 3; the Workflow workers run non-interactively.
- Invoke the stage skills by their namespaced names (`ship-it:fix-one-issue`, `ship-it:comment-cleanup`, `ship-it:review-and-address`, `ship-it:open-pr`); never reimplement their logic inline.

## Bundled files

- `references/sources.md` - how Phase 1 resolves the trigger into work-units: source dispatch, the built-in tracker adapters, and the custom-tracker extension point. Read before Phase 1.
- `references/workflow.md` - the lane-grouping algorithm and the Workflow script template to adapt. Read before Phase 5.
- `references/doc-jobs.md` - the three doc-job mechanics, the built-in jobs, and the post-merge reconcile flow. Read before Phase 6.
- `${CLAUDE_PLUGIN_ROOT}/scripts/openspec-archive.sh` - the openspec author-reconcile reconcile (merged-gated `openspec archive`, batched docs PR).
- `${CLAUDE_PLUGIN_ROOT}/scripts/watch-merges.sh` - the in-session merge watcher that runs a `--reconcile` command once the PRs merge.
- `${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktrees.sh` - pre-create lane-head worktrees (stdin `<id>|<branch>|<base>`), running the project prepare per worktree. Read before Phase 4.
- `${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-worktrees.sh` - merged-gated worktree + branch teardown. Phase 8 / post-merge.
- `${CLAUDE_PLUGIN_ROOT}/scripts/load-config.sh` - locate + resolve `ship-it.config` (defaults + `@FILE` inlining) to JSON. Load once up front.
