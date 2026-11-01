const api = @import("types.zig");
const palette_mod = @import("../core/palette.zig");

pub const Checked = struct {
    status: api.Status,
    output_size: usize = 0,
};

fn checkedMul(a: usize, b: usize) ?usize {
    const result = @mulWithOverflow(a, b);
    if (result[1] != 0) return null;
    return result[0];
}

fn checkedAdd(a: usize, b: usize) ?usize {
    const result = @addWithOverflow(a, b);
    if (result[1] != 0) return null;
    return result[0];
}

pub fn rgbaSize(width: u32, height: u32) ?usize {
    const pixels = checkedMul(@as(usize, width), @as(usize, height)) orelse return null;
    return checkedMul(pixels, 4);
}

pub fn validOptions(options: *const api.Options) bool {
    return options.struct_size >= @sizeOf(api.Options) and
        options.reserved == 0 and
        (options.palette_colors == 0 or (options.palette_colors >= 2 and options.palette_colors <= palette_mod.max_colors)) and
        options.preset <= @backingInt(api.Preset.pixelart) and
        options.sample_mode <= @backingInt(api.SampleMode.nearest) and
        options.cluster_cleanup <= 1;
}

pub fn validPixelArtOptions(options: *const api.PixelArtOptions) bool {
    return options.struct_size >= @sizeOf(api.PixelArtOptions) and
        options.reserved == 0 and
        (options.version == 1 or options.version == 2) and
        options.grid_fit <= 1 and
        options.grid_search_permille <= 200 and
        options.sample_inset_percent <= 45 and
        options.color_tolerance <= 442 and
        (options.palette_max == 0 or (options.palette_max >= 2 and options.palette_max <= 256)) and
        options.refine_iterations <= 32 and
        options.mode <= @backingInt(api.PixelArtMode.illustration) and
        options.ink_percent <= 100 and
        options.min_region >= 1 and options.min_region <= 64 and
        options.alpha_threshold <= 255;
}

pub fn checkBuffers(
    input_size: usize,
    input_width: u32,
    input_height: u32,
    input_stride: usize,
    target_width: u32,
    target_height: u32,
    output_capacity: usize,
) Checked {
    if (input_width == 0 or input_height == 0 or target_width == 0 or target_height == 0)
        return .{ .status = .invalid_argument };

    const source_row_size = checkedMul(@as(usize, input_width), 4) orelse return .{ .status = .size_overflow };
    if (input_stride < source_row_size) return .{ .status = .invalid_argument };
    const source_offset = checkedMul(@as(usize, input_height - 1), input_stride) orelse return .{ .status = .size_overflow };
    const required_input_size = checkedAdd(source_offset, source_row_size) orelse return .{ .status = .size_overflow };
    if (input_size < required_input_size) return .{ .status = .buffer_too_small };

    const required_output_size = rgbaSize(target_width, target_height) orelse return .{ .status = .size_overflow };
    if (output_capacity < required_output_size) return .{ .status = .buffer_too_small };
    return .{ .status = .ok, .output_size = required_output_size };
}
