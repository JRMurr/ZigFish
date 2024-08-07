{ writeShellScriptBin
, buildAtCommit
, lib
, git
, zig
, fastchess
, captureStdErr
, books
,
}:
let
  getExe = lib.getExe;


  bookPath = name: "${books.${name}}/${name}";

  pgnOutFile = "$OUT_DIR/pgnout.pgn";
  logFile = "$OUT_DIR/log.txt";
  # https://github.com/Disservin/fast-chess/blob/master/man
  fastArgsMap = {
    rounds = "1000";
    maxmoves = "100";
    concurrency = "20";
    recover = null;
    "use-affinity" = null;
    log = {
      file = logFile;
      level = "warn";
      realtime = "true";
    };
    pgnout = {
      file = pgnOutFile;
    };
    resign = {
      score = "500000";
    };
    draw = {
      movenumber = "30";
      movecount = "8";
      score = "80";
    };
    openings = {
      file = bookPath "popularpos_lichess.epd";
      format = "epd";
      order = "random";
    };
    engine = [
      ''cmd="$NEW_ENGINE" name=new st=0.1 timemargin=100''
      ''cmd="$OLD_ENGINE" name=old st=0.1 timemargin=100''
    ];
  };

  # toplevel/root args for fastchess have a - infront and the name and space after for val
  toRootArgStr = name: val: "-${name} ${val}";
  # sub args are key=val format
  toSubArgStr = name: val: "${name}=${val}";

  fastArgsLst = lib.mapAttrsToList
    (
      name: val:
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
          "-${name}"
    )
    fastArgsMap;

  fastArgs = lib.concatStringsSep " \\\n" fastArgsLst;

in
writeShellScriptBin "runFast" ''
  set -euxo pipefail
  DEFAULT_COMMIT="2f327523e2afa9cdc73c7d5186088c2e29d881db"
  COMMIT="''${1:-$DEFAULT_COMMIT}"

  REPO_ROOT=$(${getExe git} rev-parse --show-toplevel)
  cd $REPO_ROOT
  OUT_DIR=$(realpath ''${REPO_ROOT})/fastchess-out

  mkdir -p $OUT_DIR
  rm -f ${logFile}
  rm -f ${pgnOutFile}

  NEW_ENGINE=$(${getExe buildAtCommit} "curr")
  OLD_ENGINE=$(${getExe buildAtCommit} "$COMMIT")

  ${getExe fastchess} ${fastArgs}
''
