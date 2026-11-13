#!/usr/bin/env bash
# PreToolUse hook for PowerShell. Rewrites recognizable test-runner commands to
# pipe through Select-String for FAIL/ERROR - the PowerShell counterpart of
# filter-bash-test-output.sh. Keeps a 10,000-line test log out of the
# conversation.
#
# No "2>&1" is appended: in Windows PowerShell 5.1 it wraps every stderr line of
# a native command in an ErrorRecord and flips $? to false even on exit code 0.
#
# -CaseSensitive is required: Select-String ignores case by default, so a name
# like "test-fail.js" in npm's "> node test-fail.js" header would match "FAIL".
# grep in the Bash hook is case-sensitive, and this keeps the two aligned.

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

# Already filtered or redirected by the caller - don't filter twice.
# PowerShell is case-insensitive, so compare against a lowercased copy.
lower=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')
case "$lower" in
  *select-string*|*out-file*|*tee-object*|*'>'*) allow ;;
esac
# "sls" is the Select-String alias; match it only as a whole word.
printf '%s' "$lower" | grep -Eq '(^|[^[:alnum:]_-])sls([^[:alnum:]_-]|$)' && allow

max_lines=${LEAN_PS_MAX_LINES:-${LEAN_BASH_MAX_LINES:-100}}
case "$max_lines" in
  '' | *[!0-9]*) max_lines=100 ;;
esac

filtered_cmd="$cmd | Out-String -Stream | Select-String -Pattern 'FAIL|ERROR|error:' -CaseSensitive -Context 0,5 | Select-Object -First $max_lines"

printf '%s' "$input" | jq --arg cmd "$filtered_cmd" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    updatedInput: (.tool_input + {command: $cmd})
  }
}'
