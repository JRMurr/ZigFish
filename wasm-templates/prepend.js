// https://github.com/emscripten-core/emscripten/issues/19996
if (!global.window) {
  global.window = {
    encodeURIComponent: encodeURIComponent,
    location: location,
  };
}
