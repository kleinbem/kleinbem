#!/usr/bin/env bash
# resolve-targets.sh <filter> <repo...>
#
# Prints the repos a fan-out jj recipe (status-all, save-all, ship-all, ...)
# should operate on. No domain/default-scope concept — there's one flat list
# of repos and a filter that narrows it.
#
#   no filter   -> print every repo
#   filter given -> substring-match against every repo (e.g. "nix" catches
#                  the whole nix-* family plus the bare "nix" repo; "nix-"
#                  catches only nix-config/nix-presets/etc, not "nix" itself)
set -euo pipefail

filter="$1"
shift

if [ -z "$filter" ]; then
    printf '%s\n' "$@"
else
    for repo in "$@"; do
        case "$repo" in
        *"$filter"*) printf '%s\n' "$repo" ;;
        esac
    done
fi
