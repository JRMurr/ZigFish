{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls/0.13.0";
  };

  outputs = { self, nixpkgs, zig, zls, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ zig.overlays.default ];
        zlsPkg = zls.packages.${system}.default;
        pkgs = import nixpkgs { inherit system overlays; };

        xorgDeps = with pkgs.xorg; [ libXrandr libXinerama libXi ];
        runtimeDeps = with pkgs; [ raylib xorg.libXcursor pkg-config ] ++ xorgDeps;

      in
      {
        formatter = pkgs.nixpkgs-fmt;
        devShells = {
          default = pkgs.mkShell {
            nativeBuildInputs = runtimeDeps;
            buildInputs =
              [
                # NOTE: these need to be roughly in sync
                pkgs.zigpkgs."0.13.0" # keep in sync with zls
                zlsPkg

                # common
                pkgs.just
              ];
          };
        };

        packages = { default = pkgs.hello; };
      });
}
