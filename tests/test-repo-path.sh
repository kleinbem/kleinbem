#!/usr/bin/env bash
# Tests for repo_path resolution across primary and sibling org directories,
# exercising tools/jj-fleet.sh directly.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
SCRIPT="$HERE/../tools/jj-fleet.sh"

tmp_parent=$(mktemp -d)
trap 'rm -rf "$tmp_parent"' EXIT

ROOT="$tmp_parent/kleinbem"
mkdir -p "$ROOT/kleinbem"

cat <<'EOF' >"$ROOT/kleinbem/repos.nix"
{
  repo-klein = "git@github.com:kleinbem/repo-klein.git";
  repo-dev = "git@github.com:kleinbem-dev/repo-dev.git";
  repo-aliased-dev = "git@github.com:kleinbem-dev/repo-aliased.git";
  repo-uncloned-dev = "git@github.com:kleinbem-dev/repo-uncloned.git";
}
EOF

run_repo_path() {
    ROOT="$ROOT" bash "$SCRIPT" repo-path "$1"
}

echo "test-repo-path.sh"

# Case 1: Repo exists in primary ROOT
mkdir -p "$ROOT/repo-klein"
assert_eq "$ROOT/repo-klein" "$(run_repo_path "repo-klein")" \
    "repo in primary workspace resolves to \$ROOT/<repo>"

# Case 2: Sibling org repo exists in $ROOT/../kleinbem-dev/<reponame>
mkdir -p "$tmp_parent/kleinbem-dev/repo-dev"
assert_eq "$ROOT/../kleinbem-dev/repo-dev" "$(run_repo_path "repo-dev")" \
    "sibling org repo resolves to \$ROOT/../kleinbem-dev/<repo>"

# Case 3: Sibling org repo with aliased key name
mkdir -p "$tmp_parent/kleinbem-dev/repo-aliased"
assert_eq "$ROOT/../kleinbem-dev/repo-aliased" "$(run_repo_path "repo-aliased-dev")" \
    "aliased sibling org repo resolves to \$ROOT/../kleinbem-dev/<reponame>"

# Case 4: Sibling org repo not yet cloned -> clone target is sibling org directory
assert_eq "$ROOT/../kleinbem-dev/repo-uncloned" "$(run_repo_path "repo-uncloned-dev")" \
    "uncloned sibling org repo targets sibling org directory"

# Case 5: Primary org repo not yet cloned -> clone target is $ROOT/<repo>
assert_eq "$ROOT/unknown-repo" "$(run_repo_path "unknown-repo")" \
    "unknown repo defaults to \$ROOT/<repo>"

test_summary
