default:
  just --list

# zig test is sad when you add other modules in build zig, need to manually specifiy
test-uci:
  zig test -ODebug --dep zigfish -Mroot=./src/uci/root.zig -ODebug -Mzigfish=./src/lib/root.zig