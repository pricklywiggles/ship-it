---
name: setup-stack
description: Use this skill to run the entire stack-it pipeline end to end in one guided pass — it takes a project from nothing to a working, verified, documented tech stack by running each stage skill in order (identify-stack-slots, decide-stack, install-stack, scaffold-and-verify, document-stack), resumes from wherever the project already is, optionally sets up git and commits a checkpoint after each stage, and keeps a running task list so the user can see how much is left. Use it whenever someone wants their whole stack set up rather than just one step — phrasings like "set up my stack", "set up my whole project stack", "help me start a new project from scratch", "pick, install, and verify my stack", "take me from zero to a working project", "bootstrap my project", or "run the whole stack-it pipeline" should trigger it. It pauses only where it genuinely needs the user (their tool picks in the decide stage, an install confirmation, a stack-fault re-pick, an OK before writing docs) and handles the loop where a broken tool sends verification back to re-decide. Reach for the individual stage skills instead when the user explicitly wants only one step (only choose tools, only install, only document); this orchestrator is for the full journey. It does not reimplement the stages — it sequences them.
---

# Set Up Stack

The orchestrator for the stack-it pipeline. It takes a project from nothing to a working, verified, documented tech stack by running the five stage skills in order, resuming from wherever the project already is and pausing only where a human is genuinely needed. Each stage is a real skill with its own `SKILL.md`; this skill's job is to **sequence** them, carry the `.claude/stack-it/` artifacts between them, and handle the one loop where verification sends a bad choice back to be re-decided. Defer to each stage for *how* that stage works — don't reimplement it here.

## The pipeline

| # | Stage skill | Produces / does |
|---|---|---|
| 1 | `identify-stack-slots` | `.claude/stack-it/slots.yaml` — the decision categories |
| 2 | `decide-stack` | `.claude/stack-it/stack.yaml` — concrete, pinned, vetted choices |
| 3 | `install-stack` | installs the locked stack; updates `stack.yaml` to match reality |
| 4 | `scaffold-and-verify` | builds a minimal slice and runs it green; updates `stack.yaml` on pin drift; **escalates a stack fault back to stage 2** |
| 5 | `document-stack` | `CLAUDE.md` + `README` documenting the stack |

Run each stage by following that stage's skill, not by re-deriving its behavior.

## Step 0: Set up the workspace

Before the first stage, get two things in place that you maintain for the rest of the run.

**Git.** Check whether the project is a git repository (`git rev-parse --is-inside-work-tree`). If it isn't, offer to initialize one — `git init` plus a baseline `.gitignore` appropriate to the project (keep the `.claude/stack-it/` artifacts; ignore build output, `node_modules`/`.venv`, and any `.env*` secrets). Ask once, batched with anything else you need up front; if the user declines, skip the commit steps below and just narrate progress. Working in git is strongly preferred — it lets you **checkpoint after every stage** (a clean rollback point that matters when `scaffold-and-verify` hits a stack fault and loops back), and the history is itself a resume signal. If the project is already a repo, note the current branch and whether the tree is clean before changing anything.

**The running task list.** Build the master list of everything the run will do and keep it current — it's how the user stays oriented through a long, sometimes-interactive process. Seed it with the five stages, then expand each into real sub-tasks as the artifacts appear: once `slots.yaml` exists, each open slot is a "decide" task; once `stack.yaml` exists, each entry is an "install" task and a "verify" task. Add and remove items as the stack changes (a deferred slot drops off; a stack-fault re-pick adds a task back). See **The running task list** below for how and when to show it.

## The running task list

Maintain one list for the whole run and **render it to the user between every stage**, with clear done / current / remaining markers, so they always know how much is left and never have to wonder "are we done yet?". Keep it concise — group by stage and show counts where a stage has many items. Update it whenever the work changes (slots added or deferred, tools chosen, a stack fault sending a slot back). Derive it from the `slots.yaml`/`stack.yaml` entries plus the fixed stage sequence — don't invent a separate tracking file.

Example shape (adapt freely):

```
stack-it progress
  [x] identify slots        (11 slots: 9 required, 2 optional)
  [>] decide stack          (4 / 11 chosen — contact-email, MDX, testing, component-sharing open)
  [ ] install
  [ ] scaffold & verify
  [ ] document
```

## The handoff contract

Whenever you stop and return control to the user, **end with one explicit line** so it's never ambiguous whether you're waiting on them or about to continue. Use one of two shapes:

- **Ready to proceed, no input needed** — `Next: <stage or action>. Reply "go" (or tell me to change something) when you're ready.`
- **You need something first** — `Before <next step>, I need <the specific thing>: <question>.`

