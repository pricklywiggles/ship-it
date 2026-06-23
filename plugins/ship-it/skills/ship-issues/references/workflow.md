# Lane grouping and the batch Workflow

Read before Phase 5. It covers (1) turning scoped work-units into concurrent lanes and (2) the Workflow script to adapt and launch.

## 1. Grouping into lanes

The aim: maximize concurrency without letting two work-units' PRs collide. Two collide only if they edit the same file.

1. From the Phase 2 plan pass (or scope pass, when planning is off) you have, per work-unit, a predicted set of files. Normalize to repo-relative paths; a directory or component area covers any file under it.
2. Build an undirected graph: one node per work-unit, an edge between two whose predicted file sets intersect. Be conservative: if two clearly work the same feature even with slightly different predicted paths, draw the edge. A false overlap costs a little parallelism; a false independence costs a merge conflict.
3. The connected components are the **lanes**. One work-unit = independent; several = a collision cluster.
4. Order within a lane (ascending id is a fine default). The lane runs sequentially on stacked branches:
   - item[0]: `base` = `config.repo.mainBranch`, `prBase` = same.
   - item[k>0]: `base` = item[k-1].branch, `prBase` = item[k-1].branch.
5. Lanes run concurrently with each other.

Common case: every work-unit is in a different area, so every lane has one item and the whole batch runs concurrently off main. Worktree creation: lane heads are pre-created in Phase 4; stacked children cannot be (their base has no commits yet), so each child's `fix-one-issue` step creates its own worktree off the parent after the parent commits.

## 2. The Workflow script

Adapt the template: pass `args = { main, repo, configPath, lanes, maxLanes, docJobs }`, where `configPath` points at the project's `ship-it.config`, `maxLanes` is `config.concurrency.maxLanes` (the cap on how many lanes run at once), `docJobs` is the **author-reconcile** entries of `config.docs.jobs` (authored on-branch so they ride the PR), and each work-unit object is `{ id, title, desc, branch, base, prBase, wt, url, focus, plan }` (`focus` is the scoped approach + predicted files from Phase 2; `plan` is the approved plan from the Phase 2 plan pass, present when `config.planning.enabled`). Launch with the **Workflow** tool. At most `maxLanes` lanes run concurrently (a worker pool over lanes); within a lane the items run as an awaited sequential loop, so issues stacked in a lane stay sequential.

The per-work-unit pipeline **invokes the ship-it stage skills**; it does not reimplement them. The stage skills read `ship-it.config` themselves, so the agent prompts are thin wrappers that hand over the work-unit and the config path.

```javascript
export const meta = {
  name: 'ship-it-batch',
  description: 'Ship a batch of work-units: implement, comment-cleanup, review and address, push and PR; lanes concurrent, stacked within a lane',
  phases: [{ title: 'Implement' }, { title: 'Comments' }, { title: 'Review' }, { title: 'Docs' }, { title: 'Finalize' }],
}

const { main, repo, configPath, lanes, maxLanes, docJobs } = args

const IMPL_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['issueId', 'implemented', 'committed', 'summary', 'filesChanged', 'addedComments', 'verification', 'docNeed'],
  properties: {
    issueId: { type: 'string' }, implemented: { type: 'boolean' }, committed: { type: 'boolean' },
    summary: { type: 'string' }, filesChanged: { type: 'array', items: { type: 'string' } },
    addedComments: { type: 'boolean' }, verification: { type: 'string' }, notes: { type: 'string' },
    docNeed: { type: 'array', items: { type: 'string' } }, docRationale: { type: 'string' },
  },
}
const CLEANUP_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['issueId', 'changed', 'summary'],
  properties: { issueId: { type: 'string' }, changed: { type: 'boolean' }, summary: { type: 'string' }, verification: { type: 'string' } },
}
const REVIEW_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['issueId', 'findings', 'applied', 'skipped'],
  properties: {
    issueId: { type: 'string' },
    findings: { type: 'array', items: { type: 'object' } },
    applied: { type: 'array', items: { type: 'string' } },
    skipped: { type: 'array', items: { type: 'string' } },
    verification: { type: 'string' },
  },
}
const FINAL_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['issueId', 'pushed', 'prUrl', 'finalSummary'],
  properties: {
    issueId: { type: 'string' }, pushed: { type: 'boolean' }, prUrl: { type: 'string' }, prNumber: { type: 'number' },
    finalSummary: { type: 'string' }, verification: { type: 'string' }, notes: { type: 'string' },
  },
}

// Thin wrapper: hand the work-unit and config path to a stage skill and return its structured result.
function invoke(skill, issue, extra = '') {
  return `Invoke the ${skill} skill (Skill tool) on this work-unit, reading the project config at ${configPath}:
