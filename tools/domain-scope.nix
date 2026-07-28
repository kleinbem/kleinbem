# Fleet manifest domain-scope helper.
#
# Given the parsed kleinbem/repos.nix attrset and $DOMAIN (read from the
# environment — impure by design, since this is invoked via `nix eval
# --impure`), returns the space-separated list of repo names whose domain
# matches DOMAIN or is tagged "shared".
#
# This is the single source of truth behind kleinbem/.just/common.just's
# REPOS/MANIFEST_SCOPE derivation AND kleinbem/tests/test-domain-scope.sh —
# extracted to its own file specifically so it can be unit-tested directly
# (nix eval --apply against a fixture manifest) without going through the
# heavier just/shell-escaping machinery.
repos:
let
  domain = builtins.getEnv "DOMAIN";
in
builtins.concatStringsSep " " (
  builtins.filter
    (n: repos.${n}.domain == domain || repos.${n}.domain == "shared")
    (builtins.attrNames repos)
)
