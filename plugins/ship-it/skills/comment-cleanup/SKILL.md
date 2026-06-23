---
name: comment-cleanup
description: >-
  Audit code comments against the user's strict "comments explain non-obvious
  why, never narrate what the code does" standard, and propose concrete fixes
  (keep / trim / delete, or clarify the code so the comment is unnecessary). Use
  this whenever the user asks to review, audit, clean up, sanity-check, or
  justify comments; whenever they ask "did I follow the comment rules / our
  comment guidelines"; right after writing or heavily editing code; and before
  committing or opening a PR. Also use it proactively when you have just
  generated more than a couple of comments. The caller may restrict the audit to
  a path, a function/symbol, a glob, "staged", "the branch diff", or "the PR";
  if no scope is given, audit only newly written or changed code, never the
  whole repo.
---

# Comment cleanup

This skill enforces one idea: **a comment must earn its place by explaining
something the code cannot say itself.** Comments are read far more often than
they are written, they are not type-checked, and they rot silently. A comment
that restates the code is worse than no comment: it is noise that a future
reader has to read, distrust, and re-verify against the code.

## The standard

Keep a comment **only** if it explains a non-obvious *why* that the code cannot
be made to express on its own. Legitimate categories:

- **Business / domain rule** that constrains the code but is not derivable from
  it ("archived rows are excluded here because the exporter counts them separately").
