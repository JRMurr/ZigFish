{ writeShellScriptBin, zigfish, lib, git }:
let
  getExe = lib.getExe;
in
writeShellScriptBin "captrueStderr" ''
  set -euo pipefail

  REPO_ROOT=$(${getExe git} rev-parse --show-toplevel)
  cd $REPO_ROOT
  OUT_DIR=$(realpath ''${REPO_ROOT})/fastchess-out

  OUT_FILE=$OUT_DIR/err_log.txt

  ${zigfish}/bin/zigfish-uci 2> >(tee --append "$OUT_FILE" >&2)
''
