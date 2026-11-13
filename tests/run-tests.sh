#!/usr/bin/env bash
# Exercises every PreToolUse hook against the cases that matter: the ones
# each must block or rewrite, and the many it must leave alone.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)/plugins/lean/hooks"
HOOK="$ROOT/check-file-size.sh"
BASH_HOOK="$ROOT/filter-bash-test-output.sh"
PS_HOOK="$ROOT/filter-powershell-test-output.sh"
CLAUDE_MD_HOOK="$ROOT/check-claude-md-length.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

seq 1 500 >"$TMP/big.txt"
seq 1 10 >"$TMP/small.txt"
printf 'binary\0content\0here' >"$TMP/blob.bin"

pass=0
fail=0

# check <hook> <name> <expected: allow|deny> <stdin json> [env assignments...]
check() {
  local hook=$1 name=$2 expected=$3 payload=$4
  shift 4
  local out
  out=$(printf '%s' "$payload" | env "$@" "$hook" 2>/dev/null)
  local got="allow"
  case "$out" in
    *'"permissionDecision"'*'"deny"'*) got="deny" ;;
  esac
  if [ "$got" = "$expected" ]; then
    pass=$((pass + 1))
    printf 'ok   %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL %s (expected %s, got %s)\n' "$name" "$expected" "$got"
  fi
}

# check_contains <hook> <name> <expected substring, or EMPTY> <stdin json> [env assignments...]
check_contains() {
  local hook=$1 name=$2 expected=$3 payload=$4
  shift 4
  local out
  out=$(printf '%s' "$payload" | env "$@" "$hook" 2>/dev/null)
  local ok=0
  if [ "$expected" = "EMPTY" ]; then
    [ -z "$out" ] && ok=1
  else
    case "$out" in *"$expected"*) ok=1 ;; esac
  fi
  if [ "$ok" = "1" ]; then
    pass=$((pass + 1))
    printf 'ok   %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL %s (expected to contain %s, got: %s)\n' "$name" "$expected" "$out"
  fi
}

### check-file-size.sh ###

check "$HOOK" "large file from main session is blocked" deny \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\"}}" \
  IGNORE=1

check "$HOOK" "large file inside a subagent is allowed" allow \
  "{\"tool_name\":\"Read\",\"agent_id\":\"a1\",\"agent_type\":\"bulk-reader\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\"}}" \
  IGNORE=1

check "$HOOK" "small file is allowed" allow \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/small.txt\"}}" \
  IGNORE=1

check "$HOOK" "ranged read is allowed" allow \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\",\"limit\":50}}" \
  IGNORE=1

check "$HOOK" "offset read is allowed" allow \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\",\"offset\":100}}" \
  IGNORE=1

check "$HOOK" "binary file is allowed" allow \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/blob.bin\"}}" \
  IGNORE=1

check "$HOOK" "missing file is allowed" allow \
  '{"tool_name":"Read","tool_input":{"file_path":"/nonexistent/nope.txt"}}' \
  IGNORE=1

check "$HOOK" "malformed input is allowed" allow \
  'not json at all' \
  IGNORE=1

check "$HOOK" "empty input is allowed" allow \
  '' \
  IGNORE=1

check "$HOOK" "raised threshold allows the same file" allow \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\"}}" \
  LEAN_MIN_LINES=1000

check "$HOOK" "lowered threshold blocks a small file" deny \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/small.txt\"}}" \
  LEAN_MIN_LINES=5

check "$HOOK" "non-numeric threshold falls back to the default" deny \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\"}}" \
  LEAN_MIN_LINES=abc

check "$HOOK" "disable flag allows everything" allow \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\"}}" \
  LEAN_DISABLE=1

### filter-bash-test-output.sh ###

check_contains "$BASH_HOOK" "npm test is rewritten to filter failures" "grep -A 5" \
  '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' \
  IGNORE=1

check_contains "$BASH_HOOK" "pytest is rewritten to filter failures" "grep -A 5" \
  '{"tool_name":"Bash","tool_input":{"command":"pytest"}}' \
  IGNORE=1

check_contains "$BASH_HOOK" "non-test command passes through unmodified" EMPTY \
  '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  IGNORE=1

