#!/usr/bin/env bash
# Unit tests for tools/domain-scope.nix — the domain-filtering function
# behind common.just's MANIFEST_SCOPE. Runs against a small synthetic
# fixture manifest (NOT the real kleinbem/repos.nix), so these stay fast and
# never need updating when real repos get added/removed. Requires `nix`.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
SCOPE_NIX="$HERE/../tools/domain-scope.nix"

FIXTURE="$(mktemp)"
trap 'rm -f "$FIXTURE"' EXIT
cat >"$FIXTURE" <<'EOF'
{
  nix-config = { url = "u"; domain = "nix"; };
  nix-presets = { url = "u"; domain = "nix"; };
  openwrt-builder = { url = "u"; domain = "openwrt"; };
  openwrt-config = { url = "u"; domain = "openwrt"; };
  github-config = { url = "u"; domain = "shared"; };
  kleinbem-secrets = { url = "u"; domain = "shared"; };
}
EOF

# run <domain> — joins the space-separated nix output with commas, then
# re-sorts (attrNames order isn't something this function's contract
# guarantees, and doesn't need to) so assertions aren't order-sensitive.
run() {
    DOMAIN="$1" nix eval --raw --file "$FIXTURE" --impure --apply "rs: import \"$SCOPE_NIX\" rs" \
        | tr ' ' '\n' | sort | paste -sd, -
}

echo "domain-scope.nix"

assert_eq \
    "github-config,kleinbem-secrets,nix-config,nix-presets" \
    "$(run nix)" \
    "DOMAIN=nix -> nix-tagged + shared-tagged"

assert_eq \
    "github-config,kleinbem-secrets,openwrt-builder,openwrt-config" \
    "$(run openwrt)" \
    "DOMAIN=openwrt -> openwrt-tagged + shared-tagged"

assert_eq \
    "github-config,kleinbem-secrets" \
    "$(run kleinbem)" \
    "DOMAIN=kleinbem -> only shared-tagged (the 'means everything' rule lives in common.just, not here)"

assert_eq \
    "github-config,kleinbem-secrets" \
    "$(run some-future-domain-nobody-tagged-yet)" \
    "unrecognised domain -> degrades to shared-tagged only, never errors"

# A manifest with nothing tagged "shared" at all should still resolve cleanly.
NOSHARED="$(mktemp)"
trap 'rm -f "$FIXTURE" "$NOSHARED"' EXIT
cat >"$NOSHARED" <<'EOF'
{
  a = { url = "u"; domain = "x"; };
  b = { url = "u"; domain = "y"; };
}
EOF
assert_eq \
    "a" \
    "$(DOMAIN=x nix eval --raw --file "$NOSHARED" --impure --apply "rs: import \"$SCOPE_NIX\" rs" | tr ' ' '\n' | sort | paste -sd, -)" \
    "manifest with no 'shared' entries at all still resolves correctly"

test_summary
