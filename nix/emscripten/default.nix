{ pkgs }:

# TODO: going to slightly older version to work around
# https://github.com/emscripten-core/emscripten/issues/22249
# issue says 3.1.64 should fix it but still seems sad...
pkgs.emscripten.overrideAttrs (_: prev: {
  patches = (prev.patches or [ ]) ++ [ ./comment-out-arg.patch ];

  # version = "3.1.64";
  # src = pkgs.fetchFromGitHub {
  #   owner = "emscripten-core";
  #   repo = "emscripten";
  #   hash = "sha256-AbO1b4pxZ7I6n1dRzxhLC7DnXIUnaCK9SbLy96Qxqr0=";
  #   rev = version;
  # };
})
