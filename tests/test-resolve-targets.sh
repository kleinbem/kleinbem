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
    "nix,nix-config,openwrt,openwrt-builder" \
    "$(run "" nix nix-config openwrt openwrt-builder)" \
    "no filter -> every repo, order preserved"

assert_empty \
    "$(run "")" \
    "no filter, empty repo list -> empty"

assert_eq \
    "nix,nix-config,nix-presets,nix-secrets" \
    "$(run "nix" nix nix-config nix-presets nix-secrets openwrt openwrt-builder)" \
    "filter 'nix' -> the bare 'nix' repo plus the whole nix-* family"

assert_eq \
    "nix-config,nix-presets,nix-secrets" \
    "$(run "nix-" nix nix-config nix-presets nix-secrets openwrt)" \
    "filter 'nix-' -> only nix-*, excludes the bare 'nix' repo (no dash to match)"

assert_eq \
    "nix-secrets" \
    "$(run "nix-secrets" nix nix-config nix-presets nix-secrets openwrt-builder)" \
    "exact single-repo filter -> just that one"

assert_empty \
    "$(run "bogus-repo-xyz" nix-config openwrt-builder)" \
    "no match -> empty, no error"

assert_eq \
    "kleinbem-secrets" \
    "$(run "kleinbem-secrets" nix nix-config kleinbem-secrets)" \
    "filter matches regardless of which repo it is -- no more special-cased categories"

test_summary
