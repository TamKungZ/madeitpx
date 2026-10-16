# MadeIt.PixelArt

`MadeIt.PixelArt` is a .NET binding for the native `madeitpx` library. It
accepts RGBA8 byte arrays and returns opaque RGBA8 output.

The package targets .NET Framework 4.6.2, .NET Standard 2.0, .NET Standard 2.1,
and .NET 10.0.

The package contains the managed binding, not native binaries. Provide a
`madeitpx` shared library built for the current operating system and process
architecture, and make it available through the platform's native library
search path.

## Example

```csharp
using MadeIt.PixelArt;

byte[] rgba = { 255, 0, 0, 255 };
byte[] pixelArt = PixelArtConverter.Convert(
    rgba,
    inputWidth: 1,
    inputHeight: 1,
    inputStride: 4,
    targetWidth: 1,
    targetHeight: 1);
```

`ConversionOptions` can select a preset or palette size, sampling mode,
background color, and cluster cleanup behavior. Input and output are tightly
described RGBA8 byte arrays, while `inputStride` may include row padding.
