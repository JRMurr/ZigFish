{ stdenvNoCC, callPackage, zig, lib }:
let
  rootDir = ../../.;
  fs = lib.fileset;
  fileHasAnySuffix = fileSuffixes: file: (lib.lists.any (s: lib.hasSuffix s file.name) fileSuffixes);
  zigFiles = fs.fileFilter (fileHasAnySuffix [ ".zig" ".zon" ]) rootDir;
  resources = ../../resources;

  neededFiles = fs.unions [ zigFiles resources ];


in


stdenvNoCC.mkDerivation {
  name = "zigfish";
  version = "main";
  src = fs.toSource {
    root = rootDir;
    fileset = neededFiles;
  };
  nativeBuildInputs = [ zig ];
  # dontConfigure = true;
  dontInstall = true;
  # doCheck = true;

  # postPatch = ''
  #   ln -s ${callPackage ./deps.nix { }} $ZIG_GLOBAL_CACHE_DIR/p
  # '';

  # langref = langref;
  buildPhase =
    let
      buildArgs = [
        "--cache-dir $(pwd)/.zig-cache"
        "--global-cache-dir $(pwd)/.cache"
        "-Doptimize=ReleaseSafe"
        #"-Doptimize=Debug" 
        # "-Ddynamic-linker=$(cat $NIX_BINTOOLS/nix-support/dynamic-linker)"
        "--prefix $out"
      ];
    in
    ''
      mkdir -p .cache
      ls -la
      ln -s ${callPackage ./deps.nix { }} .cache/p
      zig build install ${builtins.concatStringsSep " " buildArgs}
    '';
  # checkPhase = ''
  #   zig build test --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache -Dversion_data_path=$langref -Dcpu=baseline
  # '';
}
