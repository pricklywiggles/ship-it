# ship-it config schema, encoded as jq checks. Emits {errors:[...], warnings:[...]}.
# Errors are schema violations (the engine reads these exact shapes); warnings are
# advisories. Run via scripts/validate-config.sh. Dependency-free (jq only).
#
# This file is the schema of record. When the config shape changes, update it here.

def allowed($keys; $label):
  if type == "object"
  then (keys_unsorted - $keys | map("\($label): unexpected key '\(.)'"))
  else [] end;

{
  errors: ([

    allowed(["repo","source","houseRules","safety","verify","worktree","concurrency","review","ci","docs","prTemplate","planning"]; "(top level)"),

    (if (.repo|type) == "object" then (.repo | allowed(["mainBranch","mergeStrategy","slug"]; "repo")) else [] end),
    (.repo.mergeStrategy as $ms | if ($ms != null) and ((["squash","merge","rebase"] | index($ms)) == null)
       then ["repo.mergeStrategy must be one of squash|merge|rebase (got '\($ms)')"] else [] end),

    (if (.source|type) != "object" then ["source must be an object"] else (.source | allowed(["default","tracker"]; "source")) end),
    (if (.source|type) == "object" then
       (if .source.tracker == null then ["source.tracker is required (an object with a 'type' field)"]
        elif (.source.tracker|type) != "object" then ["source.tracker must be an OBJECT like {\"type\":\"linear\", ...}, got a \(.source.tracker|type). Tracker fields (project, team, idPrefix) go inside source.tracker, not in a sibling key."]
        elif .source.tracker.type == null then ["source.tracker.type is required (github-issues | linear | <custom resolver>)"]
        else [] end)
     else [] end),

    (if .verify == null then ["verify is required (an array of command strings run in the worktree)"]
     elif (.verify|type) != "array" then ["verify must be an ARRAY of command strings, got a \(.verify|type). Do not wrap it in {commands:[...]}."]
     else [] end),

    (if (.worktree|type) == "object" then (.worktree | allowed(["enabled","root","prepare","qaNotes"]; "worktree")) else [] end),
    (if (.worktree.enabled == true) and (.worktree.prepare == null) then ["worktree.prepare is required when worktree.enabled is true"] else [] end),

    (if .review.reviewers == null then []
     elif (.review.reviewers|type) != "array" then ["review.reviewers must be an array"]
     else [ .review.reviewers | to_entries[] | .key as $i | .value as $r |
              (if $r.ref == null then "review.reviewers[\($i)] is missing 'ref' (the invocation name, e.g. pr-review-toolkit:code-reviewer or vercel-react-best-practices)" else empty end),
              (if $r.kind == null then "review.reviewers[\($i)] is missing 'kind' (agent|skill|command)"
               elif (["agent","skill","command"] | index($r.kind)) == null then "review.reviewers[\($i)].kind must be agent|skill|command (got '\($r.kind)')"
               else empty end) ]
     end),

    (if .docs.jobs == null then []
     elif (.docs.jobs|type) != "array" then ["docs.jobs must be an array"]
     else [ .docs.jobs | to_entries[] | .key as $i | .value as $j |
              (if $j.name == null then "docs.jobs[\($i)] is missing 'name'" else empty end),
              (if $j.mechanic == null then "docs.jobs[\($i)] is missing 'mechanic'"
               elif (["regenerate","author-reconcile","curate-serial"] | index($j.mechanic)) == null then "docs.jobs[\($i)].mechanic must be regenerate|author-reconcile|curate-serial (got '\($j.mechanic)')"
               else empty end),
              (if $j.ref == null then "docs.jobs[\($i)] (\($j.name // "?")) is missing 'ref' (the command or skill that runs it, e.g. 'graphify update .' or 'impeccable')" else empty end),
              (if ($j.mechanic != "regenerate") and ($j.appliesWhen == null) then "docs.jobs[\($i)] (\($j.name // "?")) is missing 'appliesWhen' (the docNeed classification that triggers it, e.g. 'design')" else empty end) ]
     end),

    (if (.prTemplate|type) == "object" then
       (.prTemplate | allowed(["sections","verification"]; "prTemplate"))
       + (if .prTemplate.verification == null then ["prTemplate.verification is required (the rule for the Verification section)"] else [] end)
     else [] end),

    (if (.planning|type) == "object" then (.planning | allowed(["enabled","postBack","depth"]; "planning")) else [] end),
    (.planning.depth as $d | if ($d != null) and ((["adaptive","light","full"] | index($d)) == null)
       then ["planning.depth must be one of adaptive|light|full (got '\($d)')"] else [] end),
    (if (.planning.enabled != null) and ((.planning.enabled|type) != "boolean") then ["planning.enabled must be a boolean"] else [] end),
    (if (.planning.postBack != null) and ((.planning.postBack|type) != "boolean") then ["planning.postBack must be a boolean"] else [] end)

  ] | flatten),

  warnings: ([

    (if (.safety == null) or (((.safety|type) == "array") and ((.safety|length) == 0))
       then ["safety is empty; most projects want at least a verification/scope rail"] else [] end),

    (if ((.verify|type) == "array") and (.worktree.enabled == true) then
       [ .verify[] | select(type == "string") | select(test("^(pnpm|yarn|npm run|bun run) "))
         | "verify command '\(.)' uses a package-manager run-script; in a worktree prefer the direct binary (e.g. node_modules/.bin/...), run-scripts can misbehave there" ]
     else [] end)

  ] | flatten)
}
