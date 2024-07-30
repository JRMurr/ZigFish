{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls/0.13.0";
    zon2nix.url = "github:MidstallSoftware/zon2nix";
  };

  outputs = { self, nixpkgs, zig, zls, flake-utils, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ zig.overlays.default ];
        pkgs = import nixpkgs { inherit system overlays; };

        zigPkg = pkgs.zigpkgs."0.13.0"; # keep in sync with zls
        zlsPkg = zls.packages.${system}.default;

        zon2nix = inputs.zon2nix.packages.${system}.default;

        xorgDeps = with pkgs.xorg; [ libXrandr libXinerama libXi ];
        runtimeDeps = with pkgs; [ raylib xorg.libXcursor pkg-config ] ++ xorgDeps;

        myPkgs = import ./nix { inherit (pkgs) lib newScope; zig = zigPkg; };

        emscripten = pkgs.emscripten;


      in
      {
        formatter = pkgs.nixpkgs-fmt;
        devShells = {
          default = pkgs.mkShell {
            nativeBuildInputs = runtimeDeps;
            # needed for ray lib  --sysroot $EMSCRIPTEN_ROOT
            EMSCRIPTEN_ROOT = "${emscripten}/share/emscripten";
            buildInputs =
              [
                pkgs.gcc
                pkgs.glibc
                pkgs.pkg-config
                # NOTE: these need to be roughly in sync
                zigPkg
                zlsPkg
                zon2nix

                pkgs.gdb
                emscripten


                myPkgs.fastchess
                # myPkgs.buildAtCommit
                # myPkgs.runFast

                # common
                pkgs.just
              ];
          };
        };

        packages = {
          default = myPkgs.zigfish;
          fastChess = myPkgs.fastchess;
          runFast = myPkgs.runFast;
          books = myPkgs.books.all;
          popularBook = myPkgs.books."popularpos_lichess.epd";
          emscripten = pkgs.emscripten;
        };
      });
}
