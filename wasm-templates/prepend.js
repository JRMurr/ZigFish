// https://github.com/emscripten-core/emscripten/issues/19996
if (!global.window) {
  global.window = {
    encodeURIComponent: encodeURIComponent,
    location: location,
  };
}
Module["force_exit"] = _emscripten_force_exit;