- **Edge case or workaround** ("WKWebView fires this twice on macOS; the second
  is ignored").
- **Historical / architectural decision** ("built in Rust instead of config
  because a runtime env var cannot drive a compile-time feature").
- **Cross-file or security intent** that isn't visible locally ("pairs with the
  Rust devtools(false) gate; this only removes the in-app entry point").
- **Performance rationale** for code that would otherwise look arbitrary
  ("hoisted out of the row so the memoized child stays stable").
- **A tried-and-rejected alternative**, so it isn't "fixed" back ("a red tint is
  invisible on this surface, so the signal is the text color").
- **Intentional surprising behavior**, e.g. a deliberately swallowed error
  ("already-pinned is the expected no-op").

Delete or rewrite everything else.

## The prime directives: be as brief as possible,never narrate the code

A comment that describes *what the next line(s) do* is never acceptable, and
this is not a judgment call to hand back to the user. If the code's purpose is
not clear without a narrating comment, **the code is the problem**, fix it:
rename a variable or function, extract a well-named helper, introduce an
intermediate named value, or simplify the control flow. Only if the logic is
genuinely irreducibly subtle does it get a comment, and then the comment
explains *why it must be this way*, not *what it does*.

Examples of narration to remove (and instead clarify the code):

- `// loop through the users` above a `for` loop.
- `// Admins skip the quota check; everyone else is limited` above the exact
  conditionals that compute that. The variable names should say it.
- `// rounded card with a subtle border and shadow` above a class
  string that literally contains `rounded-lg border shadow-sm`.
- A docstring that re-lists the parameters and their obvious meanings.

When you remove a narration comment, in the same change make the code
self-explanatory if it wasn't already, and say what you renamed/extracted.

## Also enforce

- **Brevity, applied per sentence.** A comment with a valid *why* is not
  automatically a KEEP. Every sentence in it must independently carry
  non-derivable information. After distilling the irreducible why, audit each
  remaining sentence; if it describes what the code does, restates a
  type/name, or narrates language/framework semantics, cut it. Common
  narration patterns that look like "context" but are visible from the body
  and must be removed:
  - "`beforeprint` fires while the page can still reflow, so flipping state
    here lets charts render at a fixed print width before the PDF is
    captured." (The event-listener call right below already shows this.)
  - "The effect re-runs and rebuilds the map cleanly once those conditions
    clear." (That is just how `useEffect` dependency arrays work.)
  - "`matchMedia('print')` is the fallback path for engines without the
    events." (Code shows the second listener; calling it "fallback" adds
    nothing.)
  - "Null until the GET returns or a print fetch populates it." (Restating
    a state variable's lifecycle visible from `setState` call sites.)

  Mandatory analysis: Is this comment as short as is possible, is there another way
  to restate it that is shorter and serves the same purpose. How many lines does this take?
  If a comment is 100% necessary, ask yourself how many lines is it and the more lines it has,
  the more scrutinous you should be to try restating it.

  Worked failure mode: a 5-line comment whose first sentence is the
  irreducible why and whose next three sentences narrate `beforeprint`,
  `matchMedia`, and React semantics is a **TRIM to one or two sentences**,
  not a KEEP. Default to TRIM for any multi-sentence comment until you have
  justified each sentence independently.

  Example trim: "`updates the title; the API rejects edits to locked items. A title
  change can surface anywhere, so clear all caches.`" → keep only the
  cache-invalidation rationale; the rest restates the function.
- **No commented-out code.** Delete it. Version control remembers.
- **No doc-header comments** on a symbol unless it is genuinely public API or
  feeds an auto-doc generator. Internal helpers do not get ceremonial headers.
- **Match the codebase.** If a file's idiom is terse, do not introduce verbose
  comments, and vice versa.
- **No em dashes** in any comment you write or rewrite (use a colon, semicolon,
  or two sentences). This is a hard user preference.
- Respect any project `CLAUDE.md` / `AGENTS.md` comment rules; this skill is the
  enforcement arm of those rules, not a competing standard.

## What is out of scope of the audit

Do not flag or rewrite:

- **Pre-existing comments that were only moved** by a refactor in the change
  under review. You are auditing comments *introduced or modified* in this work,
  not re-litigating untouched authorial decisions. Note them as "pre-existing,
  unchanged" and move on, unless the user explicitly asks for a whole-file pass.
- **Functional / directive comments** that the toolchain consumes:
  `biome-ignore`, `eslint-disable`, `ts-expect-error`, `@ts-ignore`,
  `prettier-ignore`, `noqa`, `nolint`, `# type:` pragmas, codegen markers,
  shebangs, license/copyright headers. These are not explanatory prose.
- Comments outside the resolved scope (see below).

## Resolving scope

The caller may pass a scope. Honor it literally:

- A **file path or glob** → audit comments in those files only.
- A **function / symbol / class name** → audit comments inside that symbol only.
- **"staged"** → `git diff --cached`.
- **"branch" / "branch diff" / "the PR"** → diff vs the base branch (below).
- A **commit range** → that range.

If **no scope is given**, default to *newly written or changed code only*, the
uncommitted working tree plus any commits on this branch that are not on the
main branch. Never audit the entire repository by default; that would drown the
signal and re-litigate code the user did not touch.

Determine the changed comment lines:

```bash
# main branch name (fallbacks if not "main")
base=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || echo main)
mergebase=$(git merge-base "origin/$base" HEAD 2>/dev/null || git merge-base "$base" HEAD)

# Added/modified lines in the default scope (working tree + branch commits):
git diff "$mergebase"...HEAD            # committed on this branch
git diff                                # unstaged
git diff --cached                       # staged
```

Look at added (`+`) lines that are comments, then open the surrounding code to
judge each one in context. Judging a comment requires reading the code it sits
on, not just the comment text.

## Workflow

1. **Resolve scope** (above) and collect every comment introduced or modified in
   that scope. Separate out the out-of-scope categories and list them once as
   skipped, with a one-line reason.
2. **For each in-scope comment, run two passes, not one.** Pass A: "Is there
   any non-obvious why in here at all?" If no → REMOVE. Pass B (the one I
   keep skipping): "For *each* sentence and clause, is it independently
   non-derivable from the code?" Any sentence that narrates implementation,
   restates types/names, or describes language/framework semantics gets cut,
   even if a sibling sentence in the same comment is a legitimate why.
   Default to TRIM for any multi-sentence comment; promote to KEEP only after
   justifying every sentence independently.
3. Assign a **verdict**:
   - **KEEP**: non-obvious why, *and every sentence in the comment earns its
     place independently*. Quote it, name the category.
   - **TRIM**: contains a real why alongside narration, restatement, or
     mechanism description. Give the exact shortened text. This is the
     expected verdict for most multi-sentence comments.
   - **REMOVE**: narration, duplication, obvious, commented-out code, or
     ceremonial header. If it was narration masking unclear code, also give the
     concrete code change (rename/extract) that makes the comment unnecessary.
4. **Apply** the TRIM/REMOVE edits (and any accompanying code-clarity change),
   unless the caller asked for analysis only. Do not ask the user to adjudicate
   narration; removing it is the rule, not a preference.
5. Re-run the project linter/formatter on touched files and report the result.

## Output format

Lead with a one-line tally, then a per-comment table, then the skipped list.
Keep it scannable. Use `path:line` references.

```
Audited 14 comments in <scope>. Verdict: 6 keep, 3 trim, 5 remove.

| Location | Comment (truncated) | Why we need it | Verdict |
|---|---|---|---|
| tree-view.tsx:148 | "Computed once here so the memoized child stays stable" | perf rationale, non-obvious | KEEP |
| api/items/route.ts:62 | "title edit. updateItem is the single permission authority" | 1st clause restates the handler | TRIM → "updateItem is the single permission authority." |
| tree-view.tsx:864 | "Guests get read-only; members can edit..." | narrates the conditionals below it | REMOVE (names already say it) |

Skipped (out of scope): 2 pre-existing comments moved by the refactor
(item-pin.ts:3, tree-view.tsx:861); 1 biome-ignore directive.
```

Finally provide a summary of the changes in this form: "comment % removed: X% (Y chars removed, down from Z)"

Then, if you applied edits, list the files changed and the lint result. If you
made code-clarity changes to retire a narration comment, state exactly what you
renamed or extracted so the diff is reviewable.

## Disposition, not diplomacy

The user does not want borderline narration calls deferred to them. If a comment
narrates the code, it goes, and the code is made clear enough to stand alone.
Reserve genuine questions for cases where the *why* itself is unknown to you
(e.g. a comment asserts a business rule you cannot verify), there, ask, because
inventing a rationale is worse than removing the comment.
