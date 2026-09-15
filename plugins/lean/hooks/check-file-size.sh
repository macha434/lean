#!/usr/bin/env bash
# PreToolUse hook for Read. Fails open on every path except a large whole-file
# read from the main conversation - see README.md for why.

set -u

allow() { exit 0; }

[ "${LEAN_DISABLE:-0}" = "1" ] && allow

command -v jq >/dev/null 2>&1 || allow

input=$(cat 2>/dev/null) || allow
[ -n "$input" ] || allow

# agent_id is present only when the hook fires inside a subagent. The whole
# point of this plugin is that the delegate reads the file, so never block it.
agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -n "$agent_id" ] && allow

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$file_path" ] || allow
[ -f "$file_path" ] || allow
[ -r "$file_path" ] || allow

# A bounded read is already the behaviour we want to encourage.
offset=$(printf '%s' "$input" | jq -r '.tool_input.offset // empty' 2>/dev/null)
limit=$(printf '%s' "$input" | jq -r '.tool_input.limit // empty' 2>/dev/null)
[ -n "$offset" ] && allow
[ -n "$limit" ] && allow

# Line counts are meaningless for images, PDFs and other binaries, and Read
# handles those natively.
grep -qI . "$file_path" 2>/dev/null || allow

min_lines=${LEAN_MIN_LINES:-350}
case "$min_lines" in
  '' | *[!0-9]*) min_lines=350 ;;
esac

lines=$(wc -l <"$file_path" 2>/dev/null) || allow
lines=${lines//[!0-9]/}
[ -n "$lines" ] || allow
[ "$lines" -ge "$min_lines" ] || allow

reason="lean: ${file_path} is ${lines} lines (threshold ${min_lines}). \
Reading it in full would load all of it into this conversation's context.

Delegate it instead: call the Task/Agent tool with subagent_type \"bulk-reader\" \
and a prompt that states the absolute path and the specific question you need \
answered. It reads the file in its own disposable context on a cheaper model and \
returns only the extract.

If you need the raw text here, re-issue Read with offset/limit for a bounded \
range - ranged reads are never blocked."

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
