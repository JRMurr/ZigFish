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
} // {
  # not sure if including this in the above recursive scope would get sad
  # this is overriding emscripten
  emscripten = import ./emscripten { inherit pkgs; };
})
