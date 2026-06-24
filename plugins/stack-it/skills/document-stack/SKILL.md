---
name: document-stack
description: Use this skill to document a project's tech stack so both the agents working in the repo (in CLAUDE.md) and the humans reading it (in the README) know what it's built on and how to run it. It documents from the stack-it lockfile (`.claude/stack-it/stack.yaml`) when one exists, and otherwise infers the stack by analyzing the codebase. Use it proactively whenever someone wants their stack written down, even if they don't name the files — phrasings like "document my stack", "add a tech stack section to the readme", "write up what this project uses for Claude/agents", "put my dependencies in CLAUDE.md", "generate a tech-stack doc", "what's this project built with — document it", or running it as the final step after install-stack / scaffold-and-verify to capture the result. It writes an agent-facing stack summary (tools, pinned versions, how to build/test/lint/run, conventions, caveats) into CLAUDE.md and a human-facing Tech Stack + Getting Started into the README, both inside a refreshable managed block so re-running resyncs cleanly. It does NOT install, choose, research, or verify tools (those are install-stack, decide-stack, scaffold-and-verify), and it does not edit the stack YAML — here the YAML is read-only input. Not for writing general project prose, API docs, or code comments.
---

# Document Stack

Turn what a project is built on into documentation that serves its two readers: the **agents** that will work in the repo (via CLAUDE.md) and the **humans** who need to get it running (via the README). Document from the stack-it lockfile when the pipeline produced one; infer the stack from the codebase when it didn't. Either way, derive both documents from one resolved picture of the stack so they can't drift apart, and write them so a later run refreshes them cleanly.

## Step 1: Get the stack — lockfile first, else infer

**If `.claude/stack-it/stack.yaml` exists, that's the source of truth.** Validate it with `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --stage stack .claude/stack-it/stack.yaml`, then read the `project`, each slot's `choice`/`version`/`caveats`/`notes`, and the install order. It's already pinned and vetted, so trust it. A quick sanity glance at the codebase is still worth it — if the lockfile and the actual code obviously disagree (a tool the YAML lists is nowhere in the manifests, or vice versa), flag the discrepancy to the user rather than documenting a fiction. But don't re-derive what the lockfile already states.

**If there's no lockfile, the user skipped the pipeline and just wants their existing stack documented — so infer it from the codebase.** This is the harder path and the inference can be wrong, so gather evidence before concluding:

- **Manifests and lockfiles** are the spine: `package.json` + the lockfile, `pyproject.toml`/`requirements.txt` + `uv.lock`/`poetry.lock`, `go.mod`, `Cargo.toml`, `Gemfile.lock`, etc. Take exact versions from the lockfiles, not the loose ranges in the manifest.
- **Config files** reveal the tools and how they're wired: bundler/build config, test config, linter/formatter config, `tsconfig`, CSS framework config, container/CI files, ORM/migration config.
- **The code itself** confirms what's actually used (imports, framework entry points) versus merely installed.

From that evidence, name the stack the way the pipeline would: language/runtime, framework(s), key libraries, test/lint/build tooling, database/ORM, and anything else load-bearing — each with the version you found. **Present the inferred stack to the user and confirm it before writing**, calling out anything you're unsure about; inference is a best guess, and the user can correct a wrong call faster than they can un-publish a wrong doc.

## Step 2: Write for two audiences

Both documents describe the same stack, but their readers need different things. Write each for its reader rather than pasting one block into both.

**CLAUDE.md — agent-facing.** An agent reading this is about to make a change and needs to act correctly. Give it:
- Each tool and its **pinned version** and role (one line each).
- The exact commands to **build, test, lint/format, and run** the dev server or app — an agent shouldn't have to guess the test command.
- **Conventions** the tools imply that an agent would otherwise get wrong (e.g. "Tailwind v4 is wired via the Vite plugin, no `tailwind.config.js`"; "ESLint uses flat config").
- **Caveats** — carry over the lockfile's `caveats`, or note inferred gotchas (a known-incompatible pair, a pin that needs a specific peer version).

Keep it concise and factual; this is reference an agent consults, not prose it reads top to bottom.

**README — human-facing.** A person here wants to understand and run the project. Give them:
- A **Tech Stack** section: the major choices at a glance, each with a few words on what it's for.
- A **Getting Started** section: prerequisites (runtime version, package manager), install, run the dev server, run tests, build. Use the real commands for this stack.

If there's no README, create one with these sections.

## Step 3: Write into a refreshable managed block

`install-stack` and `scaffold-and-verify` update the lockfile, so this skill will be re-run after the stack changes; the documentation must update in place without clobbering anything a human wrote. Put the generated content between markers and replace only what's inside them:

```
<!-- stack-it:stack start -->
> Generated by stack-it's document-stack. Edits inside this block are overwritten on the next run.

...generated stack documentation...
<!-- stack-it:stack end -->
```

On each run: if the markers already exist in the file, replace only the content between them; if they don't, insert the block in a sensible place (in CLAUDE.md, under a top-level stack/architecture heading; in the README, after the title and intro, before deeper sections). Everything outside the markers — the rest of CLAUDE.md, the rest of the README — stays exactly as the user left it. This is what makes re-running safe and keeps the docs in sync with the lockfile.

## Step 4: Report

Tell the user what you did: which source you used (lockfile or inferred-from-code, and if inferred, that they confirmed it), which files you wrote or created, and any discrepancy or caveat you surfaced. If you inferred the stack, remind them the result is only as accurate as the codebase signals and they should correct anything you got wrong.

## Boundaries

This skill documents; it does not install, choose, research, or verify tools — those are `install-stack`, `decide-stack`, and `scaffold-and-verify`. It treats the stack YAML as read-only input and never edits it (keeping the lockfile current is the install/verify stages' job). And it documents the *stack*, not the whole project: it doesn't write general prose, API references, or code comments.

## Bundled resources

- `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py` — Validate the lockfile before trusting it, with `--stage stack`. Run `python ${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --help` for usage.
