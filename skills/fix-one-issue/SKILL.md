---
name: fix-one-issue
description: Implement a single work-unit (a tracker issue or a described task) end to end in its branch: explore, make the smallest correct change, verify, and commit. Use for "implement this issue", "fix issue 123", "make this change and verify it". The implement stage of the ship-it orchestrator, and usable standalone on an issue or a described task. Not for review (use review-and-address), comments (comment-cleanup), or CI (ci-fix).
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, WebFetch, WebSearch, ToolSearch
---

# fix-one-issue: implement, verify, commit

Take one work-unit's intent and land the smallest correct change for it in its branch, verified and committed. The core implement stage.

## 1. Resolve the work-unit and working copy

- **Orchestrated**: you are given a work-unit (`id`, `title`, `desc`, `branch`, `base`, `worktree`, and a `plan` when the planning stage ran). If `worktree` is set but does not exist yet (a stacked child whose base only just committed), create it off `base`, then make it runnable:
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

If the work-unit carries a `plan` (from the planning stage), implement against it: the plan names the steps, files, and edge cases, so follow it rather than re-deriving the approach. For a **stacked child** (its `base` is a sibling branch, not `config.repo.mainBranch`), the plan was drafted before the parent landed, so first reconcile it with the parent's committed work: read `git -C <worktree> diff <config.repo.mainBranch>...HEAD` (everything the parent already put on your base) and adjust the plan for it before coding. With no plan (standalone, or planning disabled), proceed from exploration.

1. Explore the working copy to find the exact code, or confirm the plan's predicted files; scope every search to it.
2. **Verify every external API before you write it. Do not write a single call into a third-party package, framework, runtime, or platform API from memory.** Training data lags the installed version, and a hallucinated attribute or a renamed option is how confidently-broken code ships. Read the version from `package.json` / the lockfile (or `Cargo.toml`, `go.mod`, ...), then confirm the exact symbol, signature, options, and behavior against THAT version: check the package's shipped docs and types in `node_modules` (a `docs/` folder, an `llms.txt`, an `AGENTS.md`, a README, or `.d.ts` types, e.g. `node_modules/next/dist/docs/`); the installed source itself; and version-pinned official docs via the **context7** MCP tool or the docs site. If a plan step relies on an API you cannot confirm (even a plausible one), do not implement it on faith: use a verified API or stop and flag it. Honor any project rule that already requires this.
3. Make the **smallest correct change** that fully resolves the intent, following the plan when present. Match surrounding style and conventions. If reality diverges from the plan, do the correct thing and note the divergence.
4. Stay in scope: resolve this work-unit, nothing else.

## 4. Verify

Run the `verify` commands inside the working copy; fix anything you introduced. Some checks may not reproduce locally; note what you could and could not verify.

## 5. Commit

```bash
git -C <worktree> add -A
git -C <worktree> commit -m "<concise imperative subject; mention the id if there is one>"
```
Honor `houseRules`: no em dashes, no AI attribution. Do NOT push or open a PR; later stages do that.

## 6. Classify documentation impact (do not write docs)

For each configured doc job (`config.docs.jobs`), decide whether this change meets its trigger (`appliesWhen`): a user-facing capability / behavior / route / data-path change (a spec job), a reusable visual or design-system primitive (a design job), an architectural decision or boundary shift (an architecture job), and so on. Return the matching job names, or none. If the work-unit's `plan` carried a preliminary `docNeed`, treat it as a hint and confirm it against the actual change; you are the authority here, since you see what really changed. Most changes are none; do not over-classify. The doc phase runs the matching jobs later, so do not write docs here.

## Output

- **Standalone**: report what changed (files plus a one-line summary) and the verification result.
- **Called by the orchestrator**: a structured result, `{ issueId, implemented, committed, summary, filesChanged, addedComments, verification, docNeed: [...], docRationale }`. Set `addedComments` true only if you added or changed a code comment (it gates the comment-cleanup stage).
