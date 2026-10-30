use std::env;
use std::error::Error;
use std::fmt;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

const UINT32_MAX: usize = u32::MAX as usize;

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Preset {
    Balanced = 0,
    Detail = 1,
    Bold = 2,
    Pixelart = 3,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SamplingMode {
    Area = 0,
    Nearest = 1,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Options {
    pub preset: Preset,
    pub palette_colors: u32,
    pub background_rgb: u32,
    pub sampling: SamplingMode,
    pub cluster_cleanup: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            preset: Preset::Balanced,
            palette_colors: 0,
            background_rgb: 0,
            sampling: SamplingMode::Nearest,
            cluster_cleanup: true,
        }
    }
}

#[derive(Debug)]
pub enum MadeItPxError {
    InvalidInput(&'static str),
    NativeLibrary(String),
    NativeLoad(libloading::Error),
    NativeStatus(i32),
    UnexpectedOutputSize { expected: usize, actual: usize },
}

impl fmt::Display for MadeItPxError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidInput(message) => formatter.write_str(message),
            Self::NativeLibrary(message) => formatter.write_str(message),
            Self::NativeLoad(error) => {
                write!(formatter, "unable to load madeitpx library: {error}")
            }
            Self::NativeStatus(status) => {
                write!(formatter, "madeitpx conversion failed with status {status}")
            }
            Self::UnexpectedOutputSize { expected, actual } => write!(
                formatter,
                "native library returned output size {actual}; expected {expected}"
            ),
        }
    }
}

impl Error for MadeItPxError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::NativeLoad(error) => Some(error),
            _ => None,
        }
    }
}

#[repr(C)]
struct NativeOptions {
    struct_size: u32,
    preset: u32,
    palette_colors: u32,
    background_rgb: u32,
    sample_mode: u32,
    cluster_cleanup: u32,
    reserved: u32,
}

type OptionsInit = unsafe extern "C" fn(*mut NativeOptions) -> i32;
type GetOutputSize = unsafe extern "C" fn(u32, u32, *mut usize) -> i32;
type ConvertRgba8 = unsafe extern "C" fn(
    *const u8,
    usize,
    u32,
    u32,
    usize,
    u32,
    u32,
    *const NativeOptions,
    *mut u8,
    usize,
) -> i32;

struct NativeLibrary {
    _library: libloading::Library,
    options_init: OptionsInit,
    get_output_size: GetOutputSize,
    convert_rgba8: ConvertRgba8,
}

impl NativeLibrary {
    fn load() -> Result<Self, MadeItPxError> {
        let path = native_library_path()?;
        let library =
            unsafe { libloading::Library::new(path) }.map_err(MadeItPxError::NativeLoad)?;
        let (options_init, get_output_size, convert_rgba8) = unsafe {
            let options_init = *library
                .get::<OptionsInit>(b"madeitpx_options_init\0")
                .map_err(MadeItPxError::NativeLoad)?;
            let get_output_size = *library
                .get::<GetOutputSize>(b"madeitpx_get_output_size\0")
                .map_err(MadeItPxError::NativeLoad)?;
            let convert_rgba8 = *library
                .get::<ConvertRgba8>(b"madeitpx_convert_rgba8\0")
                .map_err(MadeItPxError::NativeLoad)?;
            (options_init, get_output_size, convert_rgba8)
        };

        Ok(Self {
            _library: library,
            options_init,
            get_output_size,
            convert_rgba8,
        })
    }
}

static NATIVE_LIBRARY: OnceLock<Result<NativeLibrary, String>> = OnceLock::new();

fn native_library() -> Result<&'static NativeLibrary, MadeItPxError> {
    match NATIVE_LIBRARY.get_or_init(|| NativeLibrary::load().map_err(|error| error.to_string())) {
        Ok(library) => Ok(library),
        Err(message) => Err(MadeItPxError::NativeLibrary(message.clone())),
    }
}