${JSON.stringify(issue)}
${extra}
Do all work inside ${issue.wt}; never touch ${main}. Return only the skill's structured result.`
}

async function runIssue(issue) {
  const impl = await agent(invoke('ship-it:fix-one-issue', issue, 'Implement against issue.plan when present; for a stacked child, first reconcile the plan with the parent changes already on its base.'), { label: `impl:${issue.id}`, phase: 'Implement', schema: IMPL_SCHEMA })
  if (!impl || !impl.committed) {
    return { issueId: issue.id, pushed: false, prUrl: '', finalSummary: 'implement did not complete', notes: (impl && impl.notes) || 'impl failed' }
  }
  // comment-cleanup is code-modifying: sequential within the lane, never concurrent with review/finalize on this worktree.
  let cleanup = null
  if (impl.addedComments) {
    cleanup = await agent(invoke('ship-it:comment-cleanup', issue, `Scope to the commit range ${issue.base}...HEAD in ${issue.wt}. Apply mode. Commit, do not push.`),
      { label: `comments:${issue.id}`, phase: 'Comments', schema: CLEANUP_SCHEMA })
  }
  const review = await agent(invoke('ship-it:review-and-address', issue, `Review the diff ${issue.base}...HEAD. Apply warranted per config.review.applyWarranted. Commit, do not push.`),
    { label: `review:${issue.id}`, phase: 'Review', schema: REVIEW_SCHEMA })
  // author-reconcile docs on-branch BEFORE open-pr, so the artifact rides the original push (references/doc-jobs.md).
  for (const job of (docJobs || []).filter((j) => j.mechanic === 'author-reconcile' && (impl.docNeed || []).includes(j.appliesWhen))) {
    await agent(`In ${issue.wt}, author the "${job.name}" doc artifact for this work-unit by invoking ${job.ref} over the diff ${issue.base}...HEAD, then commit it on ${issue.branch} (do not push). It must ride this PR.`,
      { label: `doc:${job.name}:${issue.id}`, phase: 'Docs' })
  }
  const fin = await agent(invoke('ship-it:open-pr', issue, `Push ${issue.branch} to ${repo} and open its PR with base ${issue.prBase}. Build the body from config.prTemplate (two-part Verification).`),
    { label: `pr:${issue.id}`, phase: 'Finalize', schema: FINAL_SCHEMA })
  return { ...fin, docNeed: impl.docNeed, docRationale: impl.docRationale, addedComments: impl.addedComments, review }
}

const laneCap = Math.max(1, maxLanes || 4)
log(`Shipping ${lanes.flat().length} work-unit(s) across ${lanes.length} lane(s), at most ${laneCap} lane(s) at a time`)

// Concurrency is capped at the LANE level (config.concurrency.maxLanes), not the issue level:
// laneCap worker thunks pull whole lanes from a shared queue, so at most laneCap lanes are in
// flight at once. Within a lane, issues still run sequentially on their stacked branches, and a
// multi-issue lane occupies one slot for its whole run.
const laneResults = new Array(lanes.length)
let nextLane = 0
await parallel(
  Array.from({ length: Math.min(laneCap, lanes.length) }, () => async () => {
    for (let i = nextLane++; i < lanes.length; i = nextLane++) {
      const results = []
      for (const issue of lanes[i]) results.push(await runIssue(issue))
      laneResults[i] = results
    }
  }),
)

return { results: laneResults.flat() }
```

### Notes

- Pass `args` as a real JSON object to the Workflow tool: `{ main, repo, configPath, lanes, maxLanes }`. Do not stringify it.
- The per-stage agents invoke the stage skills, which read `ship-it.config` themselves; keep the prompts thin so the skills stay the single source of truth.
- The Phase 2 plan pass (one `Plan` agent per work-unit invoking `ship-it:plan-one-issue`) runs before this Workflow; each work-unit's approved `plan` rides in its object, and `fix-one-issue` implements against it.
- If a stage skill fails to resolve or returns null, the issue degrades rather than crashing the batch (finalize just has less to act on).
- After the Workflow returns: read the per-work-unit results (including `docNeed`), run Phase 6 (doc-job fan-out), launch Phase 7 watchers, then print the Phase 8 summary. Verify PRs with `gh pr list`.
