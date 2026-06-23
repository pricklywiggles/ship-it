---
name: plan-one-issue
description: Produce a comprehensive, reviewable implementation plan for a single work-unit before any code is written. Reads the real code (not just locates it), weighs the alternatives, names the existing utilities to reuse, and lays out context, approach, the per-file changes, the key decisions, edge cases, verification, and risks, scaled to the work's complexity. Read-only; emits the plan plus predicted files and a preliminary doc classification. Use for "plan this issue", "draft a plan for FRA-123", "scope and plan this ticket before coding", "what's the approach for this work-unit". The planning stage of the ship-it orchestrator, and usable standalone on an issue or a described task. Not for implementing (use fix-one-issue), batch-shipping many issues (use ship-issues), review (review-and-address), or just listing issues.
allowed-tools: Bash, Read, Grep, Glob, WebFetch, WebSearch, ToolSearch
---

# plan-one-issue: a comprehensive, read-only plan for one work-unit

Produce the plan a careful engineer would write before touching code: grounded in the real codebase, weighing the obvious alternatives, and spelling out the change, the decisions, the edge cases, and how it will be verified. The deliberate planning stage; it runs concurrently (one per work-unit) inside the orchestrator and standalone on its own. Read-only: no edits, no commits, no worktrees.

## 1. Resolve the work-unit

- **Orchestrated**: you are given a work-unit (`id`, `title`, `desc`, `branch`, `base`, `url`). Reason read-only against `base` (or the current checkout); do NOT create a worktree.
- **Standalone**: given an issue id, fetch its intent (the default source); given a described task, use the text directly.

## 2. Read config

Load the resolved config via `${CLAUDE_PLUGIN_ROOT}/scripts/load-config.sh`; read keys with `jq`:
- `houseRules` / `safety` (the plan must respect them, e.g. code-only verification, or a "read the framework doc first" rail),
- `verify` (so the plan's verification section names the real checks),
- `planning.depth` (`light` | `adaptive` | `full`; see step 4),
- `docs.jobs` (their `name` + `appliesWhen`, to classify `docNeed`).

## 3. Explore deeply (read-only)

This is what separates a real plan from a guess. Do not stop at locating files:
1. **Read the code the change will touch.** Open the relevant files and understand the actual symbols, signatures, types, and surrounding patterns. If `graphify-out/` exists, query the graph to find the right nodes fast, then read them.
2. **Find what to reuse.** Identify the existing utilities, hooks, types, and conventions the change should build on rather than reinventing, and name them.
3. **Verify every external API the plan will rely on, against the installed version. Never propose a package, framework, or platform call from memory.** Training data lags the version this project actually has, and a confidently wrong API (a hallucinated attribute, a renamed option, a signature that changed) is how a whole plan rots. Read the version from `package.json` / the lockfile (or `Cargo.toml`, `go.mod`, ...), then confirm each non-obvious call exists with the signature and behavior you assume, checking: the package's own shipped docs and types in `node_modules` (many now ship a `docs/` folder, an `llms.txt`, an `AGENTS.md`, a README, or `.d.ts` types for exactly this, e.g. `node_modules/next/dist/docs/`); the installed source itself, wherever the ecosystem installs it (`node_modules` for JS/TS, `~/.cargo/registry/src` for Rust crates, `site-packages` for Python, `vendor/` for Go), not just `node_modules`; and version-pinned official docs via the **context7** MCP tool (resolve the library, then query the specific API) or the official docs site. The same goes for **network service calls** (REST / GraphQL / RPC, an LLM, payment, or platform API): confirm the endpoints, the request and response shape, auth, pagination, and error handling against the service's current, version-pinned reference (its docs, an OpenAPI or GraphQL schema, an `llms.txt`, or context7) and against the API version the project targets (a version header, a `/vN/` base path, or the SDK version, which can itself lag the live service). Verify service shapes from docs and schemas, never by making a live call to the endpoint. If you cannot confirm a call, do not assert it: mark it in the plan as an assumption to verify during implementation, or choose an API you can confirm. A flagged unknown is fine; a confident hallucination is not.
4. **Weigh the obvious alternatives.** When there is more than one reasonable way, compare them briefly and pick one; record the road not taken when the choice is non-obvious.
5. If the ticket already carries a plan or acceptance criteria, treat it as the **seed to validate and refine against the real code, never discard it**.
6. **Note unknowns** that would change the implementation as `openQuestions`. Do not ask here; the orchestrator surfaces them at its checkpoint, and standalone you surface them in the output.

## 4. Write the plan

Scale the depth to the work and to `config.planning.depth`:
- **`full`**: always write every section below, even for small work.
- **`adaptive`** (default): a trivial single-file tweak gets a tight Context + Changes + Verification; anything non-trivial (a new module or subsystem, several files, a new pattern, or a non-obvious decision) gets every section.
- **`light`**: the files, a one-line approach, and the verification note. Minimal.

The sections of a comprehensive plan:
- **Context**: the problem and the intended outcome, in the work-unit's terms.
- **Approach**: the recommended strategy. When the choice is non-obvious, name the alternative you rejected and why.
- **Changes**: the critical files, each with what changes and which existing utilities or patterns to reuse (named, with paths). This is the spine the implement stage builds against.
- **Key decisions**: the non-obvious calls and their rationale (which library or API and why, sync vs async, a security or correctness caveat, a data-shape choice).
- **Edge cases and failure modes**: what breaks it, and how the plan handles each.
- **Verification**: the concrete `config.verify` checks, plus, for a code-only project, what is left to human QA and any unit test worth adding.
- **Risks / out of scope**: what could go wrong, and what this work deliberately does not include.

A good plan is the smallest correct change, fully reasoned: what to change, where, why, the decisions that matter, and how you will know it works. Resolve this work-unit only; do not fold in adjacent cleanups.

## 5. Classify documentation impact (preliminary)

For each `config.docs.jobs`, decide whether the planned change meets its trigger (`appliesWhen`): a user-facing capability / behavior / route / data-path change, a reusable visual or design-system primitive, an architectural decision or boundary shift, and so on. Return the matching job names. This is preliminary: `fix-one-issue` confirms it against the actual change. Most changes are none; do not over-classify.

## Output

- **Standalone**: print the plan, the predicted files, and the doc classification. Note that under the orchestrator the plan is posted to the source for review (`config.planning.postBack`); offer to post it if asked.
- **Called by the orchestrator**: a structured result, `{ issueId, plan, predictedFiles, docNeed: [...], docRationale, complexity, openQuestions: [...] }`. `plan` is the comprehensive markdown the implement stage builds against; `complexity` is exactly one of `trivial` | `normal` | `complex`; `predictedFiles` feeds lane grouping; `openQuestions` feed the checkpoint.

## Guardrails

- Read-only: never edit, commit, push, or create a worktree. Planning only.
- Ground every step in code and docs you actually read; never plan against a guessed API, always verify it against the installed version (step 3). Graphify is an accelerator when present, never a requirement.
- Right-size: a trivial change gets a tight plan, not ceremony; a real change gets the full reasoning. Match and refine a ticket that already plans well.
- Honor `houseRules` + `safety` in the plan itself (no em dashes, no AI attribution; carry project rails like code-only verification into the verification section).
- Non-interactive: surface `openQuestions` in the result; do not block.
