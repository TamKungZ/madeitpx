pub const Status = enum(c_int) {
    ok = 0,
    invalid_argument = 1,
    buffer_too_small = 2,
    size_overflow = 3,
    out_of_memory = 4,
};

pub const Preset = enum(u32) {
    balanced = 0,
    detail = 1,
    bold = 2,
    pixelart = 3,
};

pub const SampleMode = enum(u32) {
    area = 0,
    nearest = 1,
};

pub const Options = extern struct {
    struct_size: u32,
    preset: u32,
    palette_colors: u32,
    background_rgb: u32,
    sample_mode: u32,
    cluster_cleanup: u32,
    reserved: u32,
};

pub const abi_version: u32 = 0x00010000;

pub const PixelArtMode = enum(u32) {
    auto = 0,
    grid = 1,
    illustration = 2,
};

pub const PixelArtOptions = extern struct {
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
    reserved: u32,
};

pub const PixelArtField = enum(u32) {
    version = 0,
    grid_fit = 1,
    grid_search_permille = 2,
    sample_inset_percent = 3,
    color_tolerance = 4,
    palette_max = 5,
    refine_iterations = 6,
    mode = 7,
    ink_percent = 8,
    min_region = 9,
    alpha_threshold = 10,
};

pub const pixelart_defaults = PixelArtOptions{
    .struct_size = @sizeOf(PixelArtOptions),
    .version = 2,
    .grid_fit = 1,
    .grid_search_permille = 30,
    .sample_inset_percent = 25,
    .color_tolerance = 14,
    .palette_max = 0,
    .refine_iterations = 5,
    .mode = 0,
    .ink_percent = 20,
    .min_region = 4,
    .alpha_threshold = 128,
    .reserved = 0,
};
