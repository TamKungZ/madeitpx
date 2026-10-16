package me.tamkungz.madeitpx;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

class MadeItPxTest {
    @Test
    void rejectsInvalidDimensionsBeforeLoadingNativeLibrary() {
        assertThrows(IllegalArgumentException.class,
                () -> MadeItPx.convert(new byte[4], 0, 1, 1, 1));
    }

    @Test
    void rejectsShortInputBeforeLoadingNativeLibrary() {
        assertThrows(IllegalArgumentException.class,
                () -> MadeItPx.convert(new byte[3], 1, 1, 1, 1));
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "MADEITPX_LIBRARY_PATH", matches = ".+")
    void convertsTransparentPixelUsingConfiguredBackground() {
        MadeItPx.Options options = new MadeItPx.Options(
                MadeItPx.Preset.BALANCED,
                0,
                0x123456,
                MadeItPx.Sampling.NEAREST,
                true);
        byte[] result = MadeItPx.convert(new byte[] {1, 2, 3, 0}, 1, 1, 1, 1, options);
        assertArrayEquals(new byte[] {0x12, 0x34, 0x56, (byte) 0xFF}, result);
        assertEquals(4, result.length);
    }

    @Test
    void loadsBundledLibraryWhenAvailable() {
        String resource = currentNativeResource();
        assumeTrue(resource != null && MadeItPx.class.getResource(resource) != null);
        byte[] result = MadeItPx.convert(new byte[] {10, 20, 30, (byte) 255}, 1, 1, 1, 1);
        assertArrayEquals(new byte[] {10, 20, 30, (byte) 255}, result);
    }

    private static String currentNativeResource() {
        String os = System.getProperty("os.name", "").toLowerCase();
        String arch = System.getProperty("os.arch", "").toLowerCase();
        String platform = os.startsWith("windows") ? "windows" :
                os.startsWith("mac") || os.startsWith("darwin") ? "darwin" :
                        os.startsWith("linux") ? "linux" : null;
        String architecture = arch.equals("amd64") || arch.equals("x86_64") ? "x64" :
                arch.equals("aarch64") || arch.equals("arm64") ? "arm64" : null;
        if (platform == null || architecture == null) {
            return null;
        }
        String target = platform.equals("linux") ? platform + "-" + architecture + "-gnu" :
                platform + "-" + architecture;
        String libraryName = platform.equals("windows") ? "madeitpx.dll" :
                platform.equals("darwin") ? "libmadeitpx.dylib" : "libmadeitpx.so";
        return "/native/" + target + "/" + libraryName;
    }
}
