#!/usr/bin/env bash
# Fast path for the just recipes: builds <ROOT>/kleinbem#jj-fleet once and
# caches the store path, skipping the ~1.5-2s nixpkgs eval of every `nix run`.
# Rebuilds when jj-fleet.sh or flake.nix is newer than the cache, or the path is gone.
set -euo pipefail

find_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        # Skip repos: nix/ has a kleinbem -> ../kleinbem symlink.
        if [ -f "$dir/kleinbem/repos.nix" ] && [ ! -d "$dir/.jj" ]; then
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
