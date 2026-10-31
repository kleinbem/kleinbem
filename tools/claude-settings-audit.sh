#!/usr/bin/env bash
# Lists Claude Code settings files under the workspace root that hold
# permission rules (permissions.allow/ask/deny). The fleet's rules live in
# the NixOS managed settings (nix-config modules/nixos/files/
# claude-code-policy.json); every "don't ask again" adds one more exact
# command to a .claude/settings.local.json wherever the session ran, and
# those pile up unseen (2026-10-31: 24 files, one with 117 rules).
#
# Usage: claude-settings-audit.sh <root>
# Output, one TSV line per file with rules: <kind>\t<rules>\t<path relative to root>
#   local  .claude/settings.local.json at the root, a repo or a workspace (info)
#   shared .claude/settings.json at the root, a repo or a workspace (belongs in the policy)
#   stray  any other .claude/ dir, e.g. a session started in a subfolder
set -euo pipefail

root="${1:?usage: claude-settings-audit.sh <root>}"
cd "$root"

# No depth limit: a rule file anywhere counts. The prunes keep it fast (~60 ms
# on the whole workspace). A directory find can't read makes it, and so this
# script, exit non-zero (pipefail), so callers can tell a partial scan apart.
find . \
    \( -name .jj -o -name .git -o -name node_modules -o -name target -o -name .direnv -o -name result \) -prune \
    -o -path '*/.claude/settings*.json' -type f -print 2>/dev/null |
    sed 's|^\./||' | LC_ALL=C sort |
    while IFS= read -r f; do
        rules=$(jq '[.permissions.allow, .permissions.ask, .permissions.deny] | map(length? // 0) | add' "$f" 2>/dev/null || echo 0)
        [ "${rules:-0}" -gt 0 ] || continue
        dir="${f%/.claude/*}"
        [ "$dir" = "$f" ] && dir=""
        # The root itself, <repo>/ or <repo>.ws/<name>/ count as homes; anything deeper is a stray.
        if [ -z "$dir" ] || [[ "$dir" != */* ]] || [[ "$dir" =~ ^[^/]+\.ws/[^/]+$ ]]; then
            case "$f" in
            *settings.local.json) kind=local ;;
            *) kind=shared ;;
            esac
        else
            kind=stray
        fi
        printf '%s\t%s\t%s\n' "$kind" "$rules" "$f"
    done
