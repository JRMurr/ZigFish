{ writeShellScriptBin, buildAtCommit, lib, git, zig, fastchess }:
let
  getExe = lib.getExe;

  pgnOutFile = "$OUT_DIR/pgnout.pgn";
  logFile = "$OUT_DIR/log.txt";

  fastArgsMap = {
    maxmoves = "100";
    concurrency = "12";
    log = {
      file = logFile;
      level = "trace";
      realtime = "false";
    };
    pgnout = { file = pgnOutFile; };
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
  DEFAULT_COMMIT="1711077a1e2a5923d2e358d75cd420fc583055c8"
  COMMIT="''${1:-$DEFAULT_COMMIT}"

  REPO_ROOT=$(${getExe git} rev-parse --show-toplevel)
  cd $REPO_ROOT
  OUT_DIR=$(realpath ''${REPO_ROOT})/fastchess-out

  mkdir -p $OUT_DIR
  rm -f ${logFile}
  rm -f ${pgnOutFile}

  ${zig}/bin/zig build -Doptimize=ReleaseSafe
  OLD_ENGINE=$(${getExe buildAtCommit} "$COMMIT")
  ${getExe fastchess} ${fastArgs}
''

