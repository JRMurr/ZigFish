{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs = { self, nixpkgs, zig, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ zig.overlays.default ];
        pkgs = import nixpkgs { inherit system overlays; };
      in
      {
        formatter = pkgs.nixpkgs-fmt;
        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs;
              [
                pkgs.zigpkgs.default # latest release https://github.com/mitchellh/zig-overlay/blob/98339f7226cd6310f9be2658e95e81970f83dba5/flake.nix#L30

                # common
                just
              ];
          };
        };

        packages = { default = pkgs.hello; };
      });
}
