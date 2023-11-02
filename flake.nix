{
  description = "A simple cli-driven todo app inspired by Todo.txt";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    devenv.url = "github:cachix/devenv";
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    devenv,
    ...
  } @inputs: 
  let
    supportedSystems = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
      "x86_64-darwin"
    ];
  in
    flake-utils.lib.eachSystem supportedSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShell = devenv.lib.mkShell { 
          inherit inputs pkgs;

          modules = [
            ({pkgs, ...}: {
              packages = [pkgs.zig pkgs.zls];

              # zig build test
              scripts.zbt.exec = "zig build test";
              scripts.zbr.exec = "zig build run";
            })
          ];
        };
      });
}
