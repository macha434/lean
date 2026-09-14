#!/usr/bin/env bash
# Exercises the PreToolUse hook against the cases that matter: the one it must
# block, and the many it must not.

set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/plugins/haiku-shunt/hooks/check-file-size.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

seq 1 500 >"$TMP/big.txt"
seq 1 10 >"$TMP/small.txt"
printf 'binary\0content\0here' >"$TMP/blob.bin"

pass=0
fail=0

# check <name> <expected: allow|deny> <stdin json> [env assignments...]
check() {
  local name=$1 expected=$2 payload=$3
  shift 3
  local out
  out=$(printf '%s' "$payload" | env "$@" "$HOOK" 2>/dev/null)
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

check "large file from main session is blocked" deny \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\"}}" \
  IGNORE=1

check "large file inside a subagent is allowed" allow \
  "{\"tool_name\":\"Read\",\"agent_id\":\"a1\",\"agent_type\":\"bulk-reader\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\"}}" \
  IGNORE=1

check "small file is allowed" allow \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/small.txt\"}}" \
  IGNORE=1

check "ranged read is allowed" allow \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\",\"limit\":50}}" \
  IGNORE=1

check "offset read is allowed" allow \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\",\"offset\":100}}" \
  IGNORE=1

check "binary file is allowed" allow \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/blob.bin\"}}" \
  IGNORE=1

check "missing file is allowed" allow \
  '{"tool_name":"Read","tool_input":{"file_path":"/nonexistent/nope.txt"}}' \
  IGNORE=1

check "malformed input is allowed" allow \
  'not json at all' \
  IGNORE=1

check "empty input is allowed" allow \
  '' \
  IGNORE=1

check "raised threshold allows the same file" allow \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\"}}" \
  HAIKU_SHUNT_MIN_LINES=1000

check "lowered threshold blocks a small file" deny \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/small.txt\"}}" \
  HAIKU_SHUNT_MIN_LINES=5

check "non-numeric threshold falls back to the default" deny \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\"}}" \
  HAIKU_SHUNT_MIN_LINES=abc

check "disable flag allows everything" allow \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TMP/big.txt\"}}" \
  HAIKU_SHUNT_DISABLE=1

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
