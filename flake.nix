{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls";
  };

  outputs = { self, nixpkgs, zig, zls, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ zig.overlays.default ];
        zlsPkg = zls.packages.${system}.default;
        pkgs = import nixpkgs { inherit system overlays; };

        runtimeDeps = with pkgs; [ SDL2 pkg-config ];

      in
      {
        formatter = pkgs.nixpkgs-fmt;
        devShells = {
          default = pkgs.mkShell {
            nativeBuildInputs = runtimeDeps;
            buildInputs =
              [
                # NOTE: these need to be roughly in sync
                pkgs.zigpkgs.master
                zlsPkg

                # common
                pkgs.just
              ];
          };
        };

        packages = { default = pkgs.hello; };
      });
}
