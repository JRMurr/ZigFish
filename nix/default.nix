{ lib, newScope, zig }:

lib.makeScope newScope (self:
let inherit (self) callPackage;
in {
  books = callPackage ./books.nix { };
  buildAtCommit = callPackage ./buildAtCommit.nix { };
  captureStdErr = callPackage ./captureStdErr.nix { };
  fastchess = callPackage ./fastchess.nix { };
  runFast = callPackage ./runFast.nix { inherit zig; };
  zigfish = callPackage ./zigfish { inherit zig; };
})
