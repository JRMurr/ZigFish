{ lib, newScope, zig }:

lib.makeScope newScope (self:
let inherit (self) callPackage;
in {
  fastchess = callPackage ./fastchess.nix { };
  zigfish = callPackage ./zigfish { inherit zig; };
})
