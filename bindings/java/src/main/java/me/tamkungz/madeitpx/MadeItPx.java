package me.tamkungz.madeitpx;

import com.sun.jna.Library;
import com.sun.jna.Native;
import com.sun.jna.Structure;
import com.sun.jna.ptr.LongByReference;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

public final class MadeItPx {
    private static final String LIBRARY_PATH_PROPERTY = "madeitpx.library.path";
    private static final String LIBRARY_PATH_ENVIRONMENT = "MADEITPX_LIBRARY_PATH";

    private MadeItPx() {
    }

    public enum Preset {
        BALANCED,
        DETAIL,
        BOLD,
        PIXELART
    }

    public enum Sampling {
        AREA,
        NEAREST
    }

    public static final class Options {
        private final Preset preset;
        private final int paletteColors;
        private final int backgroundRgb;
        private final Sampling sampling;
        private final boolean clusterCleanup;

        public Options() {
            this(Preset.BALANCED, 0, 0, Sampling.NEAREST, true);
        }

        public Options(
                Preset preset,
                int paletteColors,
                int backgroundRgb,
                Sampling sampling,
                boolean clusterCleanup) {
            if (preset == null) {
                throw new NullPointerException("preset");
            }
            if (sampling == null) {
                throw new NullPointerException("sampling");
            }
            if (paletteColors != 0 && (paletteColors < 2 || paletteColors > 64)) {
                throw new IllegalArgumentException("paletteColors must be 0 or between 2 and 64");
            }
            if (backgroundRgb < 0 || backgroundRgb > 0xFFFFFF) {
                throw new IllegalArgumentException("backgroundRgb must be a 0xRRGGBB value");
            }
            this.preset = preset;
            this.paletteColors = paletteColors;
            this.backgroundRgb = backgroundRgb;
            this.sampling = sampling;
            this.clusterCleanup = clusterCleanup;
        }

        public Preset getPreset() {
            return preset;
        }

        public int getPaletteColors() {
            return paletteColors;
        }

        public int getBackgroundRgb() {
            return backgroundRgb;
        }

        public Sampling getSampling() {
            return sampling;
        }

        public boolean isClusterCleanup() {
            return clusterCleanup;
        }
    }

    public static final class ConversionException extends RuntimeException {
        private final int status;

        private ConversionException(int status) {
            super("madeitpx conversion failed with status " + status);
            this.status = status;
        }

        public int getStatus() {
            return status;
        }
    }

    public static byte[] convert(
            byte[] input,
            int inputWidth,
            int inputHeight,
            int targetWidth,
            int targetHeight) {
        return convert(input, inputWidth, inputHeight, defaultStride(inputWidth), targetWidth, targetHeight, new Options());
    }

    public static byte[] convert(
            byte[] input,
            int inputWidth,
            int inputHeight,
            int targetWidth,
            int targetHeight,
            Options options) {
        return convert(input, inputWidth, inputHeight, defaultStride(inputWidth), targetWidth, targetHeight, options);
    }

    public static byte[] convert(
            byte[] input,
            int inputWidth,
            int inputHeight,
            int inputStride,
            int targetWidth,
            int targetHeight,
            Options options) {
        if (input == null) {
            throw new NullPointerException("input");
        }
        validateDimension(inputWidth, "inputWidth");
        validateDimension(inputHeight, "inputHeight");
        validateDimension(inputStride, "inputStride");
        validateDimension(targetWidth, "targetWidth");
        validateDimension(targetHeight, "targetHeight");

        long minimumStride = (long) inputWidth * 4;
        if (inputStride < minimumStride) {
            throw new IllegalArgumentException("inputStride must be at least inputWidth * 4");
        }
        long requiredInputLength = (long) (inputHeight - 1) * inputStride + minimumStride;
        if (requiredInputLength > input.length) {
            throw new IllegalArgumentException("input does not contain enough bytes for its dimensions and stride");
        }
        long outputPixelCount = (long) targetWidth * targetHeight;
        if (outputPixelCount > Integer.MAX_VALUE / 4) {
            throw new IllegalArgumentException("output is too large for a Java byte array");
        }
        long requiredOutputLength = outputPixelCount * 4;

        Options settings = options == null ? new Options() : options;
        NativeApi library = NativeAccess.INSTANCE;
        NativeOptions nativeOptions = new NativeOptions();
        checkStatus(library.madeitpx_options_init(nativeOptions));
        nativeOptions.read();
        nativeOptions.preset = settings.preset.ordinal();
        nativeOptions.paletteColors = settings.paletteColors;
        nativeOptions.backgroundRgb = settings.backgroundRgb;
        nativeOptions.sampleMode = settings.sampling.ordinal();
        nativeOptions.clusterCleanup = settings.clusterCleanup ? 1 : 0;
        nativeOptions.write();

        LongByReference outputSize = new LongByReference();
        checkStatus(library.madeitpx_get_output_size(targetWidth, targetHeight, outputSize));
        if (outputSize.getValue() != requiredOutputLength) {
            throw new IllegalStateException("native library returned an unexpected output size");
        }

        byte[] output = new byte[(int) requiredOutputLength];
        checkStatus(library.madeitpx_convert_rgba8(
                input,
                input.length,
                inputWidth,
                inputHeight,
                inputStride,
                targetWidth,
                targetHeight,
                nativeOptions,
                output,
                output.length));
        return output;
    }

