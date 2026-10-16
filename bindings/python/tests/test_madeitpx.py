import os
import unittest
from unittest.mock import patch

import madeitpx
from madeitpx import (
    ConversionOptions,
    Preset,
    SamplingMode,
    convert_rgba8,
)


class MadeItPxTests(unittest.TestCase):
    def test_rejects_invalid_dimensions_before_loading_library(self):
        with self.assertRaisesRegex(ValueError, "input_width"):
            convert_rgba8(b"\x00" * 4, 0, 1, 1, 1)

    def test_rejects_short_input_before_loading_library(self):
        with self.assertRaisesRegex(ValueError, "enough bytes"):
            convert_rgba8(b"\x00" * 3, 1, 1, 1, 1)

    def test_rejects_invalid_options(self):
        with self.assertRaisesRegex(ValueError, "palette_colors"):
            ConversionOptions(palette_colors=1)
        with self.assertRaisesRegex(ValueError, "background_rgb"):
            ConversionOptions(background_rgb=0x1000000)

    @unittest.skipUnless(os.environ.get("MADEITPX_LIBRARY_PATH"), "native library path not set")
    def test_converts_transparent_pixel_using_configured_background(self):
        result = convert_rgba8(
            bytes((255, 0, 255, 0)),
            1,
            1,
            1,
            1,
            options=ConversionOptions(
                background_rgb=0x123456,
                sampling=SamplingMode.AREA,
            ),
        )
        self.assertEqual(result, bytes((0x12, 0x34, 0x56, 255)))

    @unittest.skipUnless(os.environ.get("MADEITPX_LIBRARY_PATH"), "native library path not set")
    def test_accepts_padded_rows_and_memoryviews(self):
        source = memoryview(bytes((
            255, 0, 0, 255, 0, 255, 0, 255, 9, 9, 9, 9,
            0, 0, 255, 255, 255, 255, 255, 255, 9, 9, 9, 9,
        )))
        result = convert_rgba8(
            source,
            2,
            2,
            2,
            2,
            input_stride=12,
            options=ConversionOptions(
                preset=Preset.DETAIL,
                palette_colors=4,
                cluster_cleanup=False,
            ),
        )
        self.assertEqual(len(result), 16)
        self.assertEqual(result[3::4], bytes((255, 255, 255, 255)))

    def test_loads_bundled_library_automatically(self):
        with patch.dict(os.environ, {"MADEITPX_LIBRARY_PATH": ""}):
            try:
                madeitpx._library_path(None)
            except FileNotFoundError:
                self.skipTest("no native library bundled for this test platform")
            result = convert_rgba8(bytes((10, 20, 30, 255)), 1, 1, 1, 1)
        self.assertEqual(result, bytes((10, 20, 30, 255)))


if __name__ == "__main__":
    unittest.main()
