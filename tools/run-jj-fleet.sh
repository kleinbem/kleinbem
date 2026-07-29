#!/usr/bin/env bash
# Wrapper around `nix run <ROOT>/kleinbem#jj-fleet` that skips the ~1.5-2s
# nixpkgs.legacyPackages evaluation cost on every call. That cost isn't
# `nix run`-specific — it's paid by any fresh nix invocation (run/build/eval)
# that touches `pkgs`, and there's no per-command way around it, only
# per-session (a devshell — see nix-devshells' enterShell, which now also
# puts the built `jj-fleet` binary on PATH directly for anywhere the devshell
# is loaded). This wrapper remains the fast path for the `just` recipes
# specifically (nix/openwrt/kleinbem justfiles, and the bare-root one),
# which don't assume a devshell is loaded.
#
# Build once, cache the resolved /nix/store path, reuse it on every
# subsequent call until the source actually changes (mtime-checked against
# jj-fleet.sh and flake.nix) or the cached store path has been GC'd.
set -euo pipefail

find_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/kleinbem/repos.nix" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "run-jj-fleet.sh: could not find the workspace root (no kleinbem/repos.nix found walking up from $PWD)" >&2
    return 1
}

ROOT="${ROOT:-$(find_root)}"
SCRIPT_SRC="$ROOT/kleinbem/tools/jj-fleet.sh"
FLAKE_SRC="$ROOT/kleinbem/flake.nix"
CACHE_FILE="/tmp/.jj-fleet-store-path-cache"

use_cache=0
if [ -f "$CACHE_FILE" ]; then
    cached_path=$(cat "$CACHE_FILE")
    if [ -x "$cached_path/bin/jj-fleet" ] \
        && [ "$CACHE_FILE" -nt "$SCRIPT_SRC" ] \
        && [ "$CACHE_FILE" -nt "$FLAKE_SRC" ]; then
        use_cache=1
    fi
fi

if [ "$use_cache" -eq 1 ]; then
    binary="$cached_path/bin/jj-fleet"
else
    store_path=$(nix build "$ROOT/kleinbem#jj-fleet" --no-link --print-out-paths)
    echo "$store_path" >"$CACHE_FILE"
    binary="$store_path/bin/jj-fleet"
fi

ROOT="$ROOT" exec "$binary" "$@"
