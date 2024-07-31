{ stdenvNoCC, clangStdenv, callPackage, zig, lib, emscripten, python3 }:
let
  rootDir = ../../.;
  fs = lib.fileset;
  fileHasAnySuffix = fileSuffixes: file: (lib.lists.any (s: lib.hasSuffix s file.name) fileSuffixes);
  zigFiles = fs.fileFilter (fileHasAnySuffix [ ".zig" ".zon" ]) rootDir;
  resources = ../../resources;

  neededFiles = fs.unions [ zigFiles resources ];


  compileHelper = { stdenv ? stdenvNoCC, name, optimize ? "ReleaseSafe", postBuild ? "", extraBuildArgs ? [ ], extraNativeDeps ? [ ], postConfigurePhase ? "" }:
    stdenv.mkDerivation {
      inherit name;
      version = "main";
      src = fs.toSource {
        root = rootDir;
        fileset = neededFiles;
      };
      nativeBuildInputs = [ zig ] ++ extraNativeDeps;
      # dontConfigure = true;
      dontInstall = true;
      # doCheck = true;

      # postPatch = ''
      #   ln -s ${callPackage ./deps.nix { }} $ZIG_GLOBAL_CACHE_DIR/p
      # '';

      configurePhase = postConfigurePhase;


      # langref = langref;
      buildPhase =
        let
          buildArgs = [
            "--cache-dir $(pwd)/.zig-cache"
            "--global-cache-dir $(pwd)/.cache"
            "-Doptimize=${optimize}"
            #"-Doptimize=Debug" 
            # "-Ddynamic-linker=$(cat $NIX_BINTOOLS/nix-support/dynamic-linker)"
            "--prefix $out"
          ] ++ extraBuildArgs;
        in
        ''
          runHook preBuild
          HOME=$TMPDIR
          mkdir -p .cache
          ln -s ${callPackage ./deps.nix { }} .cache/p
          zig build install ${builtins.concatStringsSep " " buildArgs}
          runHook postBuild
        '';
      postBuild = postBuild;
      # checkPhase = ''
      #   zig build test --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache -Dversion_data_path=$langref -Dcpu=baseline
      # '';
    };

  uciBuild = compileHelper { name = "zigfish"; };

  wasmBuild = compileHelper {
    stdenv = clangStdenv;
    name = "zigfish-wasm";
    extraNativeDeps = [ emscripten python3 ];
    optimize = "Debug"; # not sure why...
    postConfigurePhase = ''
      mkdir -p ./tmp
      HOME=$TMPDIR
      runHook preConfigure
      cp -r ${emscripten}/share/emscripten ./tmp
      cp ${../../template.html} template.html

      mkdir -p .emscriptencache
      export EM_CACHE=$(pwd)/.emscriptencache
      runHook postConfigure
    '';
    extraBuildArgs = [
      "-Dtarget=wasm32-emscripten"
      "-Dcpu=bleeding_edge"
      "--sysroot ./tmp/emscripten"
    ];
    postBuild = ''
      cp -r ./zig-out/htmlout $out
      # cp zigfish.html $out
    '';

  };

in
{
  inherit uciBuild wasmBuild;
}
