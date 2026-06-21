# Doc jobs: keeping living docs current

Read before Phase 6. The doc phase runs the configured doc jobs (`config.docs.jobs`) whose trigger (`appliesWhen`) matched a shipped work-unit. Jobs run in parallel (each owns a different file). Every job is one of three mechanics.

## DocJob

```
DocJob { name, mechanic: "regenerate" | "author-reconcile" | "curate-serial", ref, target?, appliesWhen? }
```

`ref` is a command (regenerate), or a skill (author / curate). `appliesWhen` is the classification `fix-one-issue` emits (e.g. capability, design, architecture); a job runs when a shipped work-unit's `docNeed` includes it.

## The three mechanics

### regenerate
Re-derive the doc from the merged code; no authoring. Run the job's command, e.g. `graphify update .`. Idempotent and cheap; run it once after the batch. Built-in: **graphify**.

### author-reconcile
Two steps split across the merge boundary:
1. **Author** (per work-unit, on its branch, rides the PR): during the run, author the artifact for that work-unit (e.g. an OpenSpec change via `openspec-propose`) and commit it on the branch. Concurrent, per work-unit, since each artifact is its own file.
2. **Reconcile** (post-merge, once): after the feature PRs merge, fold the authored artifacts into the canonical docs and open one batched docs PR. Built-in: **openspec**, reconcile = `${CLAUDE_PLUGIN_ROOT}/scripts/openspec-archive.sh` (merged-gated `openspec archive`). The merge-watcher triggers it (Phase 7).

### curate-serial
Update a shared prose doc, serialized because the file is shared. The workers only CLASSIFY (does this change the doc?); the actual write happens once, after the Workflow, by invoking the curator skill (e.g. `impeccable` for DESIGN.md). If several work-units trigger it, do one consolidated pass on a docs branch. Built-in: **impeccable** (DESIGN.md). A hand-written prose doc (e.g. ARCHITECTURE.md) uses a generated curate-serial job that `init` writes.

## Fan-out (Phase 6)

After the Workflow returns, collect each shipped work-unit's `docNeed`. For each job in `config.docs.jobs` whose `appliesWhen` matched at least one, run it, in parallel across jobs (different files):
- **regenerate**: run the command.
- **author-reconcile**: the author step already ran per work-unit during the Workflow; defer the reconcile to post-merge (Phase 7).
- **curate-serial**: do the single serial write now (consolidated if several triggered it).

Skip jobs with no match. Most work-units are `none`; do not over-document.

## Post-merge reconcile (Phase 7)

For author-reconcile jobs, the canonical docs only update after the feature PRs merge. Launch the merge-watcher:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/watch-merges.sh" --prs <pr-csv> --reconcile "<reconcile command>"
```

It polls until the PRs are merged or closed (or a timeout), then runs the reconcile (e.g. `"${CLAUDE_PLUGIN_ROOT}/scripts/openspec-archive.sh" <change-ids>`), which opens the batched docs PR. On timeout it prints the manual reconcile command. In-session only; closing the session falls back to running the reconcile by hand.

## Built-in jobs

| name | mechanic | ref | target |
|---|---|---|---|
| graphify | regenerate | `graphify update .` | `graphify-out/` |
| openspec | author-reconcile | `openspec-propose` (author) + `scripts/openspec-archive.sh` (reconcile) | `openspec/` |
| impeccable | curate-serial | `impeccable` | `DESIGN.md` |

Any other doc is a generated curate-serial (or regenerate) job that `init` writes as a project-local skill.
