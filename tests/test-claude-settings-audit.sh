#!/usr/bin/env bash
# Tests for tools/claude-settings-audit.sh against a throwaway workspace tree.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
SCRIPT="$HERE/../tools/claude-settings-audit.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

put() { mkdir -p "$(dirname "$T/$1")" && printf '%s\n' "$2" >"$T/$1"; }
rules() { printf '{"permissions":{"allow":[%s]}}' "$1"; }

put .claude/settings.local.json "$(rules '"Bash(a)","Bash(b)"')"
put .claude/settings.json '{}'
put nix/.claude/settings.json "$(rules '"Bash(c)"')"
put nix/.claude/settings.local.json '{"enabledMcpjsonServers":["github"]}'
put nix-config.ws/foo/.claude/settings.local.json '{"permissions":{"deny":["Bash(d)"],"ask":["Bash(e)"]}}'
put nix/.just/.claude/settings.local.json "$(rules '"Bash(f)","Bash(g)","Bash(h)"')"
put nix/.jj/repo/.claude/settings.json "$(rules '"Bash(i)"')"
put nix/broken/.claude/settings.json 'not json'

echo "claude-settings-audit.sh"

out=$(bash "$SCRIPT" "$T" | paste -sd'|' -)

assert_eq \
    "local	2	.claude/settings.local.json|local	2	nix-config.ws/foo/.claude/settings.local.json|shared	1	nix/.claude/settings.json|stray	3	nix/.just/.claude/settings.local.json" \
    "$out" \
    "lists only files with rules; root/repo/workspace are homes, deeper dirs are strays; .jj pruned; broken JSON skipped"

assert_empty "$(bash "$SCRIPT" "$T/nix/broken")" "a tree without rule files prints nothing"

put nix/a/b/c/d/e/.claude/settings.local.json "$(rules '"Bash(j)"')"
assert_eq \
    "stray	1	nix/a/b/c/d/e/.claude/settings.local.json" \
    "$(bash "$SCRIPT" "$T" | grep 'a/b/c' || true)" \
    "no depth limit: a deeply nested rule file is still found"

mkdir -p "$T/locked" && chmod 000 "$T/locked"
rc=0
bash "$SCRIPT" "$T" >/dev/null 2>&1 || rc=$?
chmod 755 "$T/locked"
if [ "$(id -u)" -ne 0 ]; then
    assert_eq "1" "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "an unreadable directory makes the scan exit non-zero"
fi

test_summary
