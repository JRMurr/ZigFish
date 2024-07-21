{ writeShellScriptBin, jq, nix, lib }:
let
  getExe = lib.getExe;
in
writeShellScriptBin "buildAtCommit" ''
    set -euo pipefail

  # 3d62d81a61e891f606bf8ce457dd9e4f2a5387ab
  PATH=$(${getExe nix} build github:JRMurr/ZigFish?rev=$1 --json | ${getExe jq} --raw-output '.[0].outputs.out')

  echo $PATH/bin/zigfish-uci
''
