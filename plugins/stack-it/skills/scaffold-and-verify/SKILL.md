---
name: scaffold-and-verify
description: Use this skill to prove a freshly installed project stack actually works before building anything real on it: generate the smallest example that exercises every chosen tool together, then run it until build, lint, tests, and the dev server are all green (plus a real-browser console check when there's a UI). This is the verification stage of the stack-it pipeline, after install-stack. Use it proactively, even when the user never says "verify", whenever a stack or its dependencies were just installed or scaffolded and someone wants confidence the pieces fit. Phrasings like "I just installed my stack, make sure it works", "build a minimal example that uses all of it and run it", "smoke-test my new project setup", "prove the stack works", "scaffold a smoke test", "keep fixing the example until tests/build/lint/the dev server pass", "do my pinned versions actually work together", or handing over a locked stack YAML plus an installed project and asking for confidence before building for real. It writes a thin end-to-end slice (e.g. a styled page with a form and one component test, or one API endpoint persisting through the ORM with a request test, or a CLI subcommand that runs), loops fix-and-retry until every check passes, and, when a chosen tool turns out broken or two pinned versions are fundamentally incompatible, stops and brings the user back to decide-stack rather than silently swapping or bumping. It does NOT design the architecture of the real app, and is not for choosing tools (use decide-stack), running the install commands (use install-stack), running or fixing tests in an existing or mature project, adding a dependency or feature to an app already under development, setting up CI configuration, or debugging a running production app.
---

# Scaffold and Verify

The verification stage of the stack-it pipeline. The tools are installed (`install-stack` ran); now confirm they actually work **together** before the user builds anything real on top of them. Do this by generating the smallest meaningful slice of a working app that touches every tool in the stack, then running every check until it's all green. A passing slice is the proof; an unrun stack is an unverified one.

## Input

Expect the locked stack YAML from `decide-stack` (the same file `install-stack` consumed), by default at **`.claude/stack-it/stack.yaml`** (or a path the user gives), plus the installed project on disk:

```yaml
project: { description: ..., type: ..., platforms: [...] }
stack:
  - slot: <category>
    choice: <chosen tool>
    version: <exact pinned version>
    install: [...]
    caveats: [...]
    notes: <or null>
```

Validate the YAML first with `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --stage stack .claude/stack-it/stack.yaml` so a malformed handoff fails before you write any code. If there's no installed project yet, point the user to `install-stack`; this skill verifies an install, it doesn't perform one. Surface any `caveats` from the file now, because a known issue is the first thing to suspect when a check fails.

## The core idea: one vertical slice, not N hello-worlds

It's tempting to smoke-test each tool in isolation: a bare component here, a lone test there. Resist that. Tools fail at the *seams*: the form library's markup styled by the CSS tool, rendered by the framework, asserted by the test runner, accepted by the linter, bundled by the build, served by the dev server. A single thin path that runs through every tool at once is what catches version mismatches, config that doesn't compose, and plugins that don't actually load. Build **one** end-to-end slice that every tool in the stack participates in, and keep it as small as it can be while still being real.

"Real" matters: the slice must exercise each tool in a way that would genuinely break if that tool were misconfigured. A test that asserts `true` proves nothing. A page that imports the form library but renders no form proves nothing.

## Step 1: Map each tool to a role in the slice

Read the `stack` and decide what the smallest honest slice looks like for *this* project type. Each entry should have a job in the slice:

- **Web app**: one route/page that renders a small form built with the chosen form library, styled with the chosen CSS tool, with one component test (e.g. RTL) that renders it and asserts on real behavior, plus lint, build, and the dev server.
- **API service**: one endpoint wired through the chosen router, reading/writing one record through the chosen DB layer, with one request test that hits it, plus lint and build.
- **CLI**: one subcommand that does one real thing through the chosen arg/parse and core libs, with one test invoking it, plus lint and build.
- **Library**: one exported function exercising the core dependency, with one test, plus lint, build, and (if configured) the docs/typecheck step.

These are starting points, not a menu; derive the slice from the actual stack. Note which tools are **testable** (frameworks, libraries, the things your code calls) versus **tooling** that's verified by *running it*, not by a unit test (linters, formatters, bundlers, type checkers, CI). Every tool should end up covered by one or the other.

## Step 2: Generate the slice

Write the smallest code that gives every tool a real job, following each tool's own idioms and official starter patterns rather than inventing your own structure. Add **one real test per testable tool**: a test that would fail if that tool were broken or absent. Keep the whole thing in one obvious place in the project so it's easy to delete or grow later; tell the user where it lives and that it's a scaffold, not the real app.

## Step 3: Run the green gates

Verification is the slow part of this skill (a full install, a test run, and a browser drive each cost real wall-clock), so run the gates with their actual dependencies in mind rather than one slow serial pass. Gates that don't depend on each other should run **concurrently**, and you should collect *every* failure in a wave before fixing, so the fix loop sees the whole picture at once instead of discovering problems one round at a time.

The gates fall into two waves by dependency:

**Wave 1: static checks, run concurrently.** Once the slice exists, these are independent of each other and have no runtime, so launch them together and gather all their failures:

1. **Build / compile**: the project builds cleanly at the pinned versions.
2. **Lint / format**: the chosen linter and formatter run clean on the slice.
3. **Tests**: every test you wrote passes, and passes for the right reason (a test that can't fail is a failure).

**Wave 2: runtime checks, ordered.** These need a working build, so they follow Wave 1, and they have an internal order:

4. **Dev server / runtime boots**: the app actually starts and serves (or the CLI runs, the library imports), not just builds.
5. **Browser visual check**: *when the slice has a browser-visible UI*, and only once the server from gate 4 is serving, use the `agent-browser` skill to load it, confirm it renders as intended, and check the console for errors and warnings. A clean build with a red console is not green. Skip this gate for projects with no browser surface (CLI, API, library) and say so. (This one depends on gate 4, so it can't be parallelized with it.)

**Local-first CI** is not a separate wave: it's the same commands the project's CI config would run, executed locally so a green checkout is reproducible. Drive it through the project's own scripts rather than re-charging the work by hand. If (and only if) a git remote exists, offer to push a branch and watch the real provider go green; don't require a remote for this skill to pass.

## Step 4: The fix loop

When a gate fails, the first decision is *whose fault it is*, because that determines whether you fix it, fix-and-flag it, or stop:

- **Slice fault.** The example is wrong: a typo, a missing import, a misused API, a config you can correct. Fix the slice and rerun the affected gates. This is the normal case; converge it yourself and move on.
- **Pin drift.** The *choice* is sound but the exact pinned `version` is off: it was never published, or it needs a patch bump within the same minor to satisfy a peer range (e.g. a plugin pinned below the version that supports the installed major). This is trivially fixable (install the nearest compatible patch of the same minor and keep going), but it is **not** silent housekeeping. A pin that doesn't install means `decide-stack` emitted a bad lock, so update the locked YAML (`.claude/stack-it/stack.yaml`) in place with the version you actually used, and surface it **prominently** in your report (which pin, what you bumped it to, why). Fix to keep moving, persist the fix to the lockfile so it stays accurate, and flag it so the decision stays visible. The line that matters: you may move *within* a slot's chosen tool and minor; you may not change *which tool fills the slot*.
- **Stack fault.** The *tool* itself is the problem: two chosen tools are fundamentally incompatible, a package is broken or abandoned, a chosen tool can't actually do what the slot needs, or a `caveat` from the decide stage has come true. There is no nearest-patch escape; the choice has to change. This is the only case you stop on.

Tell them apart honestly, because the cost of confusing them runs both ways: papering over a real stack fault as if it were pin drift silently discards a decision the user made, and escalating mere pin drift as a stack fault stalls the user over something you should have just fixed. If a fix attempt for the same failure isn't converging after a couple of genuine tries (especially when the error is in the tool's own internals rather than your code, and no in-minor version helps), it's a stack fault, not drift; stop rather than thrashing.

## Step 5: When the stack must change

A stack fault is not yours to resolve alone. Stop, tell the user exactly what failed and why you believe it's the tool and not the example (the error, what you tried, why it points at the stack), and hand the decision back. Usually that means returning to `decide-stack` to re-pick that one slot with the new information; sometimes the user will know a config fix you don't. Get their input and resume once the stack is adjusted. The point of the whole pipeline is that the user owns the stack decisions, so surfacing a bad one is success, not failure.

## Step 6: Report

When every applicable gate is green, give a short summary: each tool and how the slice exercises it, the result of each gate (including which were skipped and why, e.g. no browser surface, no git remote), where the scaffold lives, and the obvious next step (run the dev server, the test suite, the build). Call out any **pin drift** you corrected (the original pin and what you bumped it to), which you've already written back to `.claude/stack-it/stack.yaml` so a bad lock doesn't survive into the real project. If anything still needs the user (accounts, secrets, a manual remote-CI push), say so plainly.

## Bundled resources

- `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py`: Validates the locked stack file before you build against it: checks that every entry has a `choice`, an exact `version`, and at least one `install` step, and that the file parses. Run it first with `--stage stack`. Run `python ${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --help` for usage.
