# ship-it: contracts and configuration

The design spec for the ship-it engine: the stable interfaces (contracts) that the orchestrators, stage skills, sources, reviewers, and doc jobs build against, and the per-project `ship-it.config` that `init` produces to adapt all of it to a project.

Living draft. The interfaces are the part to keep stable; the rest is refinable. See `ship-it.config.example.jsonc` for a filled instance (Sanum).

## The shape

ship-it is three layers:

1. **Orchestrators** (generic, project-agnostic): the batch issue-shipper (`ship-issues`) and the release-cutter (`cut-release`). They own lane grouping, the concurrent Workflow fan-out, the worktree lifecycle, and the post-PR watchers. They contain no project specifics.
2. **Stage skills** (reusable units of work): each operates on a *work-unit* and is individually callable, both from an orchestrator's parallel workers and by a user on its own.
3. **Per-project config** (`ship-it.config`): values, command strings, and adapter references that adapt the generic engine to a project. Produced by `init`.

**Concurrency rule.** A piece is concurrent when it is per-work-unit and invoked from inside a Workflow worker; it is serial only when it touches shared state. All human interaction is front-loaded into `init` and the plan checkpoint, so the workers run non-interactively and parallelize. Reviewers and doc jobs are parallel fan-outs over their configured lists.

## The work-unit

The universal currency. Every stage skill operates on one, regardless of where it came from.

```
WorkUnit {
  id?:       string   // tracker id (e.g. FRA-123); absent for ad-hoc/local work
  title?:    string
  desc?:     string   // full description / intent
  branch?:   string   // the branch carrying the change
  base?:     string   // base ref (default: repo.mainBranch)
  worktree?: string   // absolute path when work runs in a worktree
  url?:      string   // tracker / PR url
  prNumber?: number
}
```

The diff a stage reasons about is `git diff <base>...HEAD` in the work-unit's branch/worktree, or the working-tree diff for the current-changes source.

## Sources (produce work-units)

A source turns a request into one or more work-units. `init` sets the default; any source is usable ad hoc.

```
Source.resolve(selection) -> WorkUnit[]
```

Built-in sources:
- `tracker` — from an issue tracker. Selection is a status ("all todo"), a range ("fra-111-120"), or an explicit list. Carries id, title, desc, branch, url.
- `working-tree` — the current uncommitted (or committed-but-unpushed) changes as one work-unit. No tracker.
- `branch` — an existing branch as a work-unit.
- `pr` — an open PR as a work-unit (carries prNumber, branch).
- `describe` — an ad-hoc text task; the orchestrator creates the branch.

### Tracker adapter (the source that varies by project)

```
Tracker.resolve(selection) -> WorkUnit[]
Tracker.branchName(issue) -> string   // branch convention that carries the auto-close link
```

Built-in: `github-issues` (default, via gh), `linear` (via the Linear MCP). Others are project-provided skills/commands. A project with no tracker uses `working-tree` / `branch` / `describe`.

## Stage skills (operate on a work-unit)

Each is a standalone skill with a flexible front-door: invoked by an orchestrator it receives a work-unit; invoked alone it resolves one (default source, or an arg). Edits stay inside the work-unit's worktree; workers run non-interactively.

| Skill | Contract | Notes |
|---|---|---|
| `fix-one-issue` | implement the work-unit's intent, verify, commit | uses `houseRules` + `verify`; the core |
| `comment-cleanup` | audit + fix comments in the work-unit's diff | shipped (first inhabitant) |
| `review-and-address` | fan out `review.reviewers` over the diff, merge findings, optionally apply warranted | see Reviewers |
| `ci-fix` | watch the work-unit's PR CI, fix failures (bounded, cause-only) | primitive: `scripts/ci-watch.sh` |

## Reviewers (read-only, parallel fan-out)

`review-and-address` runs every configured reviewer over the work-unit's diff in parallel (read-only, so safe, and it nests inside the lanes), merges and de-duplicates the findings, then the address step applies the warranted ones (a write step, in finalize). Standalone, it reports the merged findings and offers to apply.

```
Reviewer {
  name:     string
  kind:     "agent" | "skill" | "command"
  ref:      string    // agentType, skill name, or shell command
  scope?:   "diff-with-base" | "files"      // default: diff-with-base
  install?: string    // "<plugin>@<marketplace>" hint init offers if missing
}
Reviewer.run(workUnit) -> Finding[]
Finding { severity, file, location?, issue, recommendation }
```

Default reviewer: `pr-review-toolkit`. More than one is allowed (e.g. `pr-review-toolkit:review-pr` + `vercel-react-best-practices`). `init` detects installed reviewers, offers to install the default if missing or lets the user pick another, and accepts several. Zero reviewers = review is a no-op with a note.

## Doc jobs (write docs, parallel fan-out)

The doc phase runs every configured doc job in parallel (each owns a different file, so it is safe). Every job is one of three mechanics:

- **regenerate-from-code** — re-derive the doc from merged code; no authoring. Examples: graphify (`graphify update .`), typedoc, API docs.
- **author-and-reconcile** — author a per-work-unit artifact alongside the change, reconcile into canonical docs after merge. Example: OpenSpec (author a change on the issue branch, archive into `specs/` post-merge).
- **curate-serial** — update a shared prose doc; serialized because the file is shared. Classify per-issue concurrently, write once. Examples: DESIGN.md (via impeccable), ARCHITECTURE.md.

