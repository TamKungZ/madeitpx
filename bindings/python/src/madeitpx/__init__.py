from __future__ import annotations

import ctypes
import os
import platform
import struct
from dataclasses import dataclass
from enum import IntEnum
from functools import lru_cache
from pathlib import Path
from typing import Optional, Union

__version__ = "0.1.1"

_UINT32_MAX = 0xFFFFFFFF
_MAX_OUTPUT_SIZE = (1 << (struct.calcsize("P") * 8 - 1)) - 1
_LIBRARY_PATH_ENVIRONMENT = "MADEITPX_LIBRARY_PATH"


class Preset(IntEnum):
    BALANCED = 0
    DETAIL = 1
    BOLD = 2


class SamplingMode(IntEnum):
    AREA = 0
    NEAREST = 1


@dataclass(frozen=True)
class ConversionOptions:
    preset: Preset = Preset.BALANCED
    palette_colors: int = 0
    background_rgb: int = 0
    sampling: SamplingMode = SamplingMode.NEAREST
    cluster_cleanup: bool = True

    def __post_init__(self) -> None:
        if not isinstance(self.preset, Preset):
            raise TypeError("preset must be a Preset value")
        if not isinstance(self.sampling, SamplingMode):
            raise TypeError("sampling must be a SamplingMode value")
        if (
            not isinstance(self.palette_colors, int)
            or isinstance(self.palette_colors, bool)
            or (
                self.palette_colors != 0
                and not 2 <= self.palette_colors <= 64
            )
        ):
            raise ValueError("palette_colors must be 0 or an integer from 2 to 64")
        if (
            not isinstance(self.background_rgb, int)
            or isinstance(self.background_rgb, bool)
            or not 0 <= self.background_rgb <= 0xFFFFFF
        ):
            raise ValueError("background_rgb must be a 0xRRGGBB integer")
        if not isinstance(self.cluster_cleanup, bool):
            raise TypeError("cluster_cleanup must be a bool")


class ConversionError(RuntimeError):
    def __init__(self, status: int) -> None:
        self.status = status
        try:
            name = _Status(status).name.lower()
        except ValueError:
            name = f"unknown status {status}"
        super().__init__(f"madeitpx conversion failed: {name}")


class _Status(IntEnum):
    OK = 0
    INVALID_ARGUMENT = 1
    BUFFER_TOO_SMALL = 2
    SIZE_OVERFLOW = 3
    OUT_OF_MEMORY = 4


class _NativeOptions(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_uint32),
        ("preset", ctypes.c_uint32),
        ("palette_colors", ctypes.c_uint32),
        ("background_rgb", ctypes.c_uint32),
        ("sample_mode", ctypes.c_uint32),
        ("cluster_cleanup", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
    ]


def _native_library_name() -> tuple[str, str]:
    if struct.calcsize("P") != 8:
        raise RuntimeError("madeitpx native binaries require a 64-bit Python process")
    system = platform.system()
    machine = platform.machine().lower()
    if machine in ("amd64", "x86_64"):
        architecture = "x64"
    elif machine in ("aarch64", "arm64"):
        architecture = "arm64"
    else:
        raise RuntimeError(f"madeitpx does not provide native binaries for {system} {machine}")

    if system == "Windows":
        return f"windows-{architecture}", "madeitpx.dll"
    if system == "Darwin":
        return f"darwin-{architecture}", "libmadeitpx.dylib"
    if system == "Linux":
        libc_name, _ = platform.libc_ver()
        if libc_name and libc_name.lower() != "glibc":
            raise RuntimeError(
                f"madeitpx Linux binaries require glibc; detected {libc_name}"
            )
        return f"linux-{architecture}-gnu", "libmadeitpx.so"
    raise RuntimeError(f"madeitpx does not provide native binaries for {system}")


