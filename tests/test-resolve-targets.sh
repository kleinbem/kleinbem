#!/usr/bin/env bash
# Unit tests for tools/resolve-targets.sh. Pure bash — no nix/jj/git, no
# fixtures on disk, fast. Run directly or via `just test`.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
SCRIPT="$HERE/../tools/resolve-targets.sh"

# Joins resolve-targets.sh's newline-separated output with commas, so
# expected/actual comparisons stay on one line in failure output.
run() {
    bash "$SCRIPT" "$@" | paste -sd, -
}

echo "resolve-targets.sh"

assert_eq \
    "nix,github-config,kleinbem-secrets" \
    "$(run "" nix github-config kleinbem-secrets -- nix github-config kleinbem-secrets nix-config openwrt)" \
    "no filter -> default scope as-is, order preserved"

assert_empty \
    "$(run "" -- nix-config openwrt)" \
    "no filter, empty default scope -> empty (never falls back to 'all')"

assert_eq \
    "nix-config,nix-presets,nix-secrets" \
    "$(run "nix" nix github-config -- nix-config nix-presets nix-secrets github-config openwrt-builder)" \
    "domain-style filter -> substring-matches the FULL fleet, not the default scope"

assert_eq \
    "nix-secrets" \
    "$(run "nix-secrets" nix-config nix-presets -- nix-config nix-presets nix-secrets openwrt-builder)" \
    "exact single-repo filter -> just that one"

assert_eq \
    "nix-secrets" \
    "$(run "nix-secrets" openwrt github-config -- openwrt openwrt-builder github-config nix-secrets)" \
    "cross-domain filter -> finds a repo outside the caller's default scope entirely"

assert_empty \
    "$(run "bogus-repo-xyz" nix-config -- nix-config openwrt-builder)" \
    "no match -> empty, no error"

assert_eq \
    "kleinbem-secrets" \
    "$(run "kleinbem-secrets" nix -- nix nix-config kleinbem-secrets)" \
    "filter matching a 'shared'-tagged repo works the same as any other"

test_summary
