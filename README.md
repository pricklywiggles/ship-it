# ship-it

Ship your work end to end. A Claude Code plugin: a configurable orchestrator that drives a batch of issues (or your current local changes) through implement, review, comment cleanup, and PR, keeps living docs in sync, and cuts releases. The same steps are also standalone, individually callable skills, so you can run just the CI fix, just the review, or push the current diff through the flow without a tracker.

Adapt it to a project with `init`, which detects what it can (package manager, verify command, CI system, issue tracker, doc tools) and asks for the rest, producing a `ship-it.config`. Docs are kept current by pluggable jobs that run in parallel: built-ins for OpenSpec, graphify, and impeccable, plus jobs `init` can generate for any other doc you need to keep up to date.

## Status

Early scaffolding. First skill in place: `comment-cleanup`. The generalized engine (work-units, sources, stage skills, doc jobs, the ship-issues and cut-release orchestrators, and `init`) is being built out, extracted and generalized from a proven per-project implementation.

## Layout

- `.claude-plugin/` plugin and marketplace manifests
- `skills/` the individually callable skills (first: `comment-cleanup`)
