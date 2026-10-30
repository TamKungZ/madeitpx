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
madeitpx = "0.1.2"
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
