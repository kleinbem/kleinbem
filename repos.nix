# Fleet-wide sub-repo manifest — single source of truth for every repo in the
# kleinbem workspace. Flat list, no categorization: every repo is a peer,
# including the three former "conductors" (nix, openwrt, kleinbem itself) —
# there's no nix-specific or openwrt-specific handling anywhere in the
# tooling that reads this file. Add a new repo here and it's immediately
# visible to status-all/bootstrap/etc, from anywhere in the workspace, with
# zero other setup.
#
# To clone every repo, run `just jj::bootstrap` (or bare `jj-fleet bootstrap`
# if the devshell has it on PATH) from anywhere in the workspace — it skips
# whatever's already on disk, so running it from inside one of these repos
# never tries to re-clone itself. Each repo is its own independent git+jj
# repo with its own history & CI — NOT a git submodule.
{
  nix = "git@github.com:kleinbem/nix.git";
  openwrt = "git@github.com:kleinbem/openwrt.git";
  kleinbem = "git@github.com:kleinbem/kleinbem.git";
  nix-config = "git@github.com:kleinbem/nix-config.git";
  nix-devshells = "git@github.com:kleinbem/nix-devshells.git";
  nix-hardware = "git@github.com:kleinbem/nix-hardware.git";
  nix-packages = "git@github.com:kleinbem/nix-packages.git";
  nix-presets = "git@github.com:kleinbem/nix-presets.git";
  nix-templates = "git@github.com:kleinbem/nix-templates.git";
  openwrt-builder = "git@github.com:kleinbem/openwrt-builder.git";
  openwrt-config = "git@github.com:kleinbem/openwrt-config.git";
  github-config = "git@github.com:kleinbem/github-config.git";
  kleinbem-secrets = "git@github.com:kleinbem/kleinbem-secrets.git";
  kleinbem-site = "git@github.com:kleinbem/kleinbem-site.git";
  kleinbem-auth = "git@github.com:kleinbem/kleinbem-auth.git";
}
