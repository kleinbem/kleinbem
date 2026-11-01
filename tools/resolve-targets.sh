#!/usr/bin/env bash
# resolve-targets.sh <filter> <repo...>
#
# Prints the repos a fan-out recipe should cover: all of them, or those whose
# name contains <filter> ("nix" also matches the bare nix repo, "nix-" doesn't).
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
