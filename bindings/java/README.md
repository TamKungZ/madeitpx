# madeitpx

<p align="center">
  <img src="https://raw.githubusercontent.com/TamKungZ/madeitpx/main/assets/logo.png" alt="madeitpx" width="120">
</p>

Java binding for [madeitpx](https://github.com/TamKungZ/madeitpx).

<p align="center">
  <img src="https://raw.githubusercontent.com/TamKungZ/madeitpx/main/test_sources/output/preview.png" alt="madeitpx conversion examples" width="720">
</p>

```xml
<dependency>
  <groupId>me.tamkungz</groupId>
  <artifactId>madeitpx</artifactId>
  <version>0.2.1</version>
</dependency>
```

```java
import me.tamkungz.madeitpx.MadeItPx;

byte[] output = MadeItPx.convert(rgba, 2, 2, 1, 1);
```

The input and output are tightly packed RGBA8 byte arrays. The overload with
`inputStride` supports padded input rows; conversion settings are provided with
`MadeItPx.Options`.
Select `MadeItPx.Preset.PIXELART` to preserve outlines and clean up small
regions; it uses 16 palette colors by default and ignores sampling. See the
[pixelart preset documentation](../../docs/PIXELART.md) for details.

Release JARs include native libraries for supported Windows, Linux (glibc), and
macOS x64 and ARM64 platforms. The binding extracts the matching library when
first used. For local builds or a custom library, set the
`madeitpx.library.path` system property or `MADEITPX_LIBRARY_PATH` environment
variable to its path. A JAR built from source does not include native binaries
unless they are staged under `src/main/resources/native` before packaging.

The release workflow publishes the artifact to Maven Central and attaches the
JAR to GitHub Releases.

## Pixelart preset

`Preset.PIXELART` uses version 2 of the pixel-art pipeline. Settings you do not set keep the library
default, and `MadeItPx.pixelartDefaults()` returns all of them.

```java
MadeItPx.Options options = new MadeItPx.Options(
        MadeItPx.Preset.PIXELART, 0, 0, MadeItPx.Sampling.NEAREST, true,
        new MadeItPx.PixelArtSettings().mode(MadeItPx.PixelArtMode.ILLUSTRATION).paletteMax(32));
```

`version(1)` runs the original pipeline. With `keepTransparency` (default) cells that were
transparent in the source are returned with alpha 0. See
[the pixelart documentation](https://github.com/TamKungZ/madeitpx/blob/main/docs/PIXELART.md).
