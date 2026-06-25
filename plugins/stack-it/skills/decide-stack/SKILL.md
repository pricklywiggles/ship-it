---
name: decide-stack
description: Use this skill to turn a list of project stack slots (decision categories like "web framework", "test framework", "database") into concrete, version-pinned, security-vetted tool choices. This is the decision stage that comes after identify-stack-slots and before install-stack. Trigger it whenever a user has a slots YAML and needs to pick the actual tools, or says "pick my stack", "choose tools for these slots", "research and recommend my dependencies", "what should I use for each part of my stack", or hands you a slots list to fill in. This skill collects hard preferences, researches each open slot's options and versions, gets the user's picks, then pulls the exact version-specific install steps from each chosen tool's official docs, checks known vulnerabilities and recent-release supply-chain threats, and outputs an approved locked YAML. It does NOT install anything; installation is the separate install-stack skill.
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

## How the research fans out, and on which model

This skill researches in **two fan-out passes** — Phase 1 before the user chooses (options, versions, risk), Phase 2 after (exact install steps for what they picked). Both run as concurrent subagents, and two rules apply to every research subagent you launch:

- **Use the bundled researcher, which is pinned to a cheaper model.** Delegate the fan-out to the plugin's **`stack-it:researcher`** subagent — one instance per slot in Phase 1, one per chosen tool in Phase 2. It ships with `model: sonnet` in its frontmatter, so the research runs on Sonnet (roughly 40% cheaper than an Opus-tier session model, and well-suited to retrieval and doc-reading) no matter what the session model is. This is the documented pattern for cost control — Claude Code's built-in Explore subagent pins a cheaper model the same way — and it's more reliable than asking the orchestrator to set a per-call model override.
- **Keep the judgment on yourself, the session model.** The `researcher` only gathers facts (its charter forbids it from picking winners); weighing the options, making the supply-chain risk call, and choosing the final pin are yours. Cheap model gathers; session model decides.

## Step 2: Phase 1 research — options, versions, and risk (so the user can choose)

Carry over every slot that already has a preference; don't research alternatives for a decided slot unless the user asks.

For each slot with no preference, fan out one `stack-it:researcher` per slot (concurrently, per the rules above) to bring back the landscape — **not** install steps yet, just what's needed to choose. For each slot, the subagent returns 2–4 viable options, and for each option:

1. Whether it's a most-used / most-trusted / most-modern candidate (different axes; a good shortlist spans them — a battle-tested default and a modern challenger).
2. The latest stable version, maintenance status, official/ecosystem recommendation, and a real usage signal (downloads, stars-with-activity). Prefer authoritative sources; discount SEO listicles and unmaintained projects.
3. Compatibility with the rest of the stack as it's being locked (framework major, runtime, the other chosen tools).
4. Known CVEs / security advisories, and — importantly — **the latest version's publish date**.

**Treat the supply-chain cooldown as a decision input, not an install-time surprise.** If a candidate's newest version was published inside the recent-release window (roughly the last two weeks), surface that *now* and lean toward recommending the nearest already-vetted stable release, so the user picks with the window in mind. Discovering this only at install time forces avoidable version drift later.

Then walk the user through the open slots: present the 2–4 options each with a one- to two-line blurb (what it is, its main tradeoff), answer questions, and let them pick. Present the landscape; don't push your favorite. Record each decision.

## Step 3: Phase 2 research — exact install and setup from official docs (for what they chose)

Once every slot has a concrete choice, fan out a **second** swarm — one `stack-it:researcher` per chosen tool, concurrently. This is the slowest part of the skill and parallelizing it matters. Each subagent has strong, specific instructions: fetch the **exact install, setup, and configuration steps for the exact chosen version** from that tool's **official documentation** (its own docs site, repository, or registry page), never from memory or a third-party tutorial. Setup procedures change between versions — a major release can rewrite the entire config story — so the steps must come from the docs *for the pinned version*, not from general knowledge.

Each Phase-2 subagent returns:

1. **The verbatim install command(s)** for that version, in the project's package manager.
2. **Any required config files or snippets** the docs specify for that version (a plugin registration, a config-file format, an init command, …).
3. **A supply-chain check at the exact version.** Confirm whether the version is inside the fresh-release window — *published within roughly the last two weeks* — and whether any advisory affects it. A freshly published version is the window in which supply-chain compromises surface (the classic pattern: a malicious version pushed from a hijacked maintainer account that auto-installs on loose version ranges, live for only hours before removal), so a recent publish date is the trigger regardless of how old the project is. When a recent release is unvetted, the safe default is to recommend a slightly older, already-vetted stable version and pin it, or to apply a quarantine window (for npm, `npm config set min-release-age` delays installs of new versions; other ecosystems have equivalents). Record findings in the slot's caveats.
4. **The source URL** — the official doc page the steps came from, so install-stack and the user can re-verify against it.

   **Worked example.** Suppose a chosen tool's latest stable is `4.5.0`, published 3 days ago. Because that's inside the window, the subagent runs the extra search and finds an advisory reporting a malicious `4.5.0` briefly published from a hijacked maintainer account and later removed, with the clean prior release being `4.4.2`. The right move is to flag this prominently, pin `4.4.2` (or wait out a quarantine window before `4.5.x`), and record a caveat like: "4.5.0 published 3 days ago; advisory X reported a hijacked release in this window. Pinned 4.4.2 (last release before the incident) pending community vetting." If the search turns up nothing, note that you checked and found no active threat, so the user knows the fresh version was vetted rather than skipped.

You — on the session model — synthesize these results into the locked YAML: the `install:` steps are the verbatim, version-specific commands the subagents fetched from the docs (not composed from memory), the caveats carry the supply-chain findings, and each entry's `notes` records the source doc URL.

## Step 4: Present findings and confirm

Present the consolidated stack: each slot, its chosen tool, the version, and every caveat found. Call out all vulnerabilities, known issues, and supply-chain concerns explicitly. The whole point of the research is to surface these, so don't bury them.

Have a conversation to confirm or change choices in light of the findings. A serious caveat may send a slot back to Phase 1 (Step 2) for a different pick — and a changed pick means re-running Phase 2 for that one tool. Loop until the user is satisfied.

## Step 5: Emit the locked YAML

Once approved, write the final YAML. **Order the `stack` list in the sequence the tools should be installed**, since install order matters: foundational tools (language/runtime, package manager) first, then things installed through them, then plugins/extensions that depend on a framework. The list order *is* the install order, so get it right here; the install stage trusts it.

Pin the exact versions that were researched and approved — the cooldown-aware choices from Phase 1, not blindly the newest release. The `install:` steps are the verbatim, version-specific commands Phase 2 fetched from each tool's official docs, and each entry's `notes` carries the source doc URL so install-stack and the user can re-verify. Pinning keeps the install reproducible and matching exactly what was vetted.

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
      - <verbatim command/step from the version's official docs (Phase 2)>
    caveats:
      - <vulnerability / known issue / supply-chain note>   # empty list if none
    notes: <anything the install stage needs to know; include the source doc URL for provenance, or null>
```

Save it to **`.claude/stack-it/stack.yaml`** in the project (creating `.claude/stack-it/` if needed — the pipeline's home for its generated files), then validate with `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --stage stack .claude/stack-it/stack.yaml` so a schema mistake is caught now, not in the install stage. This file is the handoff to `install-stack`, and the later stages read and update it in place, so it stays the single source of truth for the stack. If the user ever sends you back here to re-pick a slot (because `install-stack` or `scaffold-and-verify` hit a tool that can't work), edit this same file with the new choice rather than starting a fresh one.

## When to stop here

If the user only wants the decisions (to commit the YAML, share it, or install on a different machine), stop after Step 5 and hand them the file. The `install-stack` skill can run from it later.

## Bundled resources

- `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py` — Validates the slots input and the stack output against their expected schemas. Run it on input (`--stage slots`) and before handoff (`--stage stack`). It catches missing fields, wrong types, and (for the stack stage) missing versions or install steps. Run `python ${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --help` for usage.
