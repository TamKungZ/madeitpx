using System;
using System.Runtime.InteropServices;

namespace MadeIt.PixelArt
{
    public enum ConversionPreset : uint
    {
        Balanced = 0,
        Detail = 1,
        Bold = 2,
        Pixelart = 3
    }

    public enum SamplingMode : uint
    {
        Area = 0,
        Nearest = 1
    }

    public enum PixelArtMode : uint
    {
        Auto = 0,
        Grid = 1,
        Illustration = 2
    }

    public enum NativeStatus
    {
        Ok = 0,
        InvalidArgument = 1,
        BufferTooSmall = 2,
        SizeOverflow = 3,
        OutOfMemory = 4
    }

    public sealed class PixelArtSettings
    {
        public uint? Version { get; set; }
        public PixelArtMode? Mode { get; set; }
        public bool? GridFit { get; set; }
        public uint? GridSearchPermille { get; set; }
        public uint? SampleInsetPercent { get; set; }
        public uint? ColorTolerance { get; set; }
        public uint? PaletteMax { get; set; }
        public uint? RefineIterations { get; set; }
        public uint? InkPercent { get; set; }
        public uint? MinRegion { get; set; }
        public uint? AlphaThreshold { get; set; }
        public bool? KeepTransparency { get; set; }
    }

    public sealed class ConversionOptions
    {
        public ConversionPreset Preset { get; set; } = ConversionPreset.Balanced;
        public uint PaletteColors { get; set; }
        public uint BackgroundRgb { get; set; }
        public SamplingMode SamplingMode { get; set; } = SamplingMode.Nearest;
        public bool ClusterCleanup { get; set; } = true;
        public PixelArtSettings PixelArt { get; set; } = new PixelArtSettings();
    }

    public sealed class PixelArtException : Exception
    {
        public PixelArtException(NativeStatus status)
            : base("madeitpx conversion failed with status " + status + ".")
        {
            Status = status;
        }

        public NativeStatus Status { get; }
    }

    public static class PixelArtConverter
    {
        private const string LibraryName = "madeitpx";

        public static PixelArtSettings GetPixelArtDefaults()
        {
            ThrowIfFailed(NativePixelArtInit(out NativePixelArtOptions native));
            return new PixelArtSettings
            {
                Version = native.Version,
                Mode = (PixelArtMode)native.Mode,
                GridFit = native.GridFit == 1,
                GridSearchPermille = native.GridSearchPermille,
                SampleInsetPercent = native.SampleInsetPercent,
                ColorTolerance = native.ColorTolerance,
                PaletteMax = native.PaletteMax,
                RefineIterations = native.RefineIterations,
                InkPercent = native.InkPercent,
                MinRegion = native.MinRegion,
                AlphaThreshold = native.AlphaThreshold,
                KeepTransparency = native.KeepTransparency == 1
            };
        }

        public static byte[] Convert(
            byte[] input,
            int inputWidth,
            int inputHeight,
            int inputStride,
            int targetWidth,
            int targetHeight,
            ConversionOptions? options = null)
        {
            if (input == null)
                throw new ArgumentNullException(nameof(input));
            ValidateDimension(inputWidth, nameof(inputWidth));
            ValidateDimension(inputHeight, nameof(inputHeight));
            ValidateDimension(inputStride, nameof(inputStride));
            ValidateDimension(targetWidth, nameof(targetWidth));
            ValidateDimension(targetHeight, nameof(targetHeight));

            long minimumStride = (long)inputWidth * 4;
            if (inputStride < minimumStride)
                throw new ArgumentOutOfRangeException(nameof(inputStride));

            long requiredInputLength = (long)(inputHeight - 1) * inputStride + minimumStride;
            if (requiredInputLength > input.Length)
                throw new ArgumentException("The input buffer is too small for its dimensions and stride.", nameof(input));

            ConversionOptions settings = options ?? new ConversionOptions();
            ValidateOptions(settings);

            int initStatus = NativeOptionsInit(out NativeOptions nativeOptions);
            ThrowIfFailed(initStatus);
            nativeOptions.Preset = (uint)settings.Preset;
            nativeOptions.PaletteColors = settings.PaletteColors;
            nativeOptions.BackgroundRgb = settings.BackgroundRgb;
            nativeOptions.SampleMode = (uint)settings.SamplingMode;
            nativeOptions.ClusterCleanup = settings.ClusterCleanup ? 1u : 0u;

            int sizeStatus = NativeGetOutputSize(
                (uint)targetWidth,
                (uint)targetHeight,
                out UIntPtr nativeOutputSize);
            ThrowIfFailed(sizeStatus);
            ulong outputSize = nativeOutputSize.ToUInt64();
            if (outputSize > int.MaxValue)
                throw new ArgumentOutOfRangeException(nameof(targetWidth), "The output is too large for a managed byte array.");

            byte[] output = new byte[(int)outputSize];
            if (settings.Preset == ConversionPreset.Pixelart)
            {
                ThrowIfFailed(NativePixelArtInit(out NativePixelArtOptions nativePixelArt));
                ApplyPixelArt(settings.PixelArt ?? new PixelArtSettings(), ref nativePixelArt);
                int pixelArtStatus = NativeConvertPixelArt(
                    input,
                    new UIntPtr((uint)input.Length),
                    (uint)inputWidth,
                    (uint)inputHeight,
                    new UIntPtr((uint)inputStride),
                    (uint)targetWidth,
                    (uint)targetHeight,
                    ref nativeOptions,
                    ref nativePixelArt,
                    output,
                    new UIntPtr((uint)output.Length));
                ThrowIfFailed(pixelArtStatus);
                return output;
            }

            int conversionStatus = NativeConvert(
                input,
                new UIntPtr((uint)input.Length),
                (uint)inputWidth,
                (uint)inputHeight,
                new UIntPtr((uint)inputStride),
                (uint)targetWidth,
                (uint)targetHeight,
                ref nativeOptions,
                output,
                new UIntPtr((uint)output.Length));
            ThrowIfFailed(conversionStatus);
            return output;
        }

