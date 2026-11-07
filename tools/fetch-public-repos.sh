#!/usr/bin/env bash
# Shallow-clones every public repo in repos.nix into <dest>/<name>, the layout
# of the workspace root, so the fleet audits run in CI the same as locally.
# Repos the token can't see (private) are listed on stderr and skipped.
#
# Usage: fetch-public-repos.sh <repos.nix> <dest>
set -euo pipefail

repos_nix="$1"
dest="$2"
mkdir -p "$dest"

entries="$(sed -nE 's/^[[:space:]]*"?([A-Za-z0-9_.-]+)"?[[:space:]]*=[[:space:]]*"git@github\.com:([^"]+)\.git".*/\1 \2/p' "$repos_nix")"
[[ -n "$entries" ]] || { echo "no repos found in $repos_nix" >&2; exit 2; }

cloned=0
while read -r name slug; do
    if ! err="$(gh api "repos/$slug" --jq .full_name </dev/null 2>&1 >/dev/null)"; then
        if [[ "$err" == *"HTTP 404"* ]]; then
            echo "skipped (private or gone): $slug" >&2
            continue
        fi
        echo "looking up $slug failed: $err" >&2
        exit 2
    fi
    GIT_TERMINAL_PROMPT=0 git clone -q --depth 1 "https://github.com/$slug" "$dest/$name" </dev/null
    cloned=$((cloned + 1))
done <<<"$entries"
echo "cloned $cloned repos into $dest" >&2
