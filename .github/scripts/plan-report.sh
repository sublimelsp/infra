#!/usr/bin/env bash
# Writes a Markdown report of a saved Terraform plan to stdout: the plan summary, a table of changed resources and
# a compact diff with only the changed lines.
#
# Usage: plan-report.sh <plan file> [max characters]
set -euo pipefail

plan=$1
max_chars=${2:-60000}

json=$(terraform show -json "$plan")
text=$(terraform show -no-color "$plan")

summary=$(grep -m1 -E '^(Plan:|No changes\.)' <<<"$text" || echo "No changes.")

rows=$(jq -r '
  .resource_changes[]
  | .change as $c
  | ($c.actions) as $a
  | (if $a == ["no-op"] then (if $c.importing then "import" else empty end)
     elif $a == ["create"] then "create"
     elif $a == ["delete"] then "**delete**"
     elif $a == ["update"] then "update"
     elif ($a | length) == 2 then "**replace**"
     else ($a | join(", ")) end) as $action
  | (if $a == ["update"] or ($a | length) == 2 then
       [($c.after // {} | keys[]) as $k
        | select($c.before[$k] != $c.after[$k] or ($c.after_unknown // {})[$k] == true)
        | "`\($k)`"] | join(", ")
     else "" end) as $attrs
  | "| `\(.address)` | \($action)\(if $c.importing and $action != "import" then " (import)" else "" end) | \($attrs) |"
' <<<"$json")

# Only the changed lines of the human-readable plan, with the change marker moved to the start of the line so that
# GitHub highlights it as a diff ("~" becomes "!").
diff=$(awk '/^Terraform will perform the following actions:/ { found = 1; next } found' <<<"$text" \
  | grep -E '^[[:space:]]*([-+~]|# )' \
  | grep -v -E '# \([0-9]+ unchanged .* hidden\)' \
  | sed -E 's/^([[:space:]]*)([-+~])/\2\1/; s/^~/!/' || true)

run_url=""
if [[ -n "${GITHUB_RUN_ID:-}" ]]; then
  run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

header="<!-- terraform-plan -->
### Terraform plan

**${summary}**
"

table=""
if [[ -n "$rows" ]]; then
  count=$(wc -l <<<"$rows" | tr -d ' ')
  open=""
  [[ $count -le 50 ]] && open=" open"
  table="
<details${open}><summary>Changed resources (${count})</summary>

| Resource | Action | Changed attributes |
| --- | --- | --- |
${rows}

</details>
"
fi

footer=""
[[ -n "$run_url" ]] && footer="
The full plan is in the [workflow run log](${run_url})."

# Keep the report within the size limit (65536 characters for PR comments) by truncating the diff.
budget=$((max_chars - ${#header} - ${#table} - ${#footer} - 200))
if [[ $budget -lt 0 ]]; then
  budget=0
fi
if [[ ${#diff} -gt $budget ]]; then
  diff="${diff:0:$budget}
... (truncated)"
fi

printf '%s' "$header$table"
if [[ -n "$diff" ]]; then
  # shellcheck disable=SC2016 # literal backticks
  printf '\n<details><summary>Diff</summary>\n\n```diff\n%s\n```\n\n</details>\n' "$diff"
fi
printf '%s\n' "$footer"