check_contains "$BASH_HOOK" "command already piped through grep is left alone" EMPTY \
  '{"tool_name":"Bash","tool_input":{"command":"pytest | grep FAIL"}}' \
  IGNORE=1

check_contains "$BASH_HOOK" "command already redirected to a file is left alone" EMPTY \
  '{"tool_name":"Bash","tool_input":{"command":"npm test > out.log"}}' \
  IGNORE=1

check_contains "$BASH_HOOK" "bash command from a subagent is left alone" EMPTY \
  '{"agent_id":"a1","tool_name":"Bash","tool_input":{"command":"npm test"}}' \
  IGNORE=1

check_contains "$BASH_HOOK" "disable flag leaves a test command unmodified" EMPTY \
  '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' \
  LEAN_DISABLE=1

### filter-powershell-test-output.sh ###

check_contains "$PS_HOOK" "npm test is rewritten to filter failures" "Select-String -Pattern 'FAIL|ERROR|error:' -CaseSensitive -Context 0,5" \
  '{"tool_name":"PowerShell","tool_input":{"command":"npm test"}}' \
  IGNORE=1

check_contains "$PS_HOOK" "rewritten command keeps the original command first" '"command": "npm test 2>&1 | Out-String -Stream' \
  '{"tool_name":"PowerShell","tool_input":{"command":"npm test"}}' \
  IGNORE=1

check_contains "$PS_HOOK" "rewrite merges stderr into the pipeline" "npm test 2>&1 | Out-String -Stream | Select-String" \
  '{"tool_name":"PowerShell","tool_input":{"command":"npm test"}}' \
  IGNORE=1

check_contains "$PS_HOOK" "pytest is rewritten to filter failures" "Select-Object -First 100" \
  '{"tool_name":"PowerShell","tool_input":{"command":"pytest"}}' \
  IGNORE=1

check_contains "$PS_HOOK" "non-test command passes through unmodified" EMPTY \
  '{"tool_name":"PowerShell","tool_input":{"command":"Get-ChildItem"}}' \
  IGNORE=1

check_contains "$PS_HOOK" "command already using Select-String is left alone" EMPTY \
  '{"tool_name":"PowerShell","tool_input":{"command":"pytest | Select-String FAIL"}}' \
  IGNORE=1

check_contains "$PS_HOOK" "Select-String match is case-insensitive" EMPTY \
  '{"tool_name":"PowerShell","tool_input":{"command":"pytest | select-string FAIL"}}' \
  IGNORE=1

check_contains "$PS_HOOK" "command already using the sls alias is left alone" EMPTY \
  '{"tool_name":"PowerShell","tool_input":{"command":"pytest | sls FAIL"}}' \
  IGNORE=1

check_contains "$PS_HOOK" "sls inside another word does not count as a filter" "Select-String -Pattern" \
  '{"tool_name":"PowerShell","tool_input":{"command":"pytest tests/test_hassls.py"}}' \
  IGNORE=1

check_contains "$PS_HOOK" "command already redirected to a file is left alone" EMPTY \
  '{"tool_name":"PowerShell","tool_input":{"command":"npm test > out.log"}}' \
  IGNORE=1

check_contains "$PS_HOOK" "command already using Out-File is left alone" EMPTY \
  '{"tool_name":"PowerShell","tool_input":{"command":"npm test | Out-File out.log"}}' \
  IGNORE=1

check_contains "$PS_HOOK" "command already using Tee-Object is left alone" EMPTY \
  '{"tool_name":"PowerShell","tool_input":{"command":"npm test | Tee-Object -FilePath out.log"}}' \
  IGNORE=1

check_contains "$PS_HOOK" "powershell command from a subagent is left alone" EMPTY \
  '{"agent_id":"a1","tool_name":"PowerShell","tool_input":{"command":"npm test"}}' \
  IGNORE=1

check_contains "$PS_HOOK" "disable flag leaves a test command unmodified" EMPTY \
  '{"tool_name":"PowerShell","tool_input":{"command":"npm test"}}' \
  LEAN_DISABLE=1

check_contains "$PS_HOOK" "LEAN_PS_MAX_LINES overrides the line cap" "Select-Object -First 7" \
  '{"tool_name":"PowerShell","tool_input":{"command":"npm test"}}' \
  LEAN_PS_MAX_LINES=7

