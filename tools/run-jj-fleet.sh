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
# Per-user cache: the path read back here gets exec'd, so it must not be writable by others.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/kleinbem"
CACHE_FILE="$CACHE_DIR/jj-fleet-store-path"
# shellcheck disable=SC2174 # only the kleinbem dir itself needs 700
mkdir -p -m 700 "$CACHE_DIR" 2>/dev/null || true
cache_ok=0
if [ -O "$CACHE_DIR" ] && [ -z "$(find "$CACHE_DIR" -maxdepth 0 -perm /022)" ]; then
    cache_ok=1
fi

use_cache=0
if [ "$cache_ok" -eq 1 ] && [ -f "$CACHE_FILE" ] && [ -O "$CACHE_FILE" ]; then
    cached_path=$(cat "$CACHE_FILE")
    if [[ "$cached_path" =~ ^/nix/store/[a-z0-9]{32}-[^/]+$ ]] \
        && [ -x "$cached_path/bin/jj-fleet" ] \
        && [ "$CACHE_FILE" -nt "$SCRIPT_SRC" ] \
        && [ "$CACHE_FILE" -nt "$FLAKE_SRC" ]; then
        use_cache=1
    fi
fi

if [ "$use_cache" -eq 1 ]; then
    binary="$cached_path/bin/jj-fleet"
else
    store_path=$(nix build "$ROOT/kleinbem#jj-fleet" --no-link --print-out-paths)
    if [ "$cache_ok" -eq 1 ]; then
        echo "$store_path" >"$CACHE_FILE"
    fi
    binary="$store_path/bin/jj-fleet"
fi

ROOT="$ROOT" exec "$binary" "$@"
