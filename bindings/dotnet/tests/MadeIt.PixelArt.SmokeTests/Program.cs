using System;
using MadeIt.PixelArt;

byte[] input =
{
    255, 0, 0, 255,
    0, 255, 0, 255,
    0, 0, 255, 255,
    255, 255, 255, 255
};

byte[] output = PixelArtConverter.Convert(input, 2, 2, 8, 2, 2, new ConversionOptions
{
    PaletteColors = 4,
    ClusterCleanup = false
});
Assert(output.Length == 16, "Output has the expected RGBA8 length.");
for (int index = 3; index < output.Length; index += 4)
    Assert(output[index] == 255, "Output pixels are opaque.");

byte[] paddedInput =
{
    255, 0, 0, 255, 0, 255, 0, 255, 9, 9, 9, 9,
    0, 0, 255, 255, 255, 255, 255, 255, 9, 9, 9, 9
};
byte[] paddedOutput = PixelArtConverter.Convert(
    paddedInput,
    2,
    2,
    12,
    2,
    2,
    new ConversionOptions { PaletteColors = 4, ClusterCleanup = false });
Assert(paddedOutput.Length == 16, "Padded input rows are accepted.");

byte[] transparent = PixelArtConverter.Convert(
    new byte[] { 255, 0, 255, 0 },
    1,
    1,
    4,
    1,
    1,
    new ConversionOptions { BackgroundRgb = 0x123456 });
Assert(transparent[0] == 0x12 && transparent[1] == 0x34 && transparent[2] == 0x56,
    "Transparent input is composited onto the configured background.");
Assert(transparent[3] == 255, "Composited output is opaque.");

byte[] pixelart = PixelArtConverter.Convert(
    new byte[] { 90, 120, 150, 255 },
    1,
    1,
    4,
    1,
    1,
    new ConversionOptions { Preset = ConversionPreset.Pixelart, PaletteColors = 2 });
Assert(pixelart.Length == 4 && pixelart[0] == 90 && pixelart[1] == 120 &&
    pixelart[2] == 150 && pixelart[3] == 255, "Pixelart preset conversion succeeds.");

PixelArtSettings defaults = PixelArtConverter.GetPixelArtDefaults();
Assert(defaults.Version == 2 && defaults.Mode == PixelArtMode.Auto && defaults.KeepTransparency == true,
    "Pixelart defaults come from the native library.");
byte[] versionOne = PixelArtConverter.Convert(
    new byte[] { 90, 120, 150, 255 },
    1,
    1,
    4,
    1,
    1,
    new ConversionOptions
    {
        Preset = ConversionPreset.Pixelart,
        PixelArt = new PixelArtSettings { Version = 1 }
    });
Assert(versionOne[0] == 90 && versionOne[3] == 255, "Pixelart version 1 can be selected.");
Expect<PixelArtException>(
    () => PixelArtConverter.Convert(
        new byte[] { 90, 120, 150, 255 },
        1,
        1,
        4,
        1,
        1,
        new ConversionOptions
        {
            Preset = ConversionPreset.Pixelart,
            PixelArt = new PixelArtSettings { PaletteMax = 1 }
        }),
    "Invalid pixelart settings are rejected by the native library.");

Expect<ArgumentException>(
    () => PixelArtConverter.Convert(new byte[3], 1, 1, 4, 1, 1),
    "Undersized input is rejected.");
Expect<ArgumentOutOfRangeException>(
    () => PixelArtConverter.Convert(new byte[4], 1, 1, 4, 1, 1, new ConversionOptions { PaletteColors = 1 }),
    "Invalid palette sizes are rejected.");

Console.WriteLine("MadeIt.PixelArt smoke tests passed.");

static void Assert(bool condition, string message)
{
    if (!condition)
        throw new InvalidOperationException(message);
}

static void Expect<TException>(Action action, string message)
    where TException : Exception
{
    try
    {
        action();
    }
    catch (TException)
    {
        return;
    }

    throw new InvalidOperationException(message);
}
