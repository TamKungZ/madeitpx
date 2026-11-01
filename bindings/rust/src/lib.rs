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

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PixelArtMode {
    Auto = 0,
    Grid = 1,
    Illustration = 2,
}

impl PixelArtMode {
    fn from_native(value: u32) -> Option<Self> {
        match value {
            0 => Some(Self::Auto),
            1 => Some(Self::Grid),
            2 => Some(Self::Illustration),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct PixelArtSettings {
    pub version: Option<u32>,
    pub mode: Option<PixelArtMode>,
    pub grid_fit: Option<bool>,
    pub grid_search_permille: Option<u32>,
    pub sample_inset_percent: Option<u32>,
    pub color_tolerance: Option<u32>,
    pub palette_max: Option<u32>,
    pub refine_iterations: Option<u32>,
    pub ink_percent: Option<u32>,
    pub min_region: Option<u32>,
    pub alpha_threshold: Option<u32>,
    pub keep_transparency: Option<bool>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Options {
    pub preset: Preset,
    pub palette_colors: u32,
    pub background_rgb: u32,
    pub sampling: SamplingMode,
    pub cluster_cleanup: bool,
    pub pixelart: PixelArtSettings,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            preset: Preset::Balanced,
            palette_colors: 0,
            background_rgb: 0,
            sampling: SamplingMode::Nearest,
            cluster_cleanup: true,
            pixelart: PixelArtSettings::default(),
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

#[repr(C)]
#[derive(Default)]
struct NativePixelArtOptions {
    struct_size: u32,
    version: u32,
    grid_fit: u32,
    grid_search_permille: u32,
    sample_inset_percent: u32,
    color_tolerance: u32,
    palette_max: u32,
    refine_iterations: u32,
    mode: u32,
    ink_percent: u32,
    min_region: u32,
    alpha_threshold: u32,
    keep_transparency: u32,
    reserved: u32,
}

type PixelArtInit = unsafe extern "C" fn(*mut NativePixelArtOptions) -> i32;
type ConvertPixelArt = unsafe extern "C" fn(
    *const u8,
    usize,
    u32,
    u32,
    usize,
    u32,
    u32,
    *const NativeOptions,
    *const NativePixelArtOptions,
    *mut u8,
    usize,
) -> i32;
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
    pixelart_init: PixelArtInit,
    convert_pixelart: ConvertPixelArt,
}

impl NativeLibrary {
    fn load() -> Result<Self, MadeItPxError> {
        let path = native_library_path()?;
        let library =
            unsafe { libloading::Library::new(path) }.map_err(MadeItPxError::NativeLoad)?;
        let (options_init, get_output_size, convert_rgba8, pixelart_init, convert_pixelart) = unsafe {
            let options_init = *library
                .get::<OptionsInit>(b"madeitpx_options_init\0")
                .map_err(MadeItPxError::NativeLoad)?;
            let get_output_size = *library
                .get::<GetOutputSize>(b"madeitpx_get_output_size\0")
                .map_err(MadeItPxError::NativeLoad)?;
            let convert_rgba8 = *library
                .get::<ConvertRgba8>(b"madeitpx_convert_rgba8\0")
                .map_err(MadeItPxError::NativeLoad)?;
            let pixelart_init = *library
                .get::<PixelArtInit>(b"madeitpx_pixelart_options_init\0")
                .map_err(MadeItPxError::NativeLoad)?;
            let convert_pixelart = *library
                .get::<ConvertPixelArt>(b"madeitpx_convert_pixelart_rgba8\0")
                .map_err(MadeItPxError::NativeLoad)?;
            (
                options_init,
                get_output_size,
                convert_rgba8,
                pixelart_init,
                convert_pixelart,
            )
        };

        Ok(Self {
            _library: library,
            options_init,
            get_output_size,
            convert_rgba8,
            pixelart_init,
            convert_pixelart,
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

impl PixelArtSettings {
    fn apply(&self, native: &mut NativePixelArtOptions) {
        if let Some(value) = self.version {
            native.version = value;
        }
        if let Some(value) = self.mode {
            native.mode = value as u32;
        }
        if let Some(value) = self.grid_fit {
            native.grid_fit = u32::from(value);
        }
        if let Some(value) = self.grid_search_permille {
            native.grid_search_permille = value;
        }
        if let Some(value) = self.sample_inset_percent {
            native.sample_inset_percent = value;
        }
        if let Some(value) = self.color_tolerance {
            native.color_tolerance = value;
        }
        if let Some(value) = self.palette_max {
            native.palette_max = value;
        }
        if let Some(value) = self.refine_iterations {
            native.refine_iterations = value;
        }
        if let Some(value) = self.ink_percent {
            native.ink_percent = value;
        }
        if let Some(value) = self.min_region {
            native.min_region = value;
        }
        if let Some(value) = self.alpha_threshold {
            native.alpha_threshold = value;
        }
        if let Some(value) = self.keep_transparency {
            native.keep_transparency = u32::from(value);
        }
    }

    fn from_native(native: &NativePixelArtOptions) -> Self {
        Self {
            version: Some(native.version),
            mode: PixelArtMode::from_native(native.mode),
            grid_fit: Some(native.grid_fit == 1),
            grid_search_permille: Some(native.grid_search_permille),
            sample_inset_percent: Some(native.sample_inset_percent),
            color_tolerance: Some(native.color_tolerance),
            palette_max: Some(native.palette_max),
            refine_iterations: Some(native.refine_iterations),
            ink_percent: Some(native.ink_percent),
            min_region: Some(native.min_region),
            alpha_threshold: Some(native.alpha_threshold),
            keep_transparency: Some(native.keep_transparency == 1),
        }
    }
}

pub fn pixelart_defaults() -> Result<PixelArtSettings, MadeItPxError> {
    let library = native_library()?;
    let mut native = NativePixelArtOptions::default();
    check_status(unsafe { (library.pixelart_init)(&mut native) })?;
    Ok(PixelArtSettings::from_native(&native))
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
    if options.preset == Preset::Pixelart {
        let mut native_pixelart = NativePixelArtOptions::default();
        check_status(unsafe { (library.pixelart_init)(&mut native_pixelart) })?;
        options.pixelart.apply(&mut native_pixelart);
        check_status(unsafe {
            (library.convert_pixelart)(
                input.as_ptr(),
                input.len(),
                input_width_u32,
                input_height_u32,
                stride,
                target_width_u32,
                target_height_u32,
                &native_options,
                &native_pixelart,
                output.as_mut_ptr(),
                output.len(),
            )
        })?;
        return Ok(output);
    }
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

    #[test]
    fn exposes_pixelart_defaults_and_version_one() {
        if env::var_os("MADEITPX_LIBRARY_PATH").is_none() {
            return;
        }
        let defaults = pixelart_defaults().expect("defaults should load");
        assert_eq!(defaults.version, Some(2));
        assert_eq!(defaults.mode, Some(PixelArtMode::Auto));
        assert_eq!(defaults.keep_transparency, Some(true));
        let options = Options {
            preset: Preset::Pixelart,
            pixelart: PixelArtSettings {
                version: Some(1),
                ..PixelArtSettings::default()
            },
            ..Options::default()
        };
        let output = convert_rgba8(&[90, 120, 150, 255], 1, 1, None, 1, 1, options)
            .expect("version 1 should succeed");
        assert_eq!(output, [90, 120, 150, 255]);
        let invalid = Options {
            preset: Preset::Pixelart,
            pixelart: PixelArtSettings {
                palette_max: Some(1),
                ..PixelArtSettings::default()
            },
            ..Options::default()
        };
        assert!(matches!(
            convert_rgba8(&[90, 120, 150, 255], 1, 1, None, 1, 1, invalid),
            Err(MadeItPxError::NativeStatus(1))
        ));
    }
}