fn native_library_path() -> Result<PathBuf, MadeItPxError> {
    if let Some(path) = env::var_os("MADEITPX_LIBRARY_PATH") {
        if !path.is_empty() {
            return Ok(PathBuf::from(path));
        }
    }

    let (target, filename) = native_target()?;
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("native")
        .join(target)
        .join(filename);
    if !path.is_file() {
        return Err(MadeItPxError::InvalidInput(
            "no bundled native library found; set MADEITPX_LIBRARY_PATH",
        ));
    }
    Ok(path)
}

fn native_target() -> Result<(&'static str, &'static str), MadeItPxError> {
    let target = match (env::consts::OS, env::consts::ARCH) {
        ("windows", "x86_64") => ("windows-x64", "madeitpx.dll"),
        ("windows", "aarch64") => ("windows-arm64", "madeitpx.dll"),
        ("linux", "x86_64") => ("linux-x64-gnu", "libmadeitpx.so"),
        ("linux", "aarch64") => ("linux-arm64-gnu", "libmadeitpx.so"),
        ("macos", "x86_64") => ("darwin-x64", "libmadeitpx.dylib"),
        ("macos", "aarch64") => ("darwin-arm64", "libmadeitpx.dylib"),
        (os, arch) => {
            return Err(MadeItPxError::InvalidInput(match (os, arch) {
                ("linux", _) => "madeitpx supports Linux x64 and ARM64 with glibc",
                ("windows", _) => "madeitpx supports Windows x64 and ARM64",
                ("macos", _) => "madeitpx supports macOS x64 and ARM64",
                _ => "madeitpx does not provide a native library for this platform",
            }))
        }
    };
    Ok(target)
}

fn validate_dimension(value: usize, name: &'static str) -> Result<u32, MadeItPxError> {
    if value == 0 || value > UINT32_MAX {
        return Err(MadeItPxError::InvalidInput(name));
    }
    Ok(value as u32)
}

fn validate_options(options: Options) -> Result<(), MadeItPxError> {
    if options.palette_colors != 0 && !(2..=64).contains(&options.palette_colors) {
        return Err(MadeItPxError::InvalidInput(
            "palette_colors must be 0 or between 2 and 64",
        ));
    }
    if options.background_rgb > 0xFFFFFF {
        return Err(MadeItPxError::InvalidInput(
            "background_rgb must be a 0xRRGGBB value",
        ));
    }
    Ok(())
}

fn check_status(status: i32) -> Result<(), MadeItPxError> {
    if status == 0 {
        Ok(())
    } else {
        Err(MadeItPxError::NativeStatus(status))
    }
}

pub fn convert_rgba8(
    input: &[u8],
    input_width: usize,
    input_height: usize,
    input_stride: Option<usize>,
    target_width: usize,
    target_height: usize,
    options: Options,
) -> Result<Vec<u8>, MadeItPxError> {
    let input_width_u32 = validate_dimension(input_width, "input_width must be a positive u32")?;
    let input_height_u32 = validate_dimension(input_height, "input_height must be a positive u32")?;
    let target_width_u32 = validate_dimension(target_width, "target_width must be a positive u32")?;
    let target_height_u32 =
        validate_dimension(target_height, "target_height must be a positive u32")?;
    let minimum_stride = input_width
        .checked_mul(4)
        .ok_or(MadeItPxError::InvalidInput("input row size overflow"))?;
    let stride = input_stride.unwrap_or(minimum_stride);
    if stride < minimum_stride {
        return Err(MadeItPxError::InvalidInput(
            "input_stride must be at least input_width * 4",
        ));
    }
    let required_input_size = (input_height - 1)
        .checked_mul(stride)
        .and_then(|offset| offset.checked_add(minimum_stride))
        .ok_or(MadeItPxError::InvalidInput("input size overflow"))?;
    if input.len() < required_input_size {
        return Err(MadeItPxError::InvalidInput(
            "input does not contain enough bytes for its dimensions and stride",
        ));
    }
    let output_size = target_width
        .checked_mul(target_height)
        .and_then(|pixels| pixels.checked_mul(4))
        .ok_or(MadeItPxError::InvalidInput("output size overflow"))?;
    validate_options(options)?;

    let library = native_library()?;
    let mut native_options = NativeOptions {
        struct_size: 0,
        preset: 0,
        palette_colors: 0,
        background_rgb: 0,
        sample_mode: 0,
        cluster_cleanup: 0,
        reserved: 0,
    };
    check_status(unsafe { (library.options_init)(&mut native_options) })?;
    native_options.preset = options.preset as u32;
    native_options.palette_colors = options.palette_colors;
    native_options.background_rgb = options.background_rgb;
    native_options.sample_mode = options.sampling as u32;
    native_options.cluster_cleanup = u32::from(options.cluster_cleanup);

    let mut native_output_size = 0usize;
    check_status(unsafe {
        (library.get_output_size)(target_width_u32, target_height_u32, &mut native_output_size)
    })?;
    if native_output_size != output_size {
        return Err(MadeItPxError::UnexpectedOutputSize {
            expected: output_size,
            actual: native_output_size,
        });
    }

    let mut output = vec![0u8; output_size];
    check_status(unsafe {
        (library.convert_rgba8)(
            input.as_ptr(),
            input.len(),
            input_width_u32,
            input_height_u32,
            stride,
            target_width_u32,
            target_height_u32,
            &native_options,
            output.as_mut_ptr(),
            output.len(),
        )
    })?;
    Ok(output)
}