@lru_cache(maxsize=8)
def _load_native_library(library_path: str) -> ctypes.CDLL:
    library = ctypes.CDLL(library_path)
    library.madeitpx_options_init.argtypes = [ctypes.POINTER(_NativeOptions)]
    library.madeitpx_options_init.restype = ctypes.c_int
    library.madeitpx_get_output_size.argtypes = [
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_size_t),
    ]
    library.madeitpx_get_output_size.restype = ctypes.c_int
    library.madeitpx_convert_rgba8.argtypes = [
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.c_size_t,
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.POINTER(_NativeOptions),
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
    ]
    library.madeitpx_convert_rgba8.restype = ctypes.c_int
    return library


def _library_path(library_path: Optional[Union[str, os.PathLike[str]]]) -> str:
    override = library_path or os.environ.get(_LIBRARY_PATH_ENVIRONMENT)
    if override:
        return os.fspath(override)

    target, filename = _native_library_name()
    path = Path(__file__).resolve().parent / "native" / target / filename
    if not path.is_file():
        raise FileNotFoundError(
            f"No madeitpx native library was found for {target}; install the "
            "published wheel or set MADEITPX_LIBRARY_PATH to a native library"
        )
    return str(path)


def _validate_dimension(value: int, name: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or not 0 < value <= _UINT32_MAX:
        raise ValueError(f"{name} must be a positive 32-bit integer")


def _check_status(status: int) -> None:
    if status != _Status.OK:
        raise ConversionError(status)


def convert_rgba8(
    input_pixels: Union[bytes, bytearray, memoryview],
    input_width: int,
    input_height: int,
    target_width: int,
    target_height: int,
    *,
    input_stride: Optional[int] = None,
    options: Optional[ConversionOptions] = None,
    library_path: Optional[Union[str, os.PathLike[str]]] = None,
) -> bytes:
    """Convert RGBA8 pixels to an opaque RGBA8 buffer."""
    if not isinstance(input_pixels, (bytes, bytearray, memoryview)):
        raise TypeError("input_pixels must be bytes, bytearray, or memoryview")
    _validate_dimension(input_width, "input_width")
    _validate_dimension(input_height, "input_height")
    _validate_dimension(target_width, "target_width")
    _validate_dimension(target_height, "target_height")

    minimum_stride = input_width * 4
    stride = minimum_stride if input_stride is None else input_stride
    _validate_dimension(stride, "input_stride")
    if stride < minimum_stride:
        raise ValueError("input_stride must be at least input_width * 4")

    source = bytes(input_pixels)
    required_input_size = (input_height - 1) * stride + minimum_stride
    if required_input_size > len(source):
        raise ValueError("input_pixels does not contain enough bytes for its dimensions and stride")

    output_size = target_width * target_height * 4
    if output_size > _MAX_OUTPUT_SIZE:
        raise ValueError("output is too large for a Python bytes object")
    settings = ConversionOptions() if options is None else options
    if not isinstance(settings, ConversionOptions):
        raise TypeError("options must be ConversionOptions or None")

    library = _load_native_library(_library_path(library_path))
    native_options = _NativeOptions()
    _check_status(library.madeitpx_options_init(ctypes.byref(native_options)))
    native_options.preset = int(settings.preset)
    native_options.palette_colors = settings.palette_colors
    native_options.background_rgb = settings.background_rgb
    native_options.sample_mode = int(settings.sampling)
    native_options.cluster_cleanup = int(settings.cluster_cleanup)

    native_output_size = ctypes.c_size_t()
    _check_status(
        library.madeitpx_get_output_size(
            target_width, target_height, ctypes.byref(native_output_size)
        )
    )
    if native_output_size.value != output_size:
        raise RuntimeError("native library returned an unexpected output size")

    source_buffer = (ctypes.c_uint8 * len(source)).from_buffer_copy(source)
    output_buffer = (ctypes.c_uint8 * output_size)()
    _check_status(
        library.madeitpx_convert_rgba8(
            source_buffer,
            len(source),
            input_width,
            input_height,
            stride,
            target_width,
            target_height,
            ctypes.byref(native_options),
            output_buffer,
            output_size,
        )
    )
    return bytes(output_buffer)


__all__ = [
    "ConversionError",
    "ConversionOptions",
    "Preset",
    "SamplingMode",
    "convert_rgba8",
]