check_contains "$PS_HOOK" "LEAN_BASH_MAX_LINES is the fallback line cap" "Select-Object -First 9" \
  '{"tool_name":"PowerShell","tool_input":{"command":"npm test"}}' \
  LEAN_BASH_MAX_LINES=9

check_contains "$PS_HOOK" "non-numeric line cap falls back to the default" "Select-Object -First 100" \
  '{"tool_name":"PowerShell","tool_input":{"command":"npm test"}}' \
  LEAN_PS_MAX_LINES=abc

check_contains "$PS_HOOK" "malformed input is left alone" EMPTY \
  'not json at all' \
  IGNORE=1

check_contains "$PS_HOOK" "empty input is left alone" EMPTY \
  '' \
  IGNORE=1

### check-claude-md-length.sh ###

seq 1 50 >"$TMP/claude_small.txt"
seq 1 260 >"$TMP/claude_warn.txt"
seq 1 350 >"$TMP/claude_block.txt"

check "$CLAUDE_MD_HOOK" "small CLAUDE.md write is allowed" allow \
  "$(jq -n --arg fp "$TMP/w1/CLAUDE.md" --rawfile content "$TMP/claude_small.txt" \
    '{tool_name:"Write",tool_input:{file_path:$fp,content:$content}}')" \
  IGNORE=1

check "$CLAUDE_MD_HOOK" "260-line CLAUDE.md write warns but is allowed" allow \
  "$(jq -n --arg fp "$TMP/w2/CLAUDE.md" --rawfile content "$TMP/claude_warn.txt" \
    '{tool_name:"Write",tool_input:{file_path:$fp,content:$content}}')" \
  IGNORE=1

check_contains "$CLAUDE_MD_HOOK" "warn case names the warn threshold" "warn threshold" \
  "$(jq -n --arg fp "$TMP/w2b/CLAUDE.md" --rawfile content "$TMP/claude_warn.txt" \
    '{tool_name:"Write",tool_input:{file_path:$fp,content:$content}}')" \
  IGNORE=1

check "$CLAUDE_MD_HOOK" "350-line CLAUDE.md write is blocked" deny \
  "$(jq -n --arg fp "$TMP/w3/CLAUDE.md" --rawfile content "$TMP/claude_block.txt" \
    '{tool_name:"Write",tool_input:{file_path:$fp,content:$content}}')" \
  IGNORE=1

check "$CLAUDE_MD_HOOK" "non-CLAUDE.md file is allowed regardless of size" allow \
  "$(jq -n --arg fp "$TMP/w4/README.md" --rawfile content "$TMP/claude_block.txt" \
    '{tool_name:"Write",tool_input:{file_path:$fp,content:$content}}')" \
  IGNORE=1

check "$CLAUDE_MD_HOOK" "subagent edits to CLAUDE.md are allowed" allow \
  "$(jq -n --arg fp "$TMP/w5/CLAUDE.md" --rawfile content "$TMP/claude_block.txt" \
    '{agent_id:"a1",tool_name:"Write",tool_input:{file_path:$fp,content:$content}}')" \
  IGNORE=1

check "$CLAUDE_MD_HOOK" "disable flag allows an over-threshold write" allow \
  "$(jq -n --arg fp "$TMP/w6/CLAUDE.md" --rawfile content "$TMP/claude_block.txt" \
    '{tool_name:"Write",tool_input:{file_path:$fp,content:$content}}')" \
  LEAN_DISABLE=1

mkdir -p "$TMP/edit"
seq 1 290 >"$TMP/edit/CLAUDE.md"
NEW21=$(seq 1 21)

check "$CLAUDE_MD_HOOK" "edit pushing a 290-line file to ~310 is blocked" deny \
  "$(jq -n --arg fp "$TMP/edit/CLAUDE.md" --arg new "$NEW21" \
    '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"x",new_string:$new}}')" \
  IGNORE=1

check "$CLAUDE_MD_HOOK" "edit trimming a 290-line file below the warn threshold is allowed" allow \
  "$(jq -n --arg fp "$TMP/edit/CLAUDE.md" --arg old "$(seq 1 60)" \
    '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:$old,new_string:"x"}}')" \
  IGNORE=1

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
