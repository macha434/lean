#!/usr/bin/env bash
# PreToolUse hook for Edit/Write. CLAUDE.md is loaded into every session's
# context, so a bloated one taxes every turn. Warns at 250 lines, blocks the
# write at 300 (PostToolUse can't block - exit code 2 is a no-op there - so
# this has to run before the write happens and predict the result).
#
# For Edit, the predicted size is current lines + (new_string lines -
# old_string lines). It's an estimate, not exact, but good enough to nudge.

set -u

allow() { exit 0; }

[ "${HAIKU_SHUNT_DISABLE:-0}" = "1" ] && allow

command -v jq >/dev/null 2>&1 || allow

input=$(cat 2>/dev/null) || allow
[ -n "$input" ] || allow

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -n "$agent_id" ] && allow

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$file_path" ] || allow
[ "$(basename -- "$file_path")" = "CLAUDE.md" ] || allow

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)

current_lines=0
[ -f "$file_path" ] && current_lines=$(wc -l <"$file_path" 2>/dev/null || echo 0)
current_lines=${current_lines//[!0-9]/}
[ -n "$current_lines" ] || current_lines=0

count_lines() { printf '%s' "$1" | grep -c '' 2>/dev/null || echo 0; }

case "$tool_name" in
  Write)
    content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
    [ -n "$content" ] || allow
    predicted=$(count_lines "$content")
    ;;
  Edit)
    old_str=$(printf '%s' "$input" | jq -r '.tool_input.old_string // empty' 2>/dev/null)
    new_str=$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
    old_lines=$(count_lines "$old_str")
    new_lines=$(count_lines "$new_str")
    predicted=$((current_lines + new_lines - old_lines))
    ;;
  *) allow ;;
esac

warn_lines=${HAIKU_SHUNT_CLAUDE_MD_WARN_LINES:-250}
block_lines=${HAIKU_SHUNT_CLAUDE_MD_BLOCK_LINES:-300}
case "$warn_lines" in '' | *[!0-9]*) warn_lines=250 ;; esac
case "$block_lines" in '' | *[!0-9]*) block_lines=300 ;; esac

if [ "$predicted" -ge "$block_lines" ]; then
  reason="haiku-shunt: this edit would take ${file_path} to about ${predicted} \
lines (block threshold ${block_lines}). CLAUDE.md loads into every turn's \
context, so size here is a recurring cost, not a one-time one.

Move the content this edit adds into a skill instead (skills load on demand, \
not every turn), or trim something else in CLAUDE.md to make room. Re-run the \
edit once the file is under the threshold.

To bypass once, set HAIKU_SHUNT_DISABLE=1 for this command."
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
fi

if [ "$predicted" -ge "$warn_lines" ]; then
  reason="haiku-shunt: ${file_path} is about to reach ${predicted} lines \
(warn threshold ${warn_lines}, block at ${block_lines}). Consider moving \
some of this into a skill before it hits the block threshold."
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
fi

allow
