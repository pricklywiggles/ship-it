# Doc jobs: keeping living docs current

Read before Phase 6. The doc phase runs the configured doc jobs (`config.docs.jobs`) whose trigger (`appliesWhen`) matched a shipped work-unit. Jobs run in parallel (each owns a different file). Every job is one of three mechanics.

## DocJob

```
DocJob { name, mechanic: "regenerate" | "author-reconcile" | "curate-serial", ref, target?, appliesWhen? }
```

`ref` is a command (regenerate), or a skill (author / curate). `appliesWhen` is the classification `fix-one-issue` emits (e.g. capability, design, architecture); a job runs when a shipped work-unit's `docNeed` includes it.

## The three mechanics

### regenerate
Re-derive the doc from the merged code; no authoring. Run the job's command, e.g. `graphify update .`. Idempotent and cheap, but it reads the code, so run it **after the feature PRs merge** (the pre-merge base branch does not have the changes yet), once, alongside any author-reconcile reconcile. If the job's `target` is gitignored (e.g. `graphify-out/`), it produces no committed artifact and no docs PR, just a local cache refresh, so it needs no merge-watcher: surface it as a manual post-merge command instead. Built-in: **graphify**.

### author-reconcile
Two steps split across the merge boundary:
1. **Author** (per work-unit, on its branch, rides the PR): during the run, author the artifact for that work-unit (e.g. an OpenSpec change via `openspec-propose`) and commit it on the branch. Concurrent, per work-unit, since each artifact is its own file.
2. **Reconcile** (post-merge, once): after the feature PRs merge, fold the authored artifacts into the canonical docs and open one batched docs PR. Built-in: **openspec**, reconcile = `${CLAUDE_PLUGIN_ROOT}/scripts/openspec-archive.sh` (merged-gated `openspec archive`). The merge-watcher triggers it (Phase 7).

### curate-serial
Update a shared prose doc, serialized because the file is shared. The workers only CLASSIFY (does this change the doc?); the actual write happens once, after the Workflow, by invoking the curator skill (e.g. `impeccable` for DESIGN.md). When exactly one shipped work-unit triggers it, author the update on that work-unit's branch and push it onto that PR (atomic doc + code, no separate stale-on-main docs PR); only when several trigger it do one consolidated pass on a separate docs branch. Built-in: **impeccable** (DESIGN.md). A hand-written prose doc (e.g. ARCHITECTURE.md) uses a generated curate-serial job that `init` writes.

## Fan-out (Phase 6)

After the Workflow returns, collect each shipped work-unit's `docNeed`. For each job in `config.docs.jobs` whose `appliesWhen` matched at least one, run it, in parallel across jobs (different files):
- **regenerate**: defer to post-merge (Phase 7), like an author-reconcile reconcile; running it against the pre-merge base would capture none of the batch's changes.
- **author-reconcile**: the author step already ran per work-unit during the Workflow; defer the reconcile to post-merge (Phase 7).
- **curate-serial**: do the single serial write now. If exactly one work-unit triggered it, commit it onto that work-unit's PR branch (rides the PR); if several, one consolidated pass on a separate docs branch.

Skip jobs with no match. Most work-units are `none`; do not over-document.

## Post-merge reconcile (Phase 7)

For author-reconcile **and regenerate** jobs, the canonical or derived docs only update after the feature PRs merge. Launch the merge-watcher **only when the post-merge work produces a tracked change** (an author-reconcile archive that edits committed specs, or a regenerate whose `target` is tracked); if the only post-merge job is a regenerate to a gitignored target (e.g. `graphify-out/`), there is no docs PR to open, so skip the watcher and surface the command as a manual local refresh:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/watch-merges.sh" --prs <pr-csv> --reconcile "<reconcile command>"
```

`<reconcile command>` composes every post-merge doc job joined with `&&`: each author-reconcile reconcile (e.g. `"${CLAUDE_PLUGIN_ROOT}/scripts/openspec-archive.sh" <change-ids>`) and each regenerate command (e.g. `graphify update .`). The watcher polls until the PRs are merged or closed (or a timeout), then runs it against the merged code, archiving specs, regenerating derived docs, and opening the batched docs PR. On timeout it prints the manual command. In-session only; closing the session falls back to running it by hand.

## Built-in jobs

| name | mechanic | ref | target |
|---|---|---|---|
| graphify | regenerate | `graphify update .` | `graphify-out/` |
| openspec | author-reconcile | `openspec-propose` (author) + `scripts/openspec-archive.sh` (reconcile) | `openspec/` |
| impeccable | curate-serial | `impeccable` | `DESIGN.md` |

Any other doc is a generated curate-serial (or regenerate) job that `init` writes as a project-local skill.
