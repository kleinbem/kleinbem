#!/usr/bin/env bash
# Unit tests for tools/audit-versions.sh on fixture repos.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
SCRIPT="$HERE/../tools/audit-versions.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "audit-versions.sh"

mkdir -p "$tmp/nix-a/shells" "$tmp/nix-a.ws/x" "$tmp/other"
cat >"$tmp/nix-a/shells/android.nix" <<'NIX'
{
  platformToolsVersion = "37.0.1";
  buildToolsVersions = [
    "35.0.0"
    "36.0.0"
  ];
  version = "1.2";
}
NIX
cp "$tmp/nix-a/shells/android.nix" "$tmp/nix-a.ws/x/"
cp "$tmp/nix-a/shells/android.nix" "$tmp/other/"

out="$(bash "$SCRIPT" "$tmp")"
assert_eq "5" "$(grep -c 'nix-a/shells/android.nix:' <<<"$out")" "single-line pin plus a multiline list, nothing else"
assert_eq "1" "$(grep -c '"35.0.0"' <<<"$out")" "list items on later lines are listed"
assert_empty "$(grep -E 'nix-a\.ws|other' <<<"$out" || true)" "skips <repo>.ws and non nix-*/openwrt-* dirs"
assert_eq "1" "$(bash "$SCRIPT" "$tmp" platformTools | grep -c android.nix)" "filter keeps matching lines"

rc=0
bash "$SCRIPT" "$tmp/other" >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc" "no repos to scan -> exit 2"

test_summary
