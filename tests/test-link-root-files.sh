#!/usr/bin/env bash
# Tests for tools/link-root-files.sh against a throwaway fake workspace root
# in a temp dir. No nix/jj/git.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
SCRIPT="$HERE/../tools/link-root-files.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/kleinbem/root"
for f in CLAUDE.md justfile .envrc; do
    echo "tracked $f" >"$tmp/kleinbem/root/$f"
done

echo "link-root-files.sh"

# Fresh root: justfile matches the tracked copy, .envrc has local edits,
# CLAUDE.md is missing.
echo "tracked justfile" >"$tmp/justfile"
echo "local edit" >"$tmp/.envrc"

rc=0
out=$(bash "$SCRIPT" "$tmp") || rc=$?

assert_eq "kleinbem/root/CLAUDE.md" "$(readlink "$tmp/CLAUDE.md")" \
    "missing file -> relative link created"
assert_eq "kleinbem/root/justfile" "$(readlink "$tmp/justfile")" \
    "regular file with same content -> replaced with link"
assert_empty "$(readlink "$tmp/.envrc" || true)" \
    "regular file that differs -> not replaced"
assert_eq "local edit" "$(cat "$tmp/.envrc")" \
    "differing file keeps its content"
assert_eq "1" "$(grep -c '.envrc: local file differs' <<<"$out")" \
    "differing file -> note printed"
assert_eq "1" "$rc" "anything left alone -> exit 1"

# Resolve the conflict, run again: idempotent, all linked, exit 0.
rm "$tmp/.envrc"
rc=0
out=$(bash "$SCRIPT" "$tmp") || rc=$?
assert_eq "kleinbem/root/.envrc" "$(readlink "$tmp/.envrc")" \
    "second run links the freed-up file"
assert_eq "3" "$(grep -c '(linked)\|(link created)' <<<"$out")" \
    "second run reports all three linked"
assert_eq "0" "$rc" "all linked -> exit 0"

# A symlink pointing somewhere else is left alone.
ln -sfn elsewhere "$tmp/CLAUDE.md"
rc=0
bash "$SCRIPT" "$tmp" >/dev/null || rc=$?
assert_eq "elsewhere" "$(readlink "$tmp/CLAUDE.md")" \
    "foreign symlink -> left alone"
assert_eq "1" "$rc" "foreign symlink -> exit 1"

test_summary
