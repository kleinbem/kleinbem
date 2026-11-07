# Every repo in the kleinbem workspace, flat, conductors included. A repo added
# here shows up in every fan-out recipe with no other setup. `just jj::bootstrap`
# clones whatever is missing; each repo is independent, not a submodule.
{
  nix = "git@github.com:kleinbem/nix.git";
  openwrt = "git@github.com:kleinbem/openwrt.git";
  kleinbem = "git@github.com:kleinbem/kleinbem.git";
  nix-config = "git@github.com:kleinbem/nix-config.git";
  nix-detour = "git@github.com:kleinbem-dev/nix-detour.git";
  nix-detour-fleet = "git@github.com:kleinbem/nix-detour-fleet.git";
  nix-devshells = "git@github.com:kleinbem/nix-devshells.git";
  nix-gantry = "git@github.com:kleinbem-dev/nix-gantry.git";
  nix-hardware = "git@github.com:kleinbem/nix-hardware.git";
  nix-packages = "git@github.com:kleinbem/nix-packages.git";
  nix-presets = "git@github.com:kleinbem/nix-presets.git";
  nix-templates = "git@github.com:kleinbem/nix-templates.git";
  openwrt-builder = "git@github.com:kleinbem/openwrt-builder.git";
  openwrt-config = "git@github.com:kleinbem/openwrt-config.git";
  android-config = "git@github.com:kleinbem/android-config.git";
  github-config = "git@github.com:kleinbem/github-config.git";
  web-config = "git@github.com:kleinbem/web-config.git";
  kleinbem-secrets = "git@github.com:kleinbem/kleinbem-secrets.git";
  kleinbem-site = "git@github.com:kleinbem/kleinbem-site.git";
  ".github" = "git@github.com:kleinbem-dev/.github.git";
  jj-toolbox = "git@github.com:kleinbem/jj-toolbox.git";
  nix-toolbox = "git@github.com:kleinbem/nix-toolbox.git";
  skills = "git@github.com:kleinbem/skills.git";
  mesh-llm-ci = "git@github.com:kleinbem/mesh-llm-ci.git";
  mesh-llm-gpu = "git@github.com:kleinbem/mesh-llm-gpu.git";
  chrome-open-in-app = "git@github.com:kleinbem/chrome-open-in-app.git";
  aur-packages = "git@github.com:kleinbem/aur-packages.git";
  actions = "git@github.com:kleinbem/actions.git";
  coderabbit = "git@github.com:kleinbem/coderabbit.git";
  coderabbit-dev = "git@github.com:kleinbem-dev/coderabbit.git";
  cadre = "git@github.com:kleinbem-dev/cadre.git";
  revue = "git@github.com:kleinbem-dev/revue.git";
  foyer = "git@github.com:kleinbem-dev/foyer.git";
}
