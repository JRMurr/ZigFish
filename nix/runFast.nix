{ writeShellScriptBin, buildAtCommit, lib, git, zig, fastchess }:
let
  getExe = lib.getExe;

  fastArgsMap = {
    maxmoves = "100";
    concurrency = "20";
    log = {
      file = "$OUT_DIR/log";
      level = "info";
      realtime = "true";
    };
    pgnout = { file = "$OUT_DIR/pgnout"; };
    resign = { score = "500000"; };
    rounds = "100";
    draw = { movenumber = "30"; movecount = "8"; score = "80"; };
    openings = { file = "./test.pgn"; format = "pgn"; order = "random"; };
    engine = [
      "cmd=./zig-out/bin/zigfish-uci name=new st=0.1 timemargin=100"
      ''cmd="$OLD_ENGINE" name=old st=0.1 timemargin=100''
    ];
  };

  # toplevel/root args for fastchess have a - infront and the name and space after for val
  toRootArgStr = name: val: "-${name} ${val}";
  # sub args are key=val format
  toSubArgStr = name: val: "${name}=${val}";

  fastArgsLst = lib.mapAttrsToList
    (name: val:
      if builtins.isList val then
        (lib.concatMapStringsSep " " (toRootArgStr name) val)
      else if builtins.isAttrs val then
        (
          let
            vals = lib.concatStringsSep " " (lib.mapAttrsToList toSubArgStr val);
          in
          toRootArgStr name vals
        )
      else if builtins.isString val then
        (toRootArgStr name val)
      else
        throw "invalid value for ${name}"
    )
    fastArgsMap;

  fastArgs = lib.concatStringsSep " \\\n" fastArgsLst;

in
writeShellScriptBin "runFast" ''
  set -euxo pipefail
  DEFAULT_COMMIT="ef2e4c6f7b600bcf2722552ec4c00f7459345a95"
  COMMIT="''${1:-$DEFAULT_COMMIT}"

  REPO_ROOT=$(${getExe git} rev-parse --show-toplevel)
  cd $REPO_ROOT
  OUT_DIR=$(realpath ''${REPO_ROOT})/fastchess-out

  mkdir -p $OUT_DIR
  rm -f $OUT_DIR/log
  rm -f $OUT_DIR/pgnout

  ${zig}/bin/zig build -Doptimize=ReleaseSafe
  OLD_ENGINE=$(${getExe buildAtCommit} "$COMMIT")
  ${getExe fastchess} ${fastArgs}
''

