{ writeShellScriptBin, jq, nix, lib, git }:
let
  getExe = lib.getExe;
in
writeShellScriptBin "buildAtCommit" ''
  set -euo pipefail

  FLAKREF="github:JRMurr/ZigFish?rev=$1"
  if [[ "$1" == "curr" ]]; then
    REPO_ROOT=$(${getExe git} rev-parse --show-toplevel)
    FLAKREF="$REPO_ROOT"/.
  fi

  PATH=$(${getExe nix} build --no-link $FLAKREF --json | ${getExe jq} --raw-output '.[0].outputs.out')

  echo $PATH/bin/zigfish-uci
''
