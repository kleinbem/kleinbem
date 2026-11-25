#!/usr/bin/env bash
# Unit tests for tools/check-flake-lock-age.sh on fixture locks.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
SCRIPT="$HERE/../tools/check-flake-lock-age.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
day=86400
export NOW=$((100 * day))

lock() {
    mkdir -p "$tmp/$1"
    printf '%s' "$2" >"$tmp/$1/flake.lock"
}
run() {
    local rc=0
    bash "$SCRIPT" "$tmp" >"$tmp/out" 2>&1 || rc=$?
    echo "$rc"
}

echo "check-flake-lock-age.sh"

lock fresh "{\"root\":\"root\",\"nodes\":{\"root\":{\"inputs\":{\"nixpkgs\":\"np\"}},\"np\":{\"locked\":{\"lastModified\":$((95 * day))}}}}"
assert_eq 0 "$(run)" "fresh nixpkgs -> exit 0"

# An old nixpkgs counts even when another input is new.
lock old "{\"root\":\"root\",\"nodes\":{\"root\":{\"inputs\":{\"nixpkgs\":\"np\"}},\"np\":{\"locked\":{\"lastModified\":$((60 * day))}},\"x\":{\"locked\":{\"lastModified\":$((99 * day))}}}}"
assert_eq 1 "$(run)" "nixpkgs 40 days old -> exit 1"
assert_eq "⚠️  old: 40 days old (1970-03-02)" "$(grep old: "$tmp/out")" "stale line names repo, age and date"
rm -r "$tmp/old"

# A follows path (list) falls back to the newest locked input.
lock follows "{\"root\":\"root\",\"nodes\":{\"root\":{\"inputs\":{\"nixpkgs\":[\"x\",\"nixpkgs\"]}},\"x\":{\"locked\":{\"lastModified\":$((90 * day))}}}}"
assert_eq 0 "$(run)" "follows path -> newest input, fresh"

mkdir -p "$tmp/fresh.ws"
printf '{}' >"$tmp/fresh.ws/flake.lock"
assert_eq 0 "$(run)" "<repo>.ws dirs are skipped"
rm -r "$tmp/fresh.ws"

lock broken '{"root":"root","nodes":{"root":{}}}'
assert_eq 2 "$(run)" "no lastModified -> exit 2"
rm -r "${tmp:?}"/*

assert_eq 2 "$(run)" "no flake.lock at all -> exit 2"

test_summary
