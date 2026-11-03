#!/usr/bin/env bash
# sync-agent-links.sh [root] [filter]
#
# Ensures standard AI discovery symlinks (CLAUDE.md, GEMINI.md, .goosehints)
# point to AGENTS.md across every repository in repos.nix.
# Safe, idempotent, leaves differing regular files alone with a note.
set -euo pipefail

find_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/kleinbem/repos.nix" ] && [ ! -d "$dir/.jj" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "sync-agent-links.sh: could not find workspace root" >&2
    return 1
}

ROOT="${1:-$(find_root)}"
FILTER="${2:-}"

get_all_repos() {
    local root="$1"
    local repos=""
    if command -v nix >/dev/null 2>&1; then
        repos=$(nix eval --raw --file "$root/kleinbem/repos.nix" \
            --apply 'rs: builtins.concatStringsSep " " (builtins.attrNames rs)' 2>/dev/null || true)
    fi
    if [ -z "$repos" ] && [ -f "$root/kleinbem/repos.nix" ]; then
        repos=$(sed -nE 's/^[[:space:]]*"?([a-zA-Z0-9_.-]+)"?[[:space:]]*=.*/\1/p' "$root/kleinbem/repos.nix" | tr '\n' ' ')
    fi
    printf '%s\n' "$repos"
}

resolve_repo_dir() {
    local root="$1" name="$2"
    if [ -d "$root/$name" ]; then
        echo "$root/$name"
        return 0
    fi
    local url=""
    if [ -f "$root/kleinbem/repos.nix" ]; then
        url=$(sed -nE 's/^[[:space:]]*"?'"$name"'"?[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$root/kleinbem/repos.nix")
    fi
    url="${url#git@github.com:}"
    url="${url#https://github.com/}"
    url="${url%.git}"
    local org="${url%%/*}"
    local reponame="${url#*/}"
    if [ -n "$org" ] && [ "$org" != "kleinbem" ]; then
        if [ -d "$root/../$org/$reponame" ]; then
            echo "$root/../$org/$reponame"
            return 0
        fi
        if [ -d "$root/../$org/$name" ]; then
            echo "$root/../$org/$name"
            return 0
        fi
    fi
    echo "$root/$name"
}

RESOLVER="$ROOT/kleinbem/tools/resolve-targets.sh"
ALL_REPOS=$(get_all_repos "$ROOT")
# shellcheck disable=SC2086 # intentional word-splitting of ALL_REPOS
TARGETS=$(bash "$RESOLVER" "$FILTER" $ALL_REPOS)
status=0

for repo in $TARGETS; do
    dir="$(resolve_repo_dir "$ROOT" "$repo")"
    [ -d "$dir" ] || continue

    if [ ! -f "$dir/AGENTS.md" ]; then
        continue
    fi

    for link_name in CLAUDE.md GEMINI.md .goosehints; do
        link_path="$dir/$link_name"
        target="AGENTS.md"

        if [ -L "$link_path" ]; then
            dest="$(readlink "$link_path")"
            if [ "$dest" != "$target" ]; then
                echo "  ! $repo/$link_name: points to $dest, not $target; left alone"
                status=1
            fi
        elif [ -e "$link_path" ]; then
            if [ "$link_path" -ef "$dir/$target" ]; then
                echo "  ! $repo/$link_name: hard link to $target; left alone"
                status=1
            elif cmp -s "$link_path" "$dir/$target"; then
                ln -sfn "$target" "$link_path"
                echo "  ✓ $repo/$link_name: same content, replaced with link -> $target"
            else
                echo "  ! $repo/$link_name: differing regular file; left alone"
                status=1
            fi
        else
            ln -s "$target" "$link_path"
            echo "  ✓ $repo/$link_name -> $target (created)"
        fi
    done
done

exit "$status"