impl From<libloading::Error> for MadeItPxError {
    fn from(error: libloading::Error) -> Self {
        Self::NativeLoad(error)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_invalid_dimensions_before_loading_native_library() {
        let error = convert_rgba8(&[0; 4], 0, 1, None, 1, 1, Options::default())
            .expect_err("zero width must be rejected");
        assert!(matches!(error, MadeItPxError::InvalidInput(_)));
    }

    #[test]
    fn rejects_short_input_before_loading_native_library() {
        let error = convert_rgba8(&[0; 3], 1, 1, None, 1, 1, Options::default())
            .expect_err("short input must be rejected");
        assert!(matches!(error, MadeItPxError::InvalidInput(_)));
    }

    #[test]
    fn rejects_invalid_options_before_loading_native_library() {
        let options = Options {
            palette_colors: 1,
            ..Options::default()
        };
        let error = convert_rgba8(&[0; 4], 1, 1, None, 1, 1, options)
            .expect_err("invalid palette size must be rejected");
        assert!(matches!(error, MadeItPxError::InvalidInput(_)));
    }

    #[test]
    fn converts_transparent_pixel_using_configured_background() {
        if env::var_os("MADEITPX_LIBRARY_PATH").is_none() {
            return;
        }
        let output = convert_rgba8(
            &[255, 0, 255, 0],
            1,
            1,
            None,
            1,
            1,
            Options {
                background_rgb: 0x123456,
                ..Options::default()
            },
        )
        .expect("conversion should succeed");
        assert_eq!(output, [0x12, 0x34, 0x56, 255]);
    }

    #[test]
    fn accepts_padded_rows() {
        if env::var_os("MADEITPX_LIBRARY_PATH").is_none() {
            return;
        }
        let input = [
            255, 0, 0, 255, 0, 255, 0, 255, 9, 9, 9, 9, 0, 0, 255, 255, 255, 255, 255, 255, 9, 9,
            9, 9,
        ];
        let output = convert_rgba8(
            &input,
            2,
            2,
            Some(12),
            2,
            2,
            Options {
                palette_colors: 4,
                cluster_cleanup: false,
                ..Options::default()
            },
        )
        .expect("conversion should succeed");
        assert_eq!(output.len(), 16);
        assert!(output[3..].iter().step_by(4).all(|alpha| *alpha == 255));
    }

    #[test]
    fn converts_with_pixelart_preset() {
        if env::var_os("MADEITPX_LIBRARY_PATH").is_none() {
            return;
        }
        let output = convert_rgba8(
            &[90, 120, 150, 255],
            1,
            1,
            None,
            1,
            1,
            Options {
                preset: Preset::Pixelart,
                palette_colors: 2,
                ..Options::default()
            },
        )
        .expect("pixelart conversion should succeed");
        assert_eq!(output, [90, 120, 150, 255]);
    }
}
