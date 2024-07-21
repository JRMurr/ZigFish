{ stdenv, fetchFromGitHub }:


stdenv.mkDerivation rec {
  pname = "fast-chess";
  version = "v0.9.0";

  src = fetchFromGitHub {
    owner = "Disservin";
    repo = "fast-chess";
    rev = "09858ce817b471408ee9439fa502c9ce4a63dd43";
    sha256 = "sha256-RUHVwutazOiIw6lX7iWGKANWJIaivlzmoxVuj9LQPUc=";
  };


  enableParallelBuilding = true;

  installPhase = ''
    ls -la
    mkdir -p $out/bin

    cp fast-chess $out/bin
  '';

}
