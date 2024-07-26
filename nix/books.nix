{ fetchFromGitHub, runCommandNoCCLocal, unzip, lib, symlinkJoin }:
let
  getExe = lib.getExe;


  bookRepo = fetchFromGitHub {
    owner = "official-stockfish";
    repo = "books";
    rev = "471124f17c1b7c11175bea1035ae9d6ebd9451de";
    hash = "sha256-iYkPdJX7FjlG8SzGANCw4yUpmDiMi/xqdytX78aT0TE=";
  };

  getBook = name: runCommandNoCCLocal "extract-${name}" { } ''
    mkdir -p $out
    ${getExe unzip} ${bookRepo}/${name}.zip -d $out
  '';

  bookNames = [
    "closedpos.epd"
    "popularpos_lichess.epd"
  ];

  books = lib.attrsets.genAttrs bookNames getBook;

in
books // {
  all = symlinkJoin {
    name = "allBooks";
    paths = builtins.attrValues books;
  };
}
