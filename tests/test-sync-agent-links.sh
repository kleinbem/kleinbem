#!/usr/bin/env bash
# Tests for tools/sync-agent-links.sh against a fake workspace root
# in a temp dir. No nix/jj/git.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
SCRIPT="$HERE/../tools/sync-agent-links.sh"

tmp_parent=$(mktemp -d)
trap 'rm -rf "$tmp_parent"' EXIT

tmp="$tmp_parent/kleinbem"
mkdir -p "$tmp"

# Create fake kleinbem and repos.nix
mkdir -p "$tmp/kleinbem/tools"
cp "$HERE/../tools/resolve-targets.sh" "$tmp/kleinbem/tools/"
chmod +x "$tmp/kleinbem/tools/resolve-targets.sh"

cat <<'EOF' >"$tmp/kleinbem/repos.nix"
{
  repo-a = "git@github.com:kleinbem/repo-a.git";
  repo-b = "git@github.com:kleinbem/repo-b.git";
  repo-c = "git@github.com:kleinbem/repo-c.git";
}
EOF

# repo-a: clean repo with AGENTS.md
mkdir -p "$tmp/repo-a"
echo "content-a" >"$tmp/repo-a/AGENTS.md"

# repo-a: also old GEMINI.md / .goosehints links to AGENTS.md, to be removed
ln -s AGENTS.md "$tmp/repo-a/GEMINI.md"
ln -s AGENTS.md "$tmp/repo-a/.goosehints"

# repo-b: has AGENTS.md, CLAUDE.md with same content, and a real .goosehints
mkdir -p "$tmp/repo-b"
echo "content-b" >"$tmp/repo-b/AGENTS.md"
echo "content-b" >"$tmp/repo-b/CLAUDE.md"
echo "own-goose-hints" >"$tmp/repo-b/.goosehints"

# repo-c: no AGENTS.md (should be skipped without error)
mkdir -p "$tmp/repo-c"

echo "sync-agent-links.sh"

# Run across all repos
rc=0
_out=$(bash "$SCRIPT" "$tmp") || rc=$?

# repo-a assertions
assert_eq "AGENTS.md" "$(readlink "$tmp/repo-a/CLAUDE.md")" \
    "repo-a: CLAUDE.md -> AGENTS.md created"
assert_eq "no" "$([ -e "$tmp/repo-a/GEMINI.md" ] || [ -L "$tmp/repo-a/GEMINI.md" ] && echo yes || echo no)" \
    "repo-a: old GEMINI.md link removed"
assert_eq "no" "$([ -e "$tmp/repo-a/.goosehints" ] || [ -L "$tmp/repo-a/.goosehints" ] && echo yes || echo no)" \
    "repo-a: old .goosehints link removed"

# repo-b assertions
assert_eq "AGENTS.md" "$(readlink "$tmp/repo-b/CLAUDE.md")" \
    "repo-b: same-content CLAUDE.md replaced with link"
assert_eq "no" "$([ -e "$tmp/repo-b/GEMINI.md" ] && echo yes || echo no)" \
    "repo-b: no GEMINI.md created"
assert_eq "own-goose-hints" "$(cat "$tmp/repo-b/.goosehints")" \
    "repo-b: a real .goosehints file is kept"
assert_eq "0" "$rc" "clean run exits 0"

# Foreign symlink handling
rm "$tmp/repo-a/CLAUDE.md"
ln -s "elsewhere.md" "$tmp/repo-a/CLAUDE.md"
ln -s "elsewhere.md" "$tmp/repo-a/GEMINI.md"
rc=0
bash "$SCRIPT" "$tmp" "repo-a" >/dev/null || rc=$?
assert_eq "elsewhere.md" "$(readlink "$tmp/repo-a/CLAUDE.md")" \
    "foreign CLAUDE.md symlink left alone"
assert_eq "elsewhere.md" "$(readlink "$tmp/repo-a/GEMINI.md")" \
    "foreign GEMINI.md symlink left alone"
assert_eq "1" "$rc" "foreign symlink causes exit 1"

# Hardlink handling: hardlink to AGENTS.md is left alone, causes exit 1
rm "$tmp/repo-a/CLAUDE.md"
ln "$tmp/repo-a/AGENTS.md" "$tmp/repo-a/CLAUDE.md"
rc=0
bash "$SCRIPT" "$tmp" "repo-a" >/dev/null || rc=$?
assert_empty "$(readlink "$tmp/repo-a/CLAUDE.md" || true)" \
    "hardlink to AGENTS.md left alone"
assert_eq "1" "$rc" "hardlink causes exit 1"

# Sibling org repo (e.g. kleinbem-dev), with both repo and repo-dev existing
mkdir -p "$tmp/../kleinbem-dev/repo"
mkdir -p "$tmp/../kleinbem-dev/repo-dev"
echo "content-dev" >"$tmp/../kleinbem-dev/repo-dev/AGENTS.md"
cat <<'EOF' >"$tmp/kleinbem/repos.nix"
{
  repo-dev = "git@github.com:kleinbem-dev/repo-dev.git";
  coderabbit-dev = "git@github.com:kleinbem-dev/coderabbit.git";
}
EOF
rc=0
bash "$SCRIPT" "$tmp" "repo-dev" >/dev/null || rc=$?
assert_eq "0" "$rc" "sibling org repo run exits 0"
assert_eq "AGENTS.md" "$(readlink "$tmp/../kleinbem-dev/repo-dev/CLAUDE.md")" \
    "sibling org repo: CLAUDE.md -> AGENTS.md created in repo-dev, not repo"
assert_empty "$(readlink "$tmp/../kleinbem-dev/repo/CLAUDE.md" || true)" \
    "sibling org repo: non-target repo directory untouched"

# Sibling aliased repo (coderabbit-dev -> kleinbem-dev/coderabbit)
mkdir -p "$tmp/../kleinbem-dev/coderabbit"
echo "content-coderabbit" >"$tmp/../kleinbem-dev/coderabbit/AGENTS.md"
rc=0
bash "$SCRIPT" "$tmp" "coderabbit-dev" >/dev/null || rc=$?
assert_eq "0" "$rc" "sibling aliased repo run exits 0"
assert_eq "AGENTS.md" "$(readlink "$tmp/../kleinbem-dev/coderabbit/CLAUDE.md")" \
    "sibling aliased repo: CLAUDE.md -> AGENTS.md created in coderabbit"

test_summary
