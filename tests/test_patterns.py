import ctypes
import struct
import sys
import unittest
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PATTERN_DIR = ROOT / "test_sources" / "test-patterns"
PRESET_LIMITS = {0: 32, 1: 64, 2: 16}
EXPECTED_PATTERN_COUNT = 23


class Options(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_uint32),
        ("preset", ctypes.c_uint32),
        ("palette_colors", ctypes.c_uint32),
        ("background_rgb", ctypes.c_uint32),
        ("sample_mode", ctypes.c_uint32),
        ("cluster_cleanup", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
    ]


def paeth(left, above, upper_left):
    estimate = left + above - upper_left
    distances = (
        abs(estimate - left),
        abs(estimate - above),
        abs(estimate - upper_left),
    )
    return (left, above, upper_left)[distances.index(min(distances))]


def read_png(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path.name}: invalid PNG signature")

    width = height = None
    compressed = bytearray()
    offset = 8
    while offset < len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4 : offset + 8]
        chunk = data[offset + 8 : offset + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color_type, compression, filtering, interlace = (
                struct.unpack(">IIBBBBB", chunk)
            )
            if (depth, color_type, compression, filtering, interlace) != (8, 6, 0, 0, 0):
                raise ValueError(f"{path.name}: unsupported PNG encoding")
        elif kind == b"IDAT":
            compressed.extend(chunk)
        elif kind == b"IEND":
            break
        offset += length + 12

    if width is None or height is None:
        raise ValueError(f"{path.name}: missing PNG header")

    decoded = zlib.decompress(compressed)
    stride = width * 4
    if len(decoded) != height * (stride + 1):
        raise ValueError(f"{path.name}: unexpected decoded image size")

    pixels = bytearray(height * stride)
    source_offset = 0
    for y in range(height):
        filter_type = decoded[source_offset]
        source_offset += 1
        row_offset = y * stride
        previous_offset = row_offset - stride
        for x in range(stride):
            value = decoded[source_offset + x]
            left = pixels[row_offset + x - 4] if x >= 4 else 0
            above = pixels[previous_offset + x] if y else 0
            upper_left = pixels[previous_offset + x - 4] if y and x >= 4 else 0
            if filter_type == 1:
                value += left
            elif filter_type == 2:
                value += above
            elif filter_type == 3:
                value += (left + above) // 2
            elif filter_type == 4:
                value += paeth(left, above, upper_left)
            elif filter_type != 0:
                raise ValueError(f"{path.name}: unsupported PNG filter {filter_type}")
            pixels[row_offset + x] = value & 255
        source_offset += stride

    return width, height, pixels


def load_library():
    names = {
        "win32": "madeitpx.dll",
        "darwin": "libmadeitpx.dylib",
    }
    filename = names.get(sys.platform, "libmadeitpx.so")
    library_dir = "bin" if sys.platform == "win32" else "lib"
    library = ctypes.CDLL(str(ROOT / "zig-out" / library_dir / filename))
    library.madeitpx_options_init.argtypes = [ctypes.POINTER(Options)]
    library.madeitpx_options_init.restype = ctypes.c_int
    library.madeitpx_convert_rgba8.argtypes = [
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.c_size_t,
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.POINTER(Options),
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
    ]
    library.madeitpx_convert_rgba8.restype = ctypes.c_int
    return library


def color_count(pixels):
    return len(set(zip(pixels[0::4], pixels[1::4], pixels[2::4])))


class PatternTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.library = load_library()
        cls.patterns = {}
        for path in sorted(PATTERN_DIR.glob("*.png")):
            cls.patterns[path.stem] = (*read_png(path), path.name)
        if len(cls.patterns) != EXPECTED_PATTERN_COUNT:
            raise RuntimeError(
                f"Expected {EXPECTED_PATTERN_COUNT} patterns in {PATTERN_DIR}, "
                f"found {len(cls.patterns)}"
            )

    def convert(
        self,
        image,
        target_width,
        target_height,
        preset=0,
        sample_mode=1,
        palette_colors=0,
        cleanup=1,
    ):
        width, height, pixels, name = image
        source = (ctypes.c_uint8 * len(pixels)).from_buffer_copy(pixels)
        output_size = target_width * target_height * 4
        output = (ctypes.c_uint8 * output_size)()
        options = Options()
        self.assertEqual(self.library.madeitpx_options_init(ctypes.byref(options)), 0)
        options.preset = preset
        options.sample_mode = sample_mode
        options.palette_colors = palette_colors
        options.cluster_cleanup = cleanup
        status = self.library.madeitpx_convert_rgba8(
            source,
            len(pixels),
            width,
            height,
            width * 4,
            target_width,
            target_height,
            ctypes.byref(options),
            output,
            output_size,
        )
        self.assertEqual(status, 0, name)
        return bytes(output)

    def assert_opaque_and_bounded(self, pixels, limit, name):
        self.assertTrue(all(alpha == 255 for alpha in pixels[3::4]), name)
        self.assertLessEqual(color_count(pixels), limit, name)

    def test_every_pattern_with_all_presets_and_sampling_modes(self):
        for image in self.patterns.values():
            name = image[3]
            for preset, limit in PRESET_LIMITS.items():
                for sample_mode in (0, 1):
                    with self.subTest(pattern=name, preset=preset, sample_mode=sample_mode):
                        output = self.convert(
                            image,
                            48,
                            37,
                            preset=preset,
                            sample_mode=sample_mode,
                        )
                        self.assertEqual(len(output), 48 * 37 * 4)
                        self.assert_opaque_and_bounded(output, limit, name)

    def test_custom_palette_limits(self):
        for stem in ("02_gray_ramps", "10_noisy_gradient"):
            image = self.patterns[stem]
            for palette_colors in (2, 4, 8, 16, 32, 64):
                with self.subTest(pattern=image[3], palette_colors=palette_colors):
                    output = self.convert(image, 48, 37, palette_colors=palette_colors)
                    self.assert_opaque_and_bounded(output, palette_colors, image[3])

    def test_near_duplicate_colors_merge(self):
        image = self.patterns["04_near_duplicate_colors"]
        source_colors = color_count(image[2])
        output = self.convert(
            image,
            128,
            128,
            palette_colors=8,
            cleanup=0,
        )
        self.assertLess(color_count(output), source_colors, image[3])
        self.assertLessEqual(color_count(output), 8, image[3])

    def test_sixty_four_swatches_fit_detail_palette(self):
        image = self.patterns["03_swatches_64_colors"]
        width, height = image[:2]
        output = self.convert(
            image,
            width,
            height,
            preset=1,
            sample_mode=1,
            cleanup=0,
        )
        self.assertEqual(color_count(output), 64, image[3])
        self.assertEqual(output, image[2], image[3])

    def test_extreme_colors_are_preserved_when_within_palette(self):
        image = self.patterns["14_extreme_colors"]
        width, height = image[:2]
        output = self.convert(
            image,
            width,
            height,
            preset=1,
            cleanup=0,
        )
        self.assertEqual(output, image[2], image[3])

    def test_sampling_modes_differ_on_checkerboard_pattern(self):
        image = self.patterns["07_checkerboards_1_2_4_8px"]
        nearest = self.convert(image, 64, 64, sample_mode=1)
        area = self.convert(image, 64, 64, sample_mode=0)
        self.assertNotEqual(nearest, area, image[3])

    def test_area_sampling_mixes_fine_color_stripes(self):
        image = self.patterns["08_color_stripes_fine"]
        nearest = self.convert(image, 64, 64, sample_mode=1)
        area = self.convert(image, 64, 64, sample_mode=0)
        self.assertGreater(color_count(area), color_count(nearest), image[3])

    def test_cluster_cleanup_changes_isolated_pixel_pattern(self):
        image = self.patterns["09_isolated_pixels_cleanup"]
        uncleaned = self.convert(image, 64, 64, cleanup=0)
        cleaned = self.convert(image, 64, 64, cleanup=1)
        changed = sum(
            uncleaned[offset : offset + 4] != cleaned[offset : offset + 4]
            for offset in range(0, len(cleaned), 4)
        )
        self.assertGreater(changed, 0, image[3])
        self.assertLess(changed, 64 * 64 // 10, image[3])

    def test_odd_sized_patterns_convert_at_their_native_grid(self):
        for stem, image in self.patterns.items():
            if not stem.startswith("15_odd_size_"):
                continue
            width, height = image[:2]
            with self.subTest(pattern=image[3]):
                output = self.convert(image, width, height)
                self.assertEqual(len(output), width * height * 4)
                self.assert_opaque_and_bounded(output, 32, image[3])


if __name__ == "__main__":
    unittest.main(verbosity=2)