```
DocJob {
  name:        string
  mechanic:    "regenerate" | "author-reconcile" | "curate-serial"
  ref:         string    // command, or skill name (e.g. impeccable, openspec-propose)
  target?:     string    // the doc path it owns
  appliesWhen?: string   // docNeed classification that triggers it
}
DocJob.run(shippedChanges, config) -> { changed, summary }
```

Built-in jobs: `graphify` (regenerate), `openspec` (author-reconcile), `impeccable` (curate-serial, DESIGN.md). For a doc with no built-in, `init` uses **skill-creator** to generate a doc-job skill from the user's description + chosen mechanic, and registers it. author-reconcile and curate-serial jobs classify per-issue inside the workers (concurrent) and do their shared write serially / post-merge.

## Orchestrators

### ship-issues (batch)
`resolve work-units (source)` -> `scope + group into lanes (overlap graph)` -> Workflow fan-out, per work-unit: `fix-one-issue` -> `comment-cleanup` (if comments changed) -> `review-and-address` -> `finalize` (apply review, push, open PR) -> `doc phase` (parallel doc jobs) -> post-PR watchers (CI fan-out per PR; merge watcher then archive). Lanes concurrent; stacked within a lane.

### cut-release
`analyze commits since last published release` -> `propose semver bump` -> `write user-facing notes` -> `open version-bump PR` -> after merge: `tag`, `watch build`, `publish notes`. Project specifics (version source, tag format, notes style, build to watch) are config.

## ship-it.config keys

JSON (JSONC accepted). Most keys optional; detection + defaults fill the rest. See the example file for concrete Sanum values.

| Key | Purpose |
|---|---|
| `repo.mainBranch` | base branch (default `main`) |
| `repo.mergeStrategy` | `squash` / `merge` / `rebase`; affects stacked-PR + archive logic (squash can strand stacked children) |
| `source.default` | which source the orchestrator uses by default |
| `source.tracker` | tracker type + project/team/idPrefix (or a custom resolver ref) |
| `houseRules` | text, or `@FILE` to derive from AGENTS.md/CLAUDE.md; injected into every worker prompt |
| `safety` | hard rails carried by every worker (e.g. "no personal health data") |
| `verify` | command(s) run inside the worktree after a change; `{changedFiles}` placeholder |
| `worktree.enabled` / `.root` / `.prepare` | worktree on/off, location, and the make-runnable hook |
| `concurrency.maxLanes` | parallel lane cap |
| `review.reviewers` | the reviewer list (parallel fan-out) |
| `ci.watch` / `.fixAttempts` | CI watch + bounded auto-fix |
| `docs.jobs` | the doc-job list (parallel fan-out) |
| `prTemplate` | PR body shape (Summary / tracker link / two-part Verification) |
| `release.*` | cut-release: version source, tag format, notes style, build to watch |

## init

Detect-first, ask-second. Detects package manager, verify command, CI system, tracker, doc tools, and installed reviewers from the repo; asks only for what it cannot infer (tracker project/team, safety rails, which doc jobs + reviewers, merge strategy); generates doc-job skills for novel docs via skill-creator; runs a prerequisite + auth check (tracker MCP, gh, doc-tool binaries); writes `ship-it.config`. All interactivity lives here, so the workers stay parallel and non-interactive.

## Plugin packaging notes

- **Namespacing.** Plugin skills are always `ship-it:<skill>` (e.g. `ship-it:comment-cleanup`). Cross-references and docs use the namespaced form.
- **`${CLAUDE_PLUGIN_ROOT}`.** Installed plugins run from a copied cache, so the orchestrator references its own bundled scripts as `${CLAUDE_PLUGIN_ROOT}/scripts/...`, never repo-relative. The scripts themselves operate on the *user's* repo via `git rev-parse --show-toplevel`, which is correct and unaffected.
- **No `../`.** A plugin cannot reference files outside its own directory; everything it ships lives inside it.
- **Calling other plugins.** Invoking another plugin's agent/skill (e.g. a configured reviewer) is runtime resolution and works if that plugin is installed; it is unaffected by caching. To guarantee a reviewer is present, a project can declare it in `dependencies` (cross-marketplace ones, like `pr-review-toolkit@claude-plugins-official`, require `allowCrossMarketplaceDependenciesOn` in the marketplace), or `init` directs the user to install it.

## Status

- **Built (in plugin)**: stage skills `comment-cleanup`, `ci-fix`, `review-and-address`, `fix-one-issue`; the `ship-issues` orchestrator (lanes + the Workflow template chaining the stage skills) with built-in **sources** resolution (tracker via github-issues/linear, plus working-tree/branch/pr/describe and the custom-tracker extension point); the **`init`** front-door skill (detect + interview + write `ship-it.config` + generate novel doc-job skills via skill-creator); bundled `scripts/ci-watch.sh`.
- **To build, in order**: a shared **config-loader** (so skills stop reading `ship-it.config` ad hoc); the **worktree + post-PR lifecycle scripts** (extract the inline `git worktree` / setup / cleanup / merge-watch logic, and turn the OpenSpec-archive and graphify steps into doc jobs); the **doc-job runners** for the three mechanics; generalize **`cut-release`**; then validate on a second, non-Sanum repo.