    private static void validateDimension(int value, String name) {
        if (value <= 0) {
            throw new IllegalArgumentException(name + " must be positive");
        }
    }

    private static int defaultStride(int inputWidth) {
        validateDimension(inputWidth, "inputWidth");
        long stride = (long) inputWidth * 4;
        if (stride > Integer.MAX_VALUE) {
            throw new IllegalArgumentException("input row is too large");
        }
        return (int) stride;
    }

    private static void checkStatus(int status) {
        if (status != 0) {
            throw new ConversionException(status);
        }
    }

    private static NativeApi loadNativeApi() {
        String libraryPath = System.getProperty(LIBRARY_PATH_PROPERTY);
        if (libraryPath == null || libraryPath.isEmpty()) {
            libraryPath = System.getenv(LIBRARY_PATH_ENVIRONMENT);
        }
        if (libraryPath != null && !libraryPath.isEmpty()) {
            return Native.load(libraryPath, NativeApi.class);
        }

        String resourceName = nativeResourceName();
        try (InputStream resource = MadeItPx.class.getResourceAsStream(resourceName)) {
            if (resource == null) {
                throw new IllegalStateException(
                        "No bundled madeitpx library for this platform; set " +
                                LIBRARY_PATH_PROPERTY + " or " + LIBRARY_PATH_ENVIRONMENT +
                                " to a native library path");
            }
            String extension = resourceName.substring(resourceName.lastIndexOf('.'));
            Path extractedLibrary = Files.createTempFile("madeitpx-", extension);
            Files.copy(resource, extractedLibrary, StandardCopyOption.REPLACE_EXISTING);
            return Native.load(extractedLibrary.toAbsolutePath().toString(), NativeApi.class);
        } catch (IOException exception) {
            throw new IllegalStateException("Unable to extract the bundled madeitpx library", exception);
        }
    }

    private static String nativeResourceName() {
        String os = System.getProperty("os.name", "").toLowerCase();
        String arch = System.getProperty("os.arch", "").toLowerCase();
        String platform;
        if (os.startsWith("windows")) {
            platform = "windows";
        } else if (os.startsWith("mac") || os.startsWith("darwin")) {
            platform = "darwin";
        } else if (os.startsWith("linux")) {
            platform = "linux";
        } else {
            throw new IllegalStateException("Unsupported operating system: " + os);
        }

        String architecture;
        if (arch.equals("amd64") || arch.equals("x86_64")) {
            architecture = "x64";
        } else if (arch.equals("aarch64") || arch.equals("arm64")) {
            architecture = "arm64";
        } else {
            throw new IllegalStateException("Unsupported architecture: " + arch);
        }

        String target = platform.equals("linux") ? platform + "-" + architecture + "-gnu" :
                platform + "-" + architecture;
        String libraryName = platform.equals("windows") ? "madeitpx.dll" :
                platform.equals("darwin") ? "libmadeitpx.dylib" : "libmadeitpx.so";
        return "/native/" + target + "/" + libraryName;
    }

    private interface NativeApi extends Library {
        int madeitpx_options_init(NativeOptions options);

        int madeitpx_get_output_size(int targetWidth, int targetHeight, LongByReference outputSize);

        int madeitpx_convert_rgba8(
                byte[] input,
                long inputSize,
                int inputWidth,
                int inputHeight,
                long inputStride,
                int targetWidth,
                int targetHeight,
                NativeOptions options,
                byte[] output,
                long outputCapacity);
    }

    @Structure.FieldOrder({
            "structSize",
            "preset",
            "paletteColors",
            "backgroundRgb",
            "sampleMode",
            "clusterCleanup",
            "reserved"
    })
    public static final class NativeOptions extends Structure implements Structure.ByReference {
        public int structSize;
        public int preset;
        public int paletteColors;
        public int backgroundRgb;
        public int sampleMode;
        public int clusterCleanup;
        public int reserved;
    }

    private static final class NativeAccess {
        private static final NativeApi INSTANCE = loadNativeApi();
    }
}
