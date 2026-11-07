#!/usr/bin/env bash
# Lists pinned SDK/tool versions (platformToolsVersion = "37.0.1", ...) in the
# fleet's nix-* and openwrt-* repos under <root>, for review against nixpkgs.
#
# Usage: audit-versions.sh <root> [filter]
# Exit: 0 done, 2 couldn't scan.
set -euo pipefail

root="$1"
filter="${2:-}"

scanned=0
echo "🔍 Pinned package versions"
echo
for repo in "$root"/nix-*/ "$root"/openwrt-*/; do
    [[ -d "$repo" ]] || continue
    repo="${repo%/}"
    # <repo>.ws/ holds agent workspaces, copies of the same repo.
    [[ "$repo" == *.ws ]] && continue
    name="$(basename "$repo")"
    scanned=$((scanned + 1))
    # grep exits 1 for no match, 2 for an error.
    rc=0
    matches="$(cd "$root" && grep -rE --include='*.nix' '(platform|build|tools|cmdLine)[A-Za-z]*Versions?[[:space:]]*=.*[0-9]+\.[0-9]+' "$name")" || rc=$?
    ((rc <= 1)) || { echo "grep failed in $repo" >&2; exit 2; }
    [[ -n "$filter" ]] && matches="$(grep -F -- "$filter" <<<"$matches" || true)"
    [[ -n "$matches" ]] || continue
    echo "📦 $name:"
    while IFS= read -r line; do echo "  $line"; done <<<"$matches"
    echo
done
((scanned > 0)) || { echo "no nix-* or openwrt-* repos under $root" >&2; exit 2; }
echo "✓ Scanned $scanned repos"
