#!/usr/bin/env bash
# link-root-files.sh <root>
#
# The workspace root isn't a repo, so its own files live in kleinbem/root/
# and the root holds relative symlinks to them:
#   <root>/CLAUDE.md -> kleinbem/root/CLAUDE.md
#   <root>/justfile  -> kleinbem/root/justfile
#   <root>/.envrc    -> kleinbem/root/.envrc
#
# Creates any missing link. A regular file with the same content is swapped
# for the link; one that differs is left alone with a note, so local edits
# are never lost. Called by `just bootstrap` (jj-fleet.sh cmd_bootstrap).
set -euo pipefail

root="${1:?usage: link-root-files.sh <workspace-root>}"
status=0

for f in CLAUDE.md justfile .envrc; do
    target="kleinbem/root/$f"
    link="$root/$f"
    if [ ! -e "$root/$target" ]; then
        echo "  ! $f: $target missing, skipped"
        status=1
    elif [ -L "$link" ]; then
        if [ "$(readlink "$link")" = "$target" ]; then
            echo "  ✓ $f (linked)"
        else
            echo "  ! $f: symlink points to $(readlink "$link"), not $target; left alone"
            status=1
        fi
    elif [ -e "$link" ]; then
        if cmp -s "$link" "$root/$target"; then
            ln -sfn "$target" "$link"
            echo "  ✓ $f (same content, replaced with link)"
        else
            echo "  ! $f: local file differs from $target; left alone."
            echo "    Move any local changes into kleinbem/root/$f, then: ln -sfn $target $link"
            status=1
        fi
    else
        ln -s "$target" "$link"
        echo "  ✓ $f (link created)"
    fi
done

exit "$status"
