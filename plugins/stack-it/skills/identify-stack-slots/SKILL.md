---
name: identify-stack-slots
description: Use this skill at the very start of a brand new coding project of any kind (CLI, web app, API service, library, mobile app, desktop app, server, etc.) to figure out the categories of technology decisions the project's stack is composed of. Trigger this whenever a user is kicking off a new project and needs to plan their stack, asks "what do I need to decide" / "help me set up the stack" / "I'm starting a new X project", or whenever you're about to scaffold a project and haven't yet established which decision categories apply. This produces a YAML list of stack "slots" (categories like "web framework", "test framework", "database"), NOT concrete tool picks. The YAML output feeds a later stage that fills each slot.
---

# Identify Stack Slots

Help a user starting a brand new coding project identify the **stack slots** their project requires. A stack slot is a *category* of decision (e.g. "web framework", "test framework", "database"), not a concrete choice (e.g. "Next.js", "Jest", "Postgres"). The YAML output is consumed by a later stage that fills each slot, so do not recommend or select specific tools here.

## Objective

Through conversation, determine the minimal, complete set of slots this project's stack is composed of. The set depends entirely on what the project is, so understand the project, research how its class of application is built, and derive the slots from both.

## Process

Run discovery and research as interleaved passes, not separate phases. This matters because knowing the application class early lets you ask sharper questions and skip irrelevant ones.

1. **Identify the project type.** Ask what the user is building. Get just enough to determine project type and target platform(s).
2. **First research pass.** As soon as you know the application class, consult authoritative sources online for how it's built today. Let this shape your next questions. Knowing the application type reveals which ambiguities actually change the slot list.
3. **Ask sharper follow-ups.** Use what you learned to ask only slot-determining questions. Examples: Does it persist data? Does it expose an API or just consume one? UI, service, library, or CLI? Single platform or cross-platform? Browser, server, on-device, or mixed?
4. **Targeted research as needed.** When an answer opens a new concern (e.g. "yes it handles payments"), do a focused search on best practice for that concern before deciding whether it adds a slot.
5. **Stop** once the slot list is complete and grounded. Don't gather preferences about *which* tool fills a slot. That's the next stage's job.

Don't interrogate the user. When the answer is a matter of standard practice and not user preference, resolve it through research instead of asking.

## Researching best practices

Ground the slots in current best practice, not just your priors.

- Prioritize authoritative sources: official framework/language documentation, platform vendor guidance (e.g. OWASP, cloud provider well-architected docs), recognized standards bodies, and widely-cited engineering references. Discount random blogs, forum opinions, and SEO content.
- Search specifically for security, reliability, and operational concerns for this application type. These often reveal slots a naive list misses: auth, secrets management, input validation, logging/observability, error tracking, rate limiting, data backup, supply-chain/dependency scanning.
- Note where best practice implies a slot is *required* for this application type even if the user didn't mention it (e.g. a public web API needs an auth slot and an input-validation slot).
- Cite which source motivated any non-obvious slot in that slot's `source` field.
- Today's date matters. Prefer current guidance over stale advice, and don't assume your training-time picture of best practice is current.

## Rules

- Output categories, never products. "ORM", not "Prisma". "Bundler", not "Vite".
- Include a slot only if the project plausibly needs a decision there. Omit slots that don't apply (a Go CLI has no "web framework" slot).
- Distinguish required slots from optional ones the user may or may not want.
- Don't invent slots to seem thorough. A small script may need only "language" and "test framework".
- If the user already named a concrete tool, record the *slot* it implies and note their stated preference as metadata for the next stage. Don't let it stop you from finding other slots.
- Language/runtime is itself a slot unless the user has fixed it.

## Output format

When the project is understood and research is done, output a single YAML document with this exact shape:

```yaml
project:
  description: <one-line summary of what the user is building>
  type: <e.g. cli, web-app, api-service, library, mobile-app, desktop-app>
  platforms: [<target platforms>]
slots:
  - slot: <category name, e.g. "web framework">
    required: <true|false>
    rationale: <one line on why this project needs this decision>
    preference: <concrete tool the user already indicated, or null>
    source: <authority that motivated this slot, or null>
```

Rules for the YAML:
- `slot` is always a category, never a product.
- `preference` and `source` are `null` when not applicable.
- Order slots with required ones first, then optional.
- Emit only the YAML in the final output block, with no surrounding prose, so the next stage can parse it directly.

After writing the YAML, save it to **`.claude/stack-it/slots.yaml`** in the project, creating the `.claude/stack-it/` directory if it doesn't exist — that directory is the stack-it pipeline's home for the files it generates, and the later stages look there by default. Validate it with `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --stage slots .claude/stack-it/slots.yaml`. This catches structural mistakes (missing fields, wrong types, an empty slot list) here, at the source, instead of letting them surface one stage downstream in `decide-stack`. Note what the validator does *not* catch: it checks shape, not meaning, so it won't flag a `slot` value that's accidentally a product name ("Next.js") instead of a category ("web framework"). That distinction is the whole point of this skill, so it stays your responsibility, not the script's.

Then ask the user to confirm or correct the slot list before it passes to the next stage.

## Example

**Input:** "I'm building a public REST API in Go for a todo app."

After a first research pass on Go API best practices and a couple of follow-ups (persistence? auth? deployment target?), a correct output looks like:

```yaml
project:
  description: Public REST API for a todo app
  type: api-service
  platforms: [linux-server]
slots:
  - slot: language/runtime
    required: true
    rationale: Core implementation language is fixed by the user.
    preference: Go
    source: null
  - slot: HTTP router/framework
    required: true
    rationale: A REST API needs request routing and handler wiring.
    preference: null
    source: null
  - slot: database
    required: true
    rationale: Todo items must persist across requests.
    preference: null
    source: null
  - slot: authentication
    required: true
    rationale: A public API needs to authenticate callers to protect data.
    preference: null
    source: OWASP API Security Top 10
  - slot: input validation
    required: true
    rationale: Public endpoints must validate untrusted input.
    preference: null
    source: OWASP API Security Top 10
  - slot: test framework
    required: true
    rationale: API behavior needs automated verification.
    preference: null
    source: null
  - slot: logging/observability
    required: true
    rationale: A running service needs operational visibility.
    preference: null
    source: null
  - slot: rate limiting
    required: false
    rationale: Public APIs benefit from abuse protection but it may be deferred.
    preference: null
    source: OWASP API Security Top 10
  - slot: containerization
    required: false
    rationale: Common for deploying Go services but not mandatory.
    preference: null
    source: null
```

## Bundled resources

- `${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py` — Validates the slots YAML this skill produces against the schema `decide-stack` expects. Run it on your output before handoff with `--stage slots`. It verifies the structure (required fields, types, a non-empty slot list); it does not judge whether a `slot` is a proper category, which is yours to get right. Run `python ${CLAUDE_PLUGIN_ROOT}/scripts/validate_yaml.py --help` for usage.
