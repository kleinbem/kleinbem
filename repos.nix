# Fleet-wide sub-repo manifest — single source of truth for every repo in the
# kleinbem workspace. Replaces the two separate nix/repos.nix and
# openwrt/repos.nix manifests (superseded, deleted).
#
# Each entry is { url; domain; }. `domain` drives which conductor's dashboard
# a repo shows up in by default (see kleinbem/.just/common.just — the DOMAIN
# variable resolves to the invoking conductor's directory name):
#   - "nix"     — default scope for `nix/`
#   - "openwrt" — default scope for `openwrt/`
#   - "shared"  — appears in EVERY conductor's default scope (cross-cutting:
#                 governs or is needed by more than one domain)
# `kleinbem/`'s own dashboard always operates on the full fleet regardless of
# domain.
#
# To clone every repo in scope, run `just jj::bootstrap` from any conductor
# (or from `kleinbem/` for the whole fleet). Each repo is its own independent
# git+jj repo with its own history & CI — NOT a git submodule.
{
  nix-config = {
    url = "git@github.com:kleinbem/nix-config.git";
    domain = "nix";
  };
  nix-devshells = {
    url = "git@github.com:kleinbem/nix-devshells.git";
    domain = "nix";
  };
  nix-hardware = {
    url = "git@github.com:kleinbem/nix-hardware.git";
    domain = "nix";
  };
  nix-packages = {
    url = "git@github.com:kleinbem/nix-packages.git";
    domain = "nix";
  };
  nix-presets = {
    url = "git@github.com:kleinbem/nix-presets.git";
    domain = "nix";
  };
  nix-secrets = {
    url = "git@github.com:kleinbem/nix-secrets.git";
    domain = "nix";
  };
  nix-templates = {
    url = "git@github.com:kleinbem/nix-templates.git";
    domain = "nix";
  };
  openwrt-builder = {
    url = "git@github.com:kleinbem/openwrt-builder.git";
    domain = "openwrt";
  };
  openwrt-config = {
    url = "git@github.com:kleinbem/openwrt-config.git";
    domain = "openwrt";
  };
  openwrt-secrets = {
    url = "git@github.com:kleinbem/openwrt-secrets.git";
    domain = "openwrt";
  };
  github-config = {
    url = "git@github.com:kleinbem/github-config.git";
    domain = "shared";
  };
  kleinbem-secrets = {
    url = "git@github.com:kleinbem/kleinbem-secrets.git";
    domain = "shared";
  };
}
