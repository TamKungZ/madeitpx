# @madeitpx/pixelart

<p align="center">
  <img src="https://raw.githubusercontent.com/TamKungZ/madeitpx/main/assets/logo-wordmark.png" alt="madeitpx" width="240">
</p>

Node.js binding for [madeitpx](https://github.com/TamKungZ/madeitpx). Converts
RGBA8 pixel buffers to an output grid with a limited color palette.

<p align="center">
  <img src="https://raw.githubusercontent.com/TamKungZ/madeitpx/main/test_sources/output/preview.png" alt="madeitpx conversion examples" width="720">
</p>

```sh
npm install @madeitpx/pixelart
```

The package installs a native library for supported platforms: Windows x64 and
ARM64, Linux x64 and ARM64 (glibc), and macOS x64 and ARM64. The matching
platform package is an optional dependency and is selected automatically.
For local builds or custom locations, pass `libraryPath` when creating a
converter or set `MADEITPX_LIBRARY_PATH`.

```js
const { createConverter } = require('@madeitpx/pixelart');

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

The result is a `Buffer` containing tightly packed RGBA8 pixels, opaque except for the transparent
cells that the pixelart preset can keep (see below). Input rows may include padding by setting
`inputStride`. Conversion options include `preset`, `paletteColors`, `backgroundRgb`, `sampling`,
`clusterCleanup` and `pixelart`. The defaults are balanced palette, nearest sampling, black
background, and cluster cleanup enabled.

## Pixelart preset

`preset: 'pixelart'` uses version 2 of the pixel-art pipeline: it recovers the real grid of pixel
art that was scaled up, and reduces smooth artwork with preserved outlines. `pixelart` holds the
detailed settings; any setting you leave out keeps the library default.

```js
const out = convert(rgba, {
  inputWidth: 1024,
  inputHeight: 1536,
  targetWidth: 256,
  targetHeight: 384,
  preset: 'pixelart',
  pixelart: { mode: 'illustration', paletteMax: 32, minRegion: 4 }
});

const defaults = convert.pixelartDefaults();
const original = convert(rgba, { ...settings, preset: 'pixelart', pixelart: { version: 1 } });
```

`convert.pixelartDefaults()` returns every default, so a settings panel can reset a field by
reading it from there. `version: 1` runs the original pipeline. Settings: `version`, `mode`
(`auto`, `grid`, `illustration`), `gridFit`, `gridSearchPermille`, `sampleInsetPercent`,
`colorTolerance`, `paletteMax`, `refineIterations`, `inkPercent`, `minRegion`, `alphaThreshold`
and `keepTransparency`. With `keepTransparency` (default) cells that were transparent in the source
come back with alpha 0. See the [pixelart documentation](../../docs/PIXELART.md).

## Browsers and bundlers

The package also runs in the browser without a native library. Bundlers (Vite, webpack, Astro)
pick the WebAssembly entry through the `browser` export condition, and `createConverter` is
asynchronous there:

```js
import { createConverter } from '@madeitpx/pixelart';

const convert = await createConverter();
const image = ctx.getImageData(0, 0, width, height);
const out = convert(image.data, {
  inputWidth: width,
  inputHeight: height,
  targetWidth: 128,
  targetHeight: 128,
  preset: 'pixelart'
});
ctx2.putImageData(new ImageData(new Uint8ClampedArray(out), 128, 128), 0, 0);
```

The module is loaded from `wasm/madeitpx.wasm` next to the package. To host it yourself, pass
`createConverter({ wasm: url })` where `url` is a URL, `Response`, `ArrayBuffer` or
`WebAssembly.Module`; `@madeitpx/pixelart/madeitpx.wasm` resolves to the file for bundlers.

Node.js 18 or newer is required.
