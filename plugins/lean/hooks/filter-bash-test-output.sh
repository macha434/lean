#!/usr/bin/env bash
# PreToolUse hook for Bash. Rewrites recognizable test-runner commands to pipe
# through grep for FAIL/ERROR, mirroring Anthropic's own example in
# docs/en/costs.md - keeps a 10,000-line test log out of the conversation.

set -u

allow() { exit 0; }

[ "${LEAN_DISABLE:-0}" = "1" ] && allow

command -v jq >/dev/null 2>&1 || allow

input=$(cat 2>/dev/null) || allow
[ -n "$input" ] || allow

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -n "$agent_id" ] && allow

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || allow

case "$cmd" in
  npm\ test*|npm\ run\ test*|pnpm\ test*|yarn\ test*|pytest*|go\ test*|jest*|vitest*|cargo\ test*|mvn*test*|gradle*test*|bundle\ exec\ rspec*|phpunit*) ;;
  *) allow ;;
esac

# Already piped through grep or redirected by the caller - don't filter twice.
case "$cmd" in
  *grep*|*'>'*) allow ;;
esac

max_lines=${LEAN_BASH_MAX_LINES:-100}
case "$max_lines" in
  '' | *[!0-9]*) max_lines=100 ;;
esac

# Run the original command inside a command substitution so its exit status
# can be captured before the output is filtered. A plain "cmd | grep | head"
# would report head's status (always 0), hiding failed runs from "&&" chains
# and from the tool's own exit-code display.
#   - FAIL/ERROR lines found       -> print them (with context)
#   - none, but exit status != 0   -> print the tail, so the failure is visible
#   - none and exit status 0       -> print a one-line "passed" note
# The last statement restores the original exit status.
filter_head='__lean_out=$({ '
# Single-quoted on purpose: everything here must reach the Bash tool verbatim.
# @MAX@ is the only placeholder; it is digits-only (validated above).
filter_tail='
} 2>&1); __lean_rc=$?
__lean_hit=$(printf "%s\n" "$__lean_out" | grep -A 5 -E "(FAIL|ERROR|error:)" | head -n @MAX@)
if [ -n "$__lean_hit" ]; then printf "%s\n" "$__lean_hit"
elif [ "$__lean_rc" -ne 0 ]; then echo "lean: exit $__lean_rc without FAIL/ERROR lines; last 20 lines:"; printf "%s\n" "$__lean_out" | tail -n 20
else echo "lean: exit 0, no FAIL/ERROR lines (output filtered)"; fi
(exit $__lean_rc)'
filter_tail=${filter_tail//@MAX@/$max_lines}
filtered_cmd="${filter_head}${cmd}${filter_tail}"

printf '%s' "$input" | jq --arg cmd "$filtered_cmd" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    updatedInput: (.tool_input + {command: $cmd})
  }
}'
