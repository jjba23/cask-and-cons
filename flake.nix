# cask-and-cons

# Copyright © Josep Bigorra <jjbigorra@gmail.com>

# SPDX-License-Identifier: MIT

{
  description = "cask-and-cons: the Nix packages `caco install-nix' puts in the user profile";

  inputs = {
    nix-jointhefreeworld = {
      # git+https rather than github: the latter goes through the GitHub API,
      # which rate-limits unauthenticated clients.
      url = "git+https://github.com/jjba23/nix-jointhefreeworld";
    };
    # One nixpkgs for everything, the one the package set itself is built on.
    nixpkgs.follows = "nix-jointhefreeworld/nixpkgs";
  };

  outputs = { self, nixpkgs, nix-jointhefreeworld }:
    let
      inherit (nixpkgs) lib;
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];

      # Names in the nix-jointhefreeworld package set to install.  Programs
      # first, then the Guile libraries whose tools are wanted too.  Packages
      # that do not build on the current platform (lambdock is linux-only) are
      # skipped rather than failing the whole profile.
      wanted = [
        "maak"
        "sift"
        # "guile-veritas" fails to build on aarch64-darwin (Guile compiler
        # crash, bytevector-u8-ref out of range); re-enable once fixed upstream.
        "araneola"
        "ggg"
        "iter-vitae"
        "lenkesamler"
        "mutastructura"
      ];

      # Plain nixpkgs attributes: linters and language servers.
      nixpkgsWanted = [
        "just"
        "shellcheck"
        # delta, the diff viewer `~/.gitconfig' pages through.  macOS gets it
        # from the `git-delta' formula in brew.scm; nixpkgs calls the package
        # `delta' and it covers the Linux systems this flake builds for, where
        # there is no brew.
        "delta"
        "bash-language-server"
        "yaml-language-server"
        # vscode-json-language-server (plus html/css/eslint servers)
        "vscode-langservers-extracted"
        "nil"
        "marksman"
      ];

      toolsFor = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          set = nix-jointhefreeworld.packages.${system};
          present = lib.filter
            (name: set ? ${name} && lib.meta.availableOn pkgs.stdenv.hostPlatform set.${name})
            wanted;
        in
        pkgs.buildEnv {
          name = "caco-tools";
          # maak and iter-vitae both ship share/resources/help.txt.
          ignoreCollisions = true;
          paths = map (name: set.${name}) present
            ++ map (name: pkgs.${name}) nixpkgsWanted;
        };
    in
    {
      packages = lib.genAttrs systems (system: {
        caco-tools = toolsFor system;
        default = toolsFor system;
      });
    };
}
