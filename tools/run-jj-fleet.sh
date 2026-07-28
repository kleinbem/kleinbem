#!/usr/bin/env bash
# Wrapper around `nix run <ROOT>/kleinbem#jj-fleet` that skips the ~1.5-2s
# nixpkgs.legacyPackages evaluation cost on every call. That cost isn't
# `nix run`-specific — it's paid by any fresh nix invocation (run/build/eval)
# that touches `pkgs`, and there's no per-command way around it, only
# per-session (a devshell). Wiring jj-fleet into nix-devshells was the other
# option, but a local flake input needs an absolute path (nix's pure-eval
# mode rejects `path:../kleinbem`), which means hardcoding this machine's
# home directory into a file meant to be identical across the fleet — not
# worth it for a speed fix.
#
# Instead: build once, cache the resolved /nix/store path, reuse it on every
# subsequent call until the source actually changes (mtime-checked against
# jj-fleet.sh and flake.nix) or the cached store path has been GC'd.
set -euo pipefail

ROOT="${ROOT:-$(dirname "$PWD")}"
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

exec "$binary" "$@"
