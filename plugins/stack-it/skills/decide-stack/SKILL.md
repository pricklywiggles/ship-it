---
name: decide-stack
description: Use this skill to turn a list of project stack slots (decision categories like "web framework", "test framework", "database") into concrete, version-pinned, security-vetted tool choices. This is the decision stage that comes after identify-stack-slots and before install-stack. Trigger it whenever a user has a slots YAML and needs to pick the actual tools, or says "pick my stack", "choose tools for these slots", "research and recommend my dependencies", "what should I use for each part of my stack", or hands you a slots list to fill in. This skill collects hard preferences, researches options per open slot, gets the user's picks, verifies the latest official version and install steps for each, checks known vulnerabilities and recent-release supply-chain threats, and outputs an approved locked YAML. It does NOT install anything; installation is the separate install-stack skill.
---

# Decide Stack

Turn a list of stack **slots** (decision categories) into concrete, version-pinned, vetted tool choices, and emit an approved YAML that the `install-stack` skill consumes. This skill is read-only with respect to the user's system: it researches and converses, it does not install.

## Input

Expect a slots YAML, normally from the `identify-stack-slots` skill:

```yaml
project:
  description: ...
  type: ...
  platforms: [...]
slots:
  - slot: <category>
    required: <true|false>
    rationale: ...
    preference: <tool the user already wants, or null>
    source: ...
```

Look for the slots YAML at **`.claude/stack-it/slots.yaml`** (where `identify-stack-slots` writes it), or use a path the user gives. If none is present, ask for it or point the user to `identify-stack-slots` first. This skill fills slots; it doesn't discover them. Validate the input with `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --stage slots .claude/stack-it/slots.yaml` before proceeding so a malformed input fails fast.

## Step 1: Collect hard preferences up front

Before researching anything, ask the user whether they have hard preferences for any slots. People often arrive already set on a few tools and open on the rest, and asking first avoids researching slots that are already decided.

Merge these answers with any `preference` values already in the input YAML. A preference from either source means that slot is decided unless the user later changes their mind.

## Step 2: Resolve each open slot

Carry over every slot that already has a preference. Don't research alternatives for a decided slot unless the user asks.

For each slot with no preference, research options online and present a short list for the user to choose from. **These research tasks are independent across slots, so run them concurrently** rather than one slot at a time. Gather all the option research in parallel, then walk the user through the slots.

For each open slot:
1. Find the options that are most used, most trusted, and most modern. These are different axes, and a good shortlist usually spans them (a battle-tested default, a modern challenger).
2. Prefer authoritative signals: official ecosystem recommendations, real usage/download statistics, maintenance status, and security track record. Discount SEO listicles and unmaintained projects.
3. Present 2–4 options with a one- to two-line blurb each: what it is and its main tradeoff.
4. Let the user pick. Answer their questions. Present the landscape and let them choose; don't push your own favorite.

Record each decision.

## Step 3: Verify every chosen tool

Once every slot has a concrete choice, verify each one. **The three checks below are independent per tool, so verify all tools concurrently** instead of serially; this is the slowest part of the skill and parallelizing it matters.

For each chosen tool:

1. **Latest official version and install instructions.** Get these from the official source, the project's own repository, site, or registry page, never a third-party tutorial. Record the exact latest stable version and the official install command(s).
2. **Known issues and vulnerabilities.** Search for CVEs, security advisories, and significant open issues affecting the tool or the version. Check the official advisory channel where one exists (GitHub Security Advisories, the language's advisory database, etc.).
3. **Supply-chain threat check for fresh releases.** If the specific version you intend to install was *published within roughly the last two weeks*, do an additional search for recent package hijacking, malicious releases, compromised maintainer accounts, or registry-level attacks affecting this package or its package manager/registry. A freshly published version is the window in which supply-chain compromises surface, so a recent publish date is the trigger regardless of how old the project itself is. The classic pattern is a malicious version pushed from a compromised maintainer account that auto-installs on anyone using loose version ranges, often live for only hours before removal, so the freshly-published window is exactly when caution pays off. When a recent release is unvetted, the safe default is to recommend a slightly older, already-vetted stable version and pin it, or to apply a quarantine window so brand-new releases aren't installed until the community has had time to vet them (for npm, `npm config set min-release-age` delays installs of new versions; other ecosystems have equivalents). Record what you found and what you recommend in the slot's caveats.

   **Worked example.** Suppose a slot's chosen tool has latest stable `4.5.0`, published 3 days ago. Because that's inside the two-week window, you run the extra search. You find a security advisory reporting that a malicious `4.5.0` was briefly published from a hijacked maintainer account and later removed, with the clean prior release being `4.4.2`. The right move is to flag this prominently to the user, recommend pinning `4.4.2` (or waiting out a quarantine window before taking `4.5.x`), and record a caveat like: "4.5.0 published 3 days ago; advisory X reported a hijacked release in this window. Pinned 4.4.2 (last release before the incident) pending community vetting." If instead the search turns up nothing concerning, note that you checked and found no active threat, so the user knows the fresh version was vetted rather than skipped.

## Step 4: Present findings and confirm

Present the consolidated stack: each slot, its chosen tool, the version, and every caveat found. Call out all vulnerabilities, known issues, and supply-chain concerns explicitly. The whole point of the research is to surface these, so don't bury them.

Have a conversation to confirm or change choices in light of the findings. A serious caveat may send a slot back to Step 2 for a different pick. Loop until the user is satisfied.

## Step 5: Emit the locked YAML

Once approved, write the final YAML. **Order the `stack` list in the sequence the tools should be installed**, since install order matters: foundational tools (language/runtime, package manager) first, then things installed through them, then plugins/extensions that depend on a framework. The list order *is* the install order, so get it right here; the install stage trusts it.

Pin the exact versions that were researched and approved. The install instructions called for the latest stable, so these should be recent; pinning them keeps the install reproducible and matching what was vetted.

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
    caveats:
      - <vulnerability / known issue / supply-chain note>   # empty list if none
    notes: <anything the install stage needs to know, or null>
```

Save it to **`.claude/stack-it/stack.yaml`** in the project (creating `.claude/stack-it/` if needed — the pipeline's home for its generated files), then validate with `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --stage stack .claude/stack-it/stack.yaml` so a schema mistake is caught now, not in the install stage. This file is the handoff to `install-stack`, and the later stages read and update it in place, so it stays the single source of truth for the stack. If the user ever sends you back here to re-pick a slot (because `install-stack` or `scaffold-and-verify` hit a tool that can't work), edit this same file with the new choice rather than starting a fresh one.

## When to stop here

If the user only wants the decisions (to commit the YAML, share it, or install on a different machine), stop after Step 5 and hand them the file. The `install-stack` skill can run from it later.

## Bundled resources

- `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py` — Validates the slots input and the stack output against their expected schemas. Run it on input (`--stage slots`) and before handoff (`--stage stack`). It catches missing fields, wrong types, and (for the stack stage) missing versions or install steps. Run `python ${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --help` for usage.
