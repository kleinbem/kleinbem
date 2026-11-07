#!/usr/bin/env bash
# Reports how old each repo's locked nixpkgs is (falling back to the newest
# locked input), read from flake.lock: file mtimes mean nothing after a clone.
#
# Usage: check-flake-lock-age.sh <root>   (NOW=<epoch> overrides the clock)
# Exit: 0 fresh, 1 a lock is over 30 days old, 2 couldn't check.
set -euo pipefail

root="$1"
now="${NOW:-$(date +%s)}"

checked=0
stale=0
echo "📅 flake.lock freshness (age of the locked nixpkgs)"
echo
for lock in "$root"/*/flake.lock; do
    [[ -f "$lock" ]] || continue
    dir="$(dirname "$lock")"
    [[ "$dir" == *.ws ]] && continue
    name="$(basename "$dir")"
    # The root's nixpkgs input names its node; a follows path is a list.
    if ! modified="$(jq -er '
        (.nodes[.nodes[.root].inputs.nixpkgs | strings]?.locked.lastModified)
        // ([.nodes[].locked.lastModified | numbers] | max)' "$lock")"; then
        echo "can't read lastModified from $lock" >&2
        exit 2
    fi
    checked=$((checked + 1))
    days=$(((now - modified) / 86400))
    date="$(date -u -d "@$modified" +%F)"
    if ((days > 30)); then
        echo "⚠️  $name: $days days old ($date)"
        stale=1
    elif ((days > 14)); then
        echo "📋 $name: $days days old ($date)"
    else
        echo "✅ $name: $days days old ($date)"
    fi
done
((checked > 0)) || { echo "no flake.lock under $root" >&2; exit 2; }
echo
echo "Refresh a stale lock with: just in <repo> nix flake update"
exit "$stale"
