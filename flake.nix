{
  description = ''
    Nix-packaged subset of the shared jj fleet dashboard — writeShellApplication
    (pinned runtimeInputs, shellcheck-gated build), invoked via `nix run` from
    the just recipes in kleinbem/.just/jj.just (status-all, diff-all,
    remote-status, remote-prs, remote-ci, check-signatures, bootstrap,
    init-bookmarks). The recipes with real mutation logic (save-all, push-all,
    ship-all, sign-unsigned, ...) are still plain bash in jj.just — converted
    later once this phase proves out. Path-referenced for now
    (`nix run {{ROOT}}/kleinbem#jj-fleet`), not wired into nix-devshells.
  '';

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      jj-fleet = pkgs.writeShellApplication {
        name = "jj-fleet";
        # Pinned exact binaries — the actual point of packaging this way: the
        # script never depends on whatever happens to be on PATH from
        # whichever devshell is loaded (or isn't).
        runtimeInputs = [
          pkgs.jujutsu
          pkgs.git
          pkgs.nix
          pkgs.gum
          pkgs.gh
          pkgs.jq
          pkgs.coreutils
          pkgs.util-linux # column
        ];
        text = builtins.readFile ./tools/jj-fleet.sh;
      };
    in
    {
      packages.${system}.jj-fleet = jj-fleet;
      apps.${system}.jj-fleet = {
        type = "app";
        program = "${jj-fleet}/bin/jj-fleet";
      };
    };
}
