{ lib, newScope }:

lib.makeScope newScope (self:
let inherit (self) callPackage;
in {
  fastchess = callPackage ./fastchess.nix { };

})