State *the* next step, not a menu of everything they could do. This applies at every pause the pipeline makes — the decide-stage picks, the install confirmation, a stack-fault escalation, and the OK before docs.

## Step 1: Find the starting point (resume-aware)

Don't redo finished work. Before running anything, figure out where the project already is by inspecting:

- `.claude/stack-it/slots.yaml` — have the slots been identified? (validate with `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --stage slots` if present)
- `.claude/stack-it/stack.yaml` — have the tools been decided and locked? (validate with `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --stage stack`)
- the project itself — are the locked tools actually installed (manifests and lockfiles present, dependencies resolved)? is there a verification slice, and does it pass? do `CLAUDE.md`/`README` already document the stack?

Map what you find to the first **unfinished** stage:

- no `slots.yaml` → start at **identify-stack-slots**
- `slots.yaml` but no `stack.yaml` → start at **decide-stack**
- `stack.yaml` but the tools aren't installed → start at **install-stack**
- installed but no passing slice → start at **scaffold-and-verify**
- verified but undocumented → start at **document-stack**
- all done → say so; offer to re-run a specific stage

When the state is ambiguous (a `stack.yaml` exists and some deps look installed, but you can't tell it's complete), tell the user what you found and **confirm the entry stage** rather than guessing. A brand-new project with none of these artifacts starts at the top.

## Step 2: Run the stages in order

From the entry stage, run each subsequent stage in pipeline order. Between stages, every time: confirm the expected artifact is in place and valid before starting the next stage; **checkpoint the work** if git is enabled — commit the stage's artifacts and any files it produced with a conventional message (`chore(stack-it): identify slots`, `feat(stack-it): decide stack`, `feat(stack-it): install stack`, …) so each stage is a discrete, revertible point; and **show the user the running task list** plus a one-paragraph summary of what the stage produced and what's next.

Pause for the user only where a stage genuinely needs them; don't gate every step:

- **decide-stack** — their hard preferences and per-slot picks. Let the stage converse; that's its job.
- **install-stack** — confirmation before destructive, irreversible, or surprising commands. The stage handles this; don't add friction to routine installs.
- **scaffold-and-verify** — a stack-fault escalation (see Step 3).
- **before document-stack** — a quick "the stack's verified — write the docs now?" check.

Everywhere else, flow through: a successful, unambiguous stage rolls straight into the next with just a summary. The point of "guided" is that the user is informed and consulted at the real decision points, not interrupted at every one. Whenever you do pause, close with the handoff-contract line (see **The handoff contract**) so it's unambiguous whether you're waiting on them.

## Step 3: Handle the verify → decide loop

`scaffold-and-verify` sorts each failure into a slice fault (it fixes), pin drift (it fixes and records to `stack.yaml`), or a **stack fault** — a chosen tool that fundamentally can't work. On a stack fault it stops and escalates rather than papering over. When that happens, the loop is:

1. Surface the fault to the user with the stage's diagnosis (what failed, why it's the tool and not the slice).
2. Re-enter **decide-stack** for just the affected slot(s), with the new information, to re-pick. It edits the same `stack.yaml`.
3. Re-run **install-stack** for the changed slot(s), then **scaffold-and-verify** again.
4. Repeat until verification is green.

This loop is the whole reason the stages are separate skills — don't try to force a stack fault through inside verification. Keep the user in the loop on each re-pick; they own the stack decisions. Surface the fault and each re-pick with the handoff contract, update the task list (the affected slot goes back to "decide"), and checkpoint (commit) after each successful re-install-and-verify so every loop iteration is a clean rollback point.

## Step 4: Finish

Once verification is green and `document-stack` has written `CLAUDE.md` + `README`, give a final summary: the locked stack (tools and versions), what was installed, that the slice passed and which gates, where the docs live, and any caveats or pin drift recorded along the way. Point the user at the obvious next step (run the dev server, the test suite, the build) and flag anything still on them (accounts, secrets, env files). Make a final checkpoint commit for the docs if git is enabled, show the task list with everything done, and close with the handoff contract.

## Scope and boundaries

This skill sequences the five stage skills; it does not reimplement their logic, and it respects each stage's own boundaries (it won't enter credentials, and it routes stack decisions back through `decide-stack` and the user rather than deciding alone). The pipeline is the default path, not a mandate: if the user doesn't want docs, skip `document-stack`; if they hand you a partial state, resume mid-pipeline per Step 1. When the user explicitly wants only one step, point them at that stage's skill instead of running the whole journey.

## Bundled resources

- `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py` — Validate `.claude/stack-it/` artifacts while detecting the resume point (`--stage slots` for `slots.yaml`, `--stage stack` for `stack.yaml`). Run `python ${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --help` for usage.
