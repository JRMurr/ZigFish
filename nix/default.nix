{ pkgs, lib, newScope, zig }:

lib.makeScope newScope (self:
let inherit (self) callPackage;
in {
  inherit zig;
  books = callPackage ./books.nix { };
  buildAtCommit = callPackage ./buildAtCommit.nix { };
  captureStdErr = callPackage ./captureStdErr.nix { };
  fastchess = callPackage ./fastchess.nix { };
  runFast = callPackage ./runFast.nix { };
  zigfish = callPackage ./zigfish { };



  # TODO: going to slightly older version to work around
  # https://github.com/emscripten-core/emscripten/issues/22249
  # issue says 3.1.64 should fix it but still seems sad...
  emscripten = pkgs.emscripten.overrideAttrs (_: prev: rec {
    version = "3.1.62";
    src = pkgs.fetchFromGitHub {
      owner = "emscripten-core";
      repo = "emscripten";
      hash = "sha256-BAGYewuujJ/UT07yLM0ENfdrhvAgDu5+SBLa9+a73uU=";
      rev = version;
    };
  });
})
