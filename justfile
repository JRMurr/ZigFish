default:
  just --list

# zig test is sad when you add other modules in build zig, need to manually specifiy
test-uci:
  zig test -ODebug --dep zigfish -Mroot=./src/uci/root.zig -ODebug -Mzigfish=./src/lib/root.zig

# run zon2nix to refresh zig deps in nix build
nix-gen:
  zon2nix > nix/zigfish/deps.nix

run-fast:
  nix run .#runFast

run:
  zig build run

run-wasm:
  nix build .#emscripten && zig build run -Dtarget=wasm32-emscripten -Dcpu=bleeding_edge --sysroot ./result/share/emscripten


build-wasm:
  nix build .#emscripten && zig build install -Dtarget=wasm32-emscripten -Dcpu=bleeding_edge --sysroot ./result/share/emscripten