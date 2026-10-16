using System;
using System.Runtime.InteropServices;

namespace MadeIt.PixelArt
{
    public enum ConversionPreset : uint
    {
        Balanced = 0,
        Detail = 1,
        Bold = 2
    }

    public enum SamplingMode : uint
    {
        Area = 0,
        Nearest = 1
    }

    public enum NativeStatus
    {
        Ok = 0,
        InvalidArgument = 1,
        BufferTooSmall = 2,
        SizeOverflow = 3,
        OutOfMemory = 4
    }

    public sealed class ConversionOptions
    {
        public ConversionPreset Preset { get; set; } = ConversionPreset.Balanced;
        public uint PaletteColors { get; set; }
        public uint BackgroundRgb { get; set; }
        public SamplingMode SamplingMode { get; set; } = SamplingMode.Nearest;
        public bool ClusterCleanup { get; set; } = true;
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
