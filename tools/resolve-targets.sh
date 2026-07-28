#!/usr/bin/env bash
# resolve-targets.sh <filter> <default-scope repos...> -- <all repos...>
#
# Prints the space-separated list of repos a fan-out jj recipe (status-all,
# save-all, ship-all, ...) should operate on for this invocation.
#
#   no filter   -> the default scope as-is (the invoking conductor's domain,
#                  or the full fleet when invoked from kleinbem/)
#   filter given -> substring-matched against the FULL fleet, not just the
#                  default scope, so e.g. `just status-all nix-secrets` works
#                  from openwrt/ too (cross-domain lookup by design).
set -euo pipefail

filter="$1"
shift

default_scope=()
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
  default_scope+=("$1")
  shift
done
shift # drop the -- separator

all=("$@")

if [ -z "$filter" ]; then
  printf '%s\n' "${default_scope[@]}"
else
  for repo in "${all[@]}"; do
    case "$repo" in
    *"$filter"*) printf '%s\n' "$repo" ;;
    esac
  done
fi
