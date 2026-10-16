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
