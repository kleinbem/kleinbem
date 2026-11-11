#!/usr/bin/env bash
# link-root-files.sh <root>
#
# The root isn't a repo, so it holds relative symlinks to kleinbem/root/
# AGENTS.md, CLAUDE.md, GEMINI.md, .goosehints, justfile and .envrc. Creates missing links;
# a same-content file is replaced by the link, a differing one is left alone with a note. Run by `just bootstrap`.
set -euo pipefail

root="${1:?usage: link-root-files.sh <workspace-root>}"
status=0

for f in AGENTS.md CLAUDE.md GEMINI.md .goosehints justfile .envrc; do
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
