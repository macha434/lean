#!/usr/bin/env bash
# PreToolUse hook for Bash. Rewrites recognizable test-runner commands to pipe
# through grep for FAIL/ERROR, mirroring Anthropic's own example in
# docs/en/costs.md - keeps a 10,000-line test log out of the conversation.

set -u

allow() { exit 0; }

[ "${HAIKU_SHUNT_DISABLE:-0}" = "1" ] && allow

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

max_lines=${HAIKU_SHUNT_BASH_MAX_LINES:-100}
case "$max_lines" in
  '' | *[!0-9]*) max_lines=100 ;;
esac

filtered_cmd="$cmd 2>&1 | grep -A 5 -E '(FAIL|ERROR|error:)' | head -n $max_lines"

printf '%s' "$input" | jq --arg cmd "$filtered_cmd" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    updatedInput: (.tool_input + {command: $cmd})
  }
}'
