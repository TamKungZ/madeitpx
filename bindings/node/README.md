# @madeit/pixelart

<p align="center">
  <img src="https://raw.githubusercontent.com/TamKungZ/madeitpx/main/assets/logo-wordmark.png" alt="madeitpx" width="240">
</p>

Node.js binding for [madeitpx](https://github.com/TamKungZ/madeitpx). Converts
RGBA8 pixel buffers to an output grid with a limited color palette.

<p align="center">
  <img src="https://raw.githubusercontent.com/TamKungZ/madeitpx/main/test_sources/output/preview.png" alt="madeitpx conversion examples" width="720">
</p>

```sh
npm install @madeit/pixelart
```

The package installs a native library for supported platforms: Windows x64 and
ARM64, Linux x64 and ARM64 (glibc), and macOS x64 and ARM64. The matching
platform package is an optional dependency and is selected automatically.
For local builds or custom locations, pass `libraryPath` when creating a
converter or set `MADEITPX_LIBRARY_PATH`.

```js
const { createConverter } = require('@madeit/pixelart');

const convert = createConverter();

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
