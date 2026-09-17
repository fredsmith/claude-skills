#!/usr/bin/env bash
set -uo pipefail

root=${AGENT_STATUS_ROOT:-}
root=${root%/}
label=${AGENT_STATUS_ROOT_LABEL:-(root)}
log_lines=${AGENT_STATUS_LOG_LINES:-20}
show_done=${AGENT_STATUS_SHOW_DONE:-1}
self=${CLAUDE_JOB_DIR:-}
self=${self##*/}

json=$(claude agents --json --all 2>/dev/null) || {
  echo "Could not reach the background service. Try: claude daemon status" >&2
  exit 1
}

fmt='
  def shorten:
    . as $p
    | if ($root != "") and ($p == $root) then $label
      elif ($root != "") and ($p | startswith($root + "/")) then ($p[($root|length)+1:])
      elif ($p == $home) then "~"
      elif ($p | startswith($home + "/")) then "~/" + ($p[($home|length)+1:])
      else $p end;
  def pad($n): (. + (" " * $n))[0:$n];
  [ .[] | select(.state as $s | $states | index($s)) ]
  | sort_by(.startedAt) | reverse
  | .[]
  | "  " + ((.id // "-") | pad(9))
        + ((.name // "(unnamed)")
            + (if (.id // "") == $self and $self != "" then " (this session)" else "" end)
            | pad(40))
        + ((.waitingFor // "") | pad(14))
        + ((if .status then "live" else "cold" end) | pad(6))
        + ((.cwd // "-") | shorten)
'

render() {
  local heading=$1 states=$2 rows
  rows=$(jq -r --argjson states "$states" --arg self "$self" \
    --arg root "$root" --arg label "$label" --arg home "$HOME" "$fmt" <<<"$json")
  [[ -z $rows ]] && return 0
  printf '\n%s\n%s\n' "$heading" "$rows"
}

count() { jq --arg s "$1" '[.[]|select(.state==$s)]|length' <<<"$json"; }

printf '%s agents — %s needs input, %s working, %s failed\n' \
  "$(jq 'length' <<<"$json")" "$(count blocked)" "$(count working)" "$(count failed)"

render "NEEDS INPUT" '["blocked"]'
render "WORKING"     '["working"]'
render "FAILED"      '["failed"]'
render "STOPPED"     '["stopped"]'
[[ $show_done == 1 ]] && render "DONE" '["done","completed"]'

for id in $(jq -r '.[] | select(.state=="blocked" or .state=="failed") | .id' <<<"$json"); do
  printf '\n--- %s: last %s lines ---\n' "$id" "$log_lines"
  claude logs "$id" 2>/dev/null | tail -"$log_lines" || echo "(no logs available)"
done
