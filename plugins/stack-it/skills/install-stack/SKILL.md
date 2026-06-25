---
name: install-stack
description: Use this skill to install and scaffold a project from an approved, version-pinned stack YAML (the output of the decide-stack skill). Trigger it whenever a user has a locked stack file and wants the project actually set up, or says "install my stack", "set up the project from this YAML", "scaffold the project", "run the installs", or hands you a stack file with concrete tools, versions, and install steps. This skill runs real commands on the user's machine: it goes through the stack in install order, runs each tool's official install steps at the pinned version, handles interactive prompts, verifies each step, and continues until the project is fully set up. It does NOT choose tools or research them; that is the separate decide-stack skill.
---

# Install Stack

Install and scaffold a project from an approved, version-pinned stack YAML produced by the `decide-stack` skill. This skill runs real commands that modify the user's machine, so it proceeds deliberately and keeps the user informed.

## Input

Expect the locked stack YAML from `decide-stack`, by default at **`.claude/stack-it/stack.yaml`** (or a path the user gives):

```yaml
project:
  description: ...
  type: ...
  platforms: [...]
stack:
  - slot: <category>
    choice: <chosen tool>
    version: <exact pinned version>
    install:
      - <official install command or step>
    caveats: [...]
    notes: <or null>
```

The `stack` list order is the install order; trust it. If no stack YAML is present at `.claude/stack-it/stack.yaml` (and the user gives no other path), ask for it or point the user to `decide-stack` first. This skill installs; it doesn't choose or research tools.

Before doing anything, validate the file with `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --stage stack .claude/stack-it/stack.yaml`. A malformed or unversioned stack file should fail here, before any command runs. Surface any `caveats` from the file to the user up front so they go in aware of known issues, even though those were already discussed in the decide stage.

## Execution rules

Go through the `stack` list in order and run each entry's `install` steps. Because the list is dependency-ordered, **installs are generally sequential and must not be parallelized** (a plugin can't install before its framework). Where two adjacent entries are genuinely independent (no shared dependency, no ordering relationship), they may run concurrently, but only when you're confident the order doesn't matter; when in doubt, stay sequential.

For each step:

- **Show before running.** Show the user the exact command before running anything that changes the system. Routine, expected installs can run as you go with a report of what you did; anything destructive, irreversible, or surprising needs confirmation first.
- **Install the pinned version.** Use the exact `version` from the YAML, not "latest", so the result matches what was vetted in the decide stage.
- **Handle interactive prompts as they come.** Installers and scaffolding tools often ask questions (project name, options, feature toggles). Answer from the project context and the YAML where the answer is clear; ask the user when it's a real preference you can't infer.
- **Verify each step before moving on.** After each install, do a quick success check (version prints, command resolves, expected files exist). If a step fails, stop and resolve it with the user before continuing; don't plow ahead on a broken foundation.
- **Respect the boundary.** Don't enter credentials, create accounts, log in, or modify access controls on the user's behalf. If a step needs a secret, an account, or a sign-in, hand that step to the user with clear instructions and continue once they confirm it's done.
- **Keep the lockfile current.** When what actually gets installed diverges from the file (you had to take the nearest available patch of a pinned version, an `install` step needed adjusting to work, or a `caveat` turned out resolved or newly relevant), update `.claude/stack-it/stack.yaml` in place so it stays an accurate record of the installed stack for `scaffold-and-verify` and the user. This is for staying faithful to reality *within* each slot's chosen tool. It is **not** license to change *which tool* fills a slot: if a chosen tool can't be installed at all, stop and send the user back to `decide-stack` rather than silently substituting another.

## Finishing

Continue until the project is fully set up. Then give a short summary: the tools and versions installed, anything the user still needs to do manually (accounts, secrets, env files), and the obvious next step (how to run the dev server, the test suite, or the build).

## Bundled resources

- `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py`: Validates the locked stack file before installation: checks that every entry has a `choice`, an exact `version`, and at least one `install` step, and that the file parses. Run `python ${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --help` for usage. Always run this first; it's cheap insurance against a malformed handoff.
