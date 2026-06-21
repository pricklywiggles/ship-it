---
name: fix-one-issue
description: Implement a single work-unit (a tracker issue or a described task) end to end in its branch: explore, make the smallest correct change, verify, and commit. Use for "implement this issue", "fix issue 123", "make this change and verify it". The implement stage of the ship-it orchestrator, and usable standalone on an issue or a described task. Not for review (use review-and-address), comments (comment-cleanup), or CI (ci-fix).
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# fix-one-issue: implement, verify, commit

Take one work-unit's intent and land the smallest correct change for it in its branch, verified and committed. The core implement stage.

## 1. Resolve the work-unit and working copy

- **Orchestrated**: you are given a work-unit (`id`, `title`, `desc`, `branch`, `base`, `worktree`). If `worktree` is set but does not exist yet (a stacked child whose base only just committed), create it off `base`, then make it runnable:
  ```bash
  git -C <main> worktree add -b <branch> <worktree> <base>   # retry once on an index-lock race
  <config.worktree.prepare, with {wt}=<worktree> and {main}=<main> substituted>
  ```
  If the worktree already exists, it is ready; skip creation.
- **Standalone**: given an issue id, fetch its intent; given a described task, use it directly. Work in the current checkout (or the named branch); create a branch only if told to and none exists.
- Do every read and edit inside the resolved working copy; never the main checkout when a worktree is in play.

## 2. Read config

Load the resolved config via `${CLAUDE_PLUGIN_ROOT}/scripts/load-config.sh` (defaults applied, `@FILE` refs inlined); read keys with `jq`:
- `houseRules` / `safety` (carry into every edit and the commit: no em dashes, no AI attribution, plus project rails, e.g. "read the framework doc first" if a project rule says so),
- `verify` (the commands to run after the change),
- `worktree.prepare` (the make-runnable command used above).

## 3. Implement

1. Explore the working copy to find the exact code; scope every search to it.
2. Make the **smallest correct change** that fully resolves the intent. Match surrounding style and conventions.
3. Stay in scope: resolve this work-unit, nothing else.

## 4. Verify

Run the `verify` commands inside the working copy; fix anything you introduced. Some checks may not reproduce locally; note what you could and could not verify.

## 5. Commit

```bash
git -C <worktree> add -A
git -C <worktree> commit -m "<concise imperative subject; mention the id if there is one>"
```
Honor `houseRules`: no em dashes, no AI attribution. Do NOT push or open a PR; later stages do that.

## 6. Classify documentation impact (do not write docs)

For each configured doc job (`config.docs.jobs`), decide whether this change meets its trigger (`appliesWhen`): a user-facing capability / behavior / route / data-path change (a spec job), a reusable visual or design-system primitive (a design job), an architectural decision or boundary shift (an architecture job), and so on. Return the matching job names, or none. Most changes are none; do not over-classify. The doc phase runs the matching jobs later, so do not write docs here.

## Output

- **Standalone**: report what changed (files plus a one-line summary) and the verification result.
- **Called by the orchestrator**: a structured result, `{ issueId, implemented, committed, summary, filesChanged, addedComments, verification, docNeed: [...], docRationale }`. Set `addedComments` true only if you added or changed a code comment (it gates the comment-cleanup stage).
