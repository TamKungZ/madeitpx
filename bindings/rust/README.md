# madeitpx

<p align="center">
  <img src="https://raw.githubusercontent.com/TamKungZ/madeitpx/main/assets/logo-wordmark.png" alt="madeitpx" width="240">
</p>

Rust binding for [madeitpx](https://github.com/TamKungZ/madeitpx). Converts
RGBA8 pixel buffers to an output grid with a limited color palette.

<p align="center">
  <img src="https://raw.githubusercontent.com/TamKungZ/madeitpx/main/test_sources/output/preview.png" alt="madeitpx conversion examples" width="720">
</p>

```toml
[dependencies]
madeitpx = "0.2.1"
```

```rust
use madeitpx::{convert_rgba8, Options};

let rgba = [
    255, 0, 0, 255,
    0, 255, 0, 255,
    0, 0, 255, 255,
    255, 255, 255, 255,
];
let output = convert_rgba8(&rgba, 2, 2, None, 1, 1, Options::default())?;
# Ok::<(), madeitpx::MadeItPxError>(())
```

The published crate includes native libraries for Windows, Linux (glibc), and
macOS on x64 and ARM64. The matching library is loaded automatically. For local
builds, set `MADEITPX_LIBRARY_PATH` to a native library path.

`input_stride` is specified in bytes; pass `None` for tightly packed rows.
Options control the palette preset and size, sampling mode, background color,
and cluster cleanup.
Use `Preset::Pixelart` for outline-preserving conversion and structure cleanup.
It uses 16 palette colors by default and ignores the sampling mode. See the
[pixelart preset documentation](../../docs/PIXELART.md) for details.

## Pixelart preset

`Preset::Pixelart` uses version 2 of the pixel-art pipeline. Fields of `PixelArtSettings` left as
`None` keep the library default, and `pixelart_defaults()` returns all of them.

```rust
use madeitpx::{Options, PixelArtMode, PixelArtSettings, Preset};

let options = Options {
    preset: Preset::Pixelart,
    pixelart: PixelArtSettings {
        mode: Some(PixelArtMode::Illustration),
        palette_max: Some(32),
        ..PixelArtSettings::default()
    },
    ..Options::default()
};
```

`version: Some(1)` runs the original pipeline. With `keep_transparency` (default) cells that were
transparent in the source are returned with alpha 0. See
[the pixelart documentation](../../docs/PIXELART.md).
