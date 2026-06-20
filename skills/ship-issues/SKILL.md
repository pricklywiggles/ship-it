---
name: ship-issues
description: Ship a batch of work-units (tracker issues, or the current local changes) end to end and concurrently: implement, comment-cleanup, review and address, then push and open a PR for each, keeping the project's living docs current. Use for "ship all the todo issues", "knock out fra-111 through 120", "batch-fix these tickets and open PRs", "clear the todo column", "run the multi-issue workflow". Resolves the work-unit set from config.source, groups into concurrent lanes, and chains the ship-it stage skills per work-unit. Checkpoints on a plan first. Not for a single existing PR (use the stage skills directly), cutting a release (cut-release), or just listing issues.
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, Agent, Workflow, Skill, ToolSearch
---

# ship-issues: batch orchestrator

Drive a set of work-units to open PRs concurrently, chaining the ship-it stage skills per work-unit, then keep the project's living docs current. Generic: every project specific lives in `ship-it.config`; the flow does not. Read `references/workflow.md` before Phase 5 (the lane algorithm and the Workflow template to adapt).

## Phase 1: Resolve the work-units

Read `config.source` and expand the trigger's selection into concrete work-units:
- **`tracker`**: list/get issues via the tracker adapter (`config.source.tracker`: type + project/team/idPrefix, or a custom resolver skill). A status ("all todo"), a range ("fra-111-120"), or an explicit list. Each work-unit carries `id`, `title`, `desc`, `branch` (the tracker's branch name, which carries the auto-close link), `url`.
- **`working-tree` / `branch` / `pr` / `describe`**: build a single work-unit from local state or a description.

Read each item's full intent. If any is ambiguous in a way that changes the implementation, batch the open questions into one `AskUserQuestion` now. All interactivity is front-loaded here and at the Phase 3 checkpoint. (The sources resolver is a separate piece; until it lands, resolve inline per `config.source.type`.)

## Phase 2: Scope and group into lanes

1. **Scope pass** (parallel, read-only): one `Explore` subagent per work-unit to predict the files it touches, a one-line approach, and a preliminary doc classification (which of `config.docs.jobs` it triggers). Locate, do not implement.
2. **Group into lanes** by the overlap-graph algorithm in `references/workflow.md` (connected components of "edit the same file"). Lanes run concurrently; within a lane, work-units run sequentially on stacked branches.
3. Branch + base per work-unit: lane head off `config.repo.mainBranch`; a stacked child off its parent branch.

## Phase 3: Checkpoint on the plan

Unless a skip-confirmation token is in the trigger, show the plan and wait: the resolved work-units, the lanes (concurrent vs stacked), the predicted files, the predicted doc jobs, and a note that verification is `config.verify` and any `config.safety` rails apply. Apply corrections. Under a skip token, print the plan anyway and proceed without pausing.

## Phase 4: Pre-create lane-head worktrees

If `config.worktree.enabled`, create each lane head's worktree under `config.worktree.root`, **sequentially** (concurrent `git worktree add` races the index lock), and make each runnable with `config.worktree.prepare`. Stacked children are created lazily by their own `fix-one-issue` step off the parent branch, after the parent commits. (The worktree-lifecycle helper is bundled later; until then the orchestrator runs `git worktree add` + `config.worktree.prepare` inline.)

## Phase 5: Run the batch

Adapt the Workflow template in `references/workflow.md` (fill in the resolved lanes and the path to `ship-it.config`), then launch it with the **Workflow** tool. Per work-unit the pipeline chains the stage skills (it never reimplements them):

1. **`ship-it:fix-one-issue`** (creating the worktree first if a stacked child), commit. Returns `addedComments` and `docNeed`.
2. **`ship-it:comment-cleanup`** in apply mode, scoped to the work-unit's commit range, only if `addedComments`. Code-modifying, so sequential within a lane; concurrent across lanes.
3. **`ship-it:review-and-address`** over the work-unit's diff (fans out `config.review.reviewers`, merges findings, applies warranted per `config.review.applyWarranted`).
4. **Finalize**: push the branch and open a PR per `config.prTemplate` (base `main` for a lane head, the parent branch for a stacked child; GitHub auto-retargets a stacked PR to main when its parent merges).

Each result carries `docNeed` (the doc jobs it triggers) for Phase 6.

## Phase 6: Documentation (doc-job fan-out)

After the Workflow returns, run the doc phase: for each job in `config.docs.jobs`, run the ones whose trigger (`appliesWhen`) matched a shipped work-unit, in parallel (each owns a different file). By mechanic:
- **regenerate**: run the job's command (e.g. `graphify update .`).
- **author-reconcile**: the per-work-unit artifact was authored on its branch during the run (or author it now); reconcile into canonical docs post-merge (Phase 7).
- **curate-serial**: update the shared prose doc once, serially (e.g. `impeccable` for DESIGN.md). If several work-units are visual, one consolidated pass.

Skip jobs with no matching change. Do not over-document.

## Phase 7: Post-PR watchers (in-session, optional)

If `config.ci.watch`, spawn one **`ship-it:ci-fix`** background watcher per PR. If there are author-reconcile doc jobs, launch the merge watcher: poll until the PRs are merged (timeout), then run each job's post-merge reconcile (archive) for the merged work-units and open the batched docs PR. On timeout, fall back to the manual command. (The watcher scripts are bundled later; until then launch them inline.)

## Phase 8: Summarize

Print a table: work-unit, PR link, lane, what changed, review items applied/skipped, doc outcome, blockers. Point the user at the post-merge follow-ups (the doc reconcile/archive, worktree cleanup), which are merged-gated.

## Guardrails

- Edit only inside each work-unit's worktree; never the main checkout.
- Honor `config.houseRules` + `config.safety` everywhere (commits, PR text, edits).
- Verification is `config.verify`.
- Create worktrees sequentially, then fan out.
- Front-load all interactivity to Phase 1 and Phase 3; the Workflow workers run non-interactively.
- Invoke the stage skills by their namespaced names (`ship-it:fix-one-issue`, `ship-it:comment-cleanup`, `ship-it:review-and-address`); never reimplement their logic inline.

## Bundled files

- `references/workflow.md` - the lane-grouping algorithm and the Workflow script template to adapt. Read before Phase 5.
