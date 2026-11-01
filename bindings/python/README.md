# madeitpx

<p align="center">
  <img src="https://raw.githubusercontent.com/TamKungZ/madeitpx/main/assets/logo-wordmark.png" alt="madeitpx" width="240">
</p>

Python binding for [madeitpx](https://github.com/TamKungZ/madeitpx). Converts
RGBA8 pixel buffers to an output grid with a limited color palette.

<p align="center">
  <img src="https://raw.githubusercontent.com/TamKungZ/madeitpx/main/test_sources/output/preview.png" alt="madeitpx conversion examples" width="720">
</p>

```sh
python -m pip install madeitpx
```

The release wheel includes native libraries for Windows, Linux (glibc), and
macOS on x64 and ARM64. The matching library is loaded automatically.

```python
from madeitpx import ConversionOptions, convert_rgba8

pixels = bytes((
    255, 0, 0, 255,
    0, 255, 0, 255,
    0, 0, 255, 255,
    255, 255, 255, 255,
))
result = convert_rgba8(
    pixels,
    input_width=2,
    input_height=2,
    target_width=1,
    target_height=1,
    options=ConversionOptions(palette_colors=4),
)
```

Inputs may be `bytes`, `bytearray`, or `memoryview`. Set `input_stride` for
padded source rows. Conversion options include `preset`, `palette_colors`,
`background_rgb`, `sampling`, and `cluster_cleanup`.
Use `Preset.PIXELART` for outline-preserving conversion and structure cleanup.
It uses 16 palette colors by default and ignores the sampling option. See the
[pixelart preset documentation](../../docs/PIXELART.md) for details.

Python 3.9 or newer is required. Linux native libraries target glibc; musl
Linux is not currently supported. For local builds, set
`MADEITPX_LIBRARY_PATH` or pass `library_path` to `convert_rgba8`.

The release workflow publishes to PyPI using GitHub's trusted publishing.
Publishing requires a PyPI trusted publisher configured for this repository,
the `release.yml` workflow, and the `pypi` environment.

## Pixelart preset

`Preset.PIXELART` uses version 2 of the pixel-art pipeline. Settings you leave as `None` keep the
library default; `pixelart_defaults()` returns all of them.

```python
from madeitpx import ConversionOptions, PixelArtMode, PixelArtSettings, Preset, convert_rgba8

options = ConversionOptions(
    preset=Preset.PIXELART,
    pixelart=PixelArtSettings(mode=PixelArtMode.ILLUSTRATION, palette_max=32),
)
```

`PixelArtSettings(version=1)` runs the original pipeline. With `keep_transparency` (default) cells
that were transparent in the source are returned with alpha 0. See
[the pixelart documentation](../../docs/PIXELART.md).
