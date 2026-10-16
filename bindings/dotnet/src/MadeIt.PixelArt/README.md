# MadeIt.PixelArt

<img src="logo.png" alt="MadeIt.PixelArt" width="180">

A .NET wrapper for [madeitpx](https://github.com/TamKungZ/madeitpx), a native
library that converts RGBA8 pixel buffers to a smaller color palette and output
grid.

<img src="preview.png" alt="madeitpx conversion examples" width="720">

## Install

```shell
dotnet add package MadeIt.PixelArt
```

The NuGet package contains the managed wrapper only. The native `madeitpx`
shared library is required at runtime and must match the operating system and
process architecture. Make it available to the native library loader before
calling the converter.

## Convert an image buffer

Pass decoded RGBA8 pixels, their dimensions and row stride, and the desired
output dimensions:

```csharp
using MadeIt.PixelArt;

byte[] rgba = GetRgbaPixels();
byte[] result = PixelArtConverter.Convert(
    rgba,
    inputWidth: 256,
    inputHeight: 256,
    inputStride: 256 * 4,
    targetWidth: 64,
    targetHeight: 64);
```

`result` is tightly packed RGBA8 with opaque pixels. The wrapper does not
decode or encode image files.

Pass `ConversionOptions` to set a preset or palette size, choose area or nearest
sampling, set the compositing background (`0xRRGGBB`), or disable cluster
cleanup. Defaults are balanced palette, nearest sampling, black background,
and cleanup enabled.

## Target frameworks

`net462`, `netstandard2.0`, `netstandard2.1`, and `net10.0`.

Licensed under [MPL-2.0](https://mozilla.org/MPL/2.0/).
