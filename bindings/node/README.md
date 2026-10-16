# @madeit/pixelart

Node.js binding for [madeitpx](https://github.com/TamKungZ/madeitpx). Converts
RGBA8 pixel buffers to an output grid with a limited color palette.

```sh
npm install @madeit/pixelart
```

The package contains the JavaScript wrapper, not the native library. Build
`madeitpx` for the current operating system and architecture, and make the
shared library available to the system loader. Alternatively, pass its path
when creating a converter or set `MADEITPX_LIBRARY_PATH`.

```js
const { createConverter } = require('@madeit/pixelart');

const convert = createConverter({
  libraryPath: 'path/to/libmadeitpx.so'
});

const rgba = Buffer.from([
  255, 0, 0, 255,
  0, 255, 0, 255,
  0, 0, 255, 255,
  255, 255, 255, 255
]);
const result = convert(rgba, {
  inputWidth: 2,
  inputHeight: 2,
  targetWidth: 1,
  targetHeight: 1
});
```

The result is a `Buffer` containing tightly packed, opaque RGBA8 pixels. Input
rows may include padding by setting `inputStride`. Conversion options include
`preset`, `paletteColors`, `backgroundRgb`, `sampling`, and `clusterCleanup`.
The defaults are balanced palette, nearest sampling, black background, and
cluster cleanup enabled.

Node.js 18 or newer is required.