        private static void ApplyPixelArt(PixelArtSettings settings, ref NativePixelArtOptions native)
        {
            if (settings.Mode.HasValue && !Enum.IsDefined(typeof(PixelArtMode), settings.Mode.Value))
                throw new ArgumentOutOfRangeException(nameof(settings.Mode));
            if (settings.Version.HasValue) native.Version = settings.Version.Value;
            if (settings.Mode.HasValue) native.Mode = (uint)settings.Mode.Value;
            if (settings.GridFit.HasValue) native.GridFit = settings.GridFit.Value ? 1u : 0u;
            if (settings.GridSearchPermille.HasValue) native.GridSearchPermille = settings.GridSearchPermille.Value;
            if (settings.SampleInsetPercent.HasValue) native.SampleInsetPercent = settings.SampleInsetPercent.Value;
            if (settings.ColorTolerance.HasValue) native.ColorTolerance = settings.ColorTolerance.Value;
            if (settings.PaletteMax.HasValue) native.PaletteMax = settings.PaletteMax.Value;
            if (settings.RefineIterations.HasValue) native.RefineIterations = settings.RefineIterations.Value;
            if (settings.InkPercent.HasValue) native.InkPercent = settings.InkPercent.Value;
            if (settings.MinRegion.HasValue) native.MinRegion = settings.MinRegion.Value;
            if (settings.AlphaThreshold.HasValue) native.AlphaThreshold = settings.AlphaThreshold.Value;
            if (settings.KeepTransparency.HasValue) native.KeepTransparency = settings.KeepTransparency.Value ? 1u : 0u;
        }

        private static void ValidateDimension(int value, string parameterName)
        {
            if (value <= 0)
                throw new ArgumentOutOfRangeException(parameterName, "Dimensions and stride must be positive.");
        }

        private static void ValidateOptions(ConversionOptions options)
        {
            if (!Enum.IsDefined(typeof(ConversionPreset), options.Preset))
                throw new ArgumentOutOfRangeException(nameof(options.Preset));
            if (!Enum.IsDefined(typeof(SamplingMode), options.SamplingMode))
                throw new ArgumentOutOfRangeException(nameof(options.SamplingMode));
            if (options.PaletteColors != 0 && (options.PaletteColors < 2 || options.PaletteColors > 64))
                throw new ArgumentOutOfRangeException(nameof(options.PaletteColors));
            if (options.BackgroundRgb > 0xFFFFFF)
                throw new ArgumentOutOfRangeException(nameof(options.BackgroundRgb));
        }

        private static void ThrowIfFailed(int status)
        {
            if (status != (int)NativeStatus.Ok)
                throw new PixelArtException((NativeStatus)status);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeOptions
        {
            public uint StructSize;
            public uint Preset;
            public uint PaletteColors;
            public uint BackgroundRgb;
            public uint SampleMode;
            public uint ClusterCleanup;
            public uint Reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativePixelArtOptions
        {
            public uint StructSize;
            public uint Version;
            public uint GridFit;
            public uint GridSearchPermille;
            public uint SampleInsetPercent;
            public uint ColorTolerance;
            public uint PaletteMax;
            public uint RefineIterations;
            public uint Mode;
            public uint InkPercent;
            public uint MinRegion;
            public uint AlphaThreshold;
            public uint KeepTransparency;
            public uint Reserved;
        }

        [DllImport(LibraryName, EntryPoint = "madeitpx_pixelart_options_init", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NativePixelArtInit(out NativePixelArtOptions options);

        [DllImport(LibraryName, EntryPoint = "madeitpx_convert_pixelart_rgba8", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NativeConvertPixelArt(
            [In] byte[] input,
            UIntPtr inputSize,
            uint inputWidth,
            uint inputHeight,
            UIntPtr inputStride,
            uint targetWidth,
            uint targetHeight,
            ref NativeOptions options,
            ref NativePixelArtOptions pixelArt,
            [Out] byte[] output,
            UIntPtr outputCapacity);

        [DllImport(LibraryName, EntryPoint = "madeitpx_options_init", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NativeOptionsInit(out NativeOptions options);

        [DllImport(LibraryName, EntryPoint = "madeitpx_get_output_size", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NativeGetOutputSize(uint targetWidth, uint targetHeight, out UIntPtr outputSize);

        [DllImport(LibraryName, EntryPoint = "madeitpx_convert_rgba8", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NativeConvert(
            [In] byte[] input,
            UIntPtr inputSize,
            uint inputWidth,
            uint inputHeight,
            UIntPtr inputStride,
            uint targetWidth,
            uint targetHeight,
            ref NativeOptions options,
            [Out] byte[] output,
            UIntPtr outputCapacity);
    }
}
