#!/usr/bin/env bash
# shellcheck disable=SC2329  # test_* functions are invoked via declare -F discovery
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_eq() {
  if [[ "$1" != "$2" ]]; then
    echo "${3:-assert_eq}: expected '$1', got '$2'" >&2
    return 1
  fi
}

run_merge() {
  printf '%s' "$1" >"$TMP/a.json"
  printf '%s' "$2" >"$TMP/b.json"
  jq -cS -n --slurpfile a "$TMP/a.json" --slurpfile b "$TMP/b.json" \
    -L "$REPO/lib" 'include "merge"; merge($a[0]; $b[0])'
}

test_merge_objects_recursive() {
  assert_eq '{"a":{"x":1,"y":3}}' "$(run_merge '{"a":{"x":1,"y":2}}' '{"a":{"y":3}}')"
}

test_merge_arrays_concat_dedup() {
  assert_eq '{"p":["a","b","-a"]}' "$(run_merge '{"p":["a","b"]}' '{"p":["b","-a"]}')"
}

test_merge_scalar_local_wins() {
  assert_eq '{"model":"y"}' "$(run_merge '{"model":"x"}' '{"model":"y"}')"
}

test_merge_type_mismatch_local_wins() {
  assert_eq '{"a":{"b":1}}' "$(run_merge '{"a":[1]}' '{"a":{"b":1}}')"
}

source "$REPO/tests/installer.sh"

main() {
  local fails=0 name
  mkdir -p /tmp/opencode
  while read -r name; do
    if out=$(
      TMP="$(mktemp -d /tmp/opencode/test.XXXXXX)"
      trap 'rm -rf "$TMP"' EXIT
      set -e
      "$name" 2>&1
    ); then
      echo "PASS $name"
    else
      echo "FAIL $name: $out"
      fails=$((fails + 1))
    fi
  done < <(declare -F | awk '{print $3}' | grep '^test_')
  exit $((fails > 0))
}

main
