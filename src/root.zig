const std = @import("std");

const api = @import("api_types.zig");
const sampling = @import("sampling.zig");
const palette_mod = @import("palette.zig");
const pixelart = @import("pixelart.zig");
const pixelart_v2 = @import("pixelart_v2.zig");

pub const PixelArtOptions = api.PixelArtOptions;
pub const PixelArtField = api.PixelArtField;
pub const Status = api.Status;
pub const Preset = api.Preset;
pub const SampleMode = api.SampleMode;
pub const Options = api.Options;
pub const abi_version = api.abi_version;

const max_palette_colors = palette_mod.max_colors;
const compositeAndQuantize = palette_mod.compositeAndQuantize;

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

fn validOptions(options: *const Options) bool {
    return options.struct_size >= @sizeOf(Options) and
        options.reserved == 0 and
        (options.palette_colors == 0 or (options.palette_colors >= 2 and options.palette_colors <= max_palette_colors)) and
        options.preset <= @backingInt(Preset.pixelart) and
        options.sample_mode <= @backingInt(SampleMode.nearest) and
        options.cluster_cleanup <= 1;
}

fn rgbaSize(width: u32, height: u32) ?usize {
    const pixels = checkedMul(@as(usize, width), @as(usize, height)) orelse return null;
    return checkedMul(pixels, 4);
}

const Checked = struct {
    status: Status,
    output_size: usize = 0,
};

fn checkBuffers(
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

fn validPixelArtOptions(options: *const PixelArtOptions) bool {
    return options.struct_size >= @sizeOf(PixelArtOptions) and
        options.reserved == 0 and
        (options.version == 1 or options.version == 2) and
        options.grid_fit <= 1 and
        options.grid_search_permille <= 200 and
        options.sample_inset_percent <= 45 and
        options.color_tolerance <= 442 and
        (options.palette_max == 0 or (options.palette_max >= 2 and options.palette_max <= 256)) and
        options.refine_iterations <= 32;
}

export fn madeitpx_version() u32 {
    return abi_version;
}

export fn madeitpx_options_init(options: ?*Options) Status {
    const value = options orelse return .invalid_argument;
    value.* = .{
        .struct_size = @sizeOf(Options),
        .preset = @backingInt(Preset.balanced),
        .palette_colors = 0,
        .background_rgb = 0,
        .sample_mode = @backingInt(SampleMode.nearest),
        .cluster_cleanup = 1,
        .reserved = 0,
    };
    return .ok;
}

export fn madeitpx_get_output_size(
    target_width: u32,
    target_height: u32,
    output_size: ?*usize,
) Status {
    const size = output_size orelse return .invalid_argument;
    if (target_width == 0 or target_height == 0) return .invalid_argument;
    size.* = rgbaSize(target_width, target_height) orelse return .size_overflow;
    return .ok;
}

export fn madeitpx_convert_rgba8(
    input: ?[*]const u8,
    input_size: usize,
    input_width: u32,
    input_height: u32,
    input_stride: usize,
    target_width: u32,
    target_height: u32,
    options: ?*const Options,
    output: ?[*]u8,
    output_capacity: usize,
) Status {
    const source = input orelse return .invalid_argument;
    const destination = output orelse return .invalid_argument;
    const config = options orelse return .invalid_argument;
    if (!validOptions(config)) return .invalid_argument;
    const checked = checkBuffers(input_size, input_width, input_height, input_stride, target_width, target_height, output_capacity);
    if (checked.status != .ok) return checked.status;
    const required_output_size = checked.output_size;
    if (config.preset == @backingInt(Preset.pixelart)) {
        return pixelart.convert(source, input_width, input_height, input_stride, target_width, target_height, config, destination);
    }
    const output_pixel_count = required_output_size / 4;
    const indices = std.heap.page_allocator.alloc(usize, output_pixel_count) catch return .out_of_memory;
    defer std.heap.page_allocator.free(indices);

    if (config.sample_mode == @backingInt(SampleMode.nearest)) {
        sampling.nearest(source, input_width, input_height, input_stride, target_width, target_height, destination);
    } else {
        sampling.resample(source, input_width, input_height, input_stride, target_width, target_height, destination);
    }
    compositeAndQuantize(destination, output_pixel_count, config, target_width, target_height, indices);
    return .ok;
}

export fn madeitpx_pixelart_options_init(options: ?*PixelArtOptions) Status {
    const value = options orelse return .invalid_argument;
    value.* = api.pixelart_defaults;
    return .ok;
}

export fn madeitpx_pixelart_options_reset_field(options: ?*PixelArtOptions, field: u32) Status {
    const value = options orelse return .invalid_argument;
    if (value.struct_size < @sizeOf(PixelArtOptions)) return .invalid_argument;
    const defaults = api.pixelart_defaults;
    switch (field) {
        @backingInt(PixelArtField.version) => value.version = defaults.version,
        @backingInt(PixelArtField.grid_fit) => value.grid_fit = defaults.grid_fit,
        @backingInt(PixelArtField.grid_search_permille) => value.grid_search_permille = defaults.grid_search_permille,
        @backingInt(PixelArtField.sample_inset_percent) => value.sample_inset_percent = defaults.sample_inset_percent,
        @backingInt(PixelArtField.color_tolerance) => value.color_tolerance = defaults.color_tolerance,
        @backingInt(PixelArtField.palette_max) => value.palette_max = defaults.palette_max,
        @backingInt(PixelArtField.refine_iterations) => value.refine_iterations = defaults.refine_iterations,
        else => return .invalid_argument,
    }
    return .ok;
}

export fn madeitpx_convert_pixelart_rgba8(
    input: ?[*]const u8,
    input_size: usize,
    input_width: u32,
    input_height: u32,
    input_stride: usize,
    target_width: u32,
    target_height: u32,
    options: ?*const Options,
    pixelart_options: ?*const PixelArtOptions,
    output: ?[*]u8,
    output_capacity: usize,
) Status {
    const source = input orelse return .invalid_argument;
    const destination = output orelse return .invalid_argument;
    const config = options orelse return .invalid_argument;
    const detail = pixelart_options orelse return .invalid_argument;
    if (!validOptions(config) or !validPixelArtOptions(detail)) return .invalid_argument;
    const checked = checkBuffers(input_size, input_width, input_height, input_stride, target_width, target_height, output_capacity);
    if (checked.status != .ok) return checked.status;

    if (detail.version == 1) {
        var legacy = config.*;
        legacy.preset = @backingInt(Preset.pixelart);
        return pixelart.convert(source, input_width, input_height, input_stride, target_width, target_height, &legacy, destination);
    }
    return pixelart_v2.convert(source, input_width, input_height, input_stride, target_width, target_height, config.background_rgb, detail, destination);
}

test "version and options initialization" {
    var options: Options = undefined;
    try std.testing.expectEqual(Status.ok, madeitpx_options_init(&options));
    try std.testing.expectEqual(@as(u32, @sizeOf(Options)), options.struct_size);
    try std.testing.expectEqual(@as(u32, 0), options.preset);
    try std.testing.expectEqual(@as(u32, 0), options.palette_colors);
    try std.testing.expectEqual(@as(u32, 0), options.background_rgb);
    try std.testing.expectEqual(@backingInt(SampleMode.nearest), options.sample_mode);
    try std.testing.expectEqual(@as(u32, 1), options.cluster_cleanup);
    try std.testing.expectEqual(@as(u32, 0), options.reserved);
    try std.testing.expectEqual(@as(u32, 0x00010000), madeitpx_version());
}

test "output size uses tightly packed RGBA8" {
    var size: usize = 0;
    try std.testing.expectEqual(Status.ok, madeitpx_get_output_size(3, 2, &size));
    try std.testing.expectEqual(@as(usize, 24), size);
}

test "conversion groups colors into an opaque palette" {
    var options: Options = undefined;
    _ = madeitpx_options_init(&options);
    options.palette_colors = 2;
    options.sample_mode = @backingInt(SampleMode.area);
    const input = [_]u8{
        100, 20, 30, 255,
        104, 20, 30, 255,
        108, 20, 30, 255,
        112, 20, 30, 255,
    };
    var output: [16]u8 = undefined;
    try std.testing.expectEqual(
        Status.ok,
        madeitpx_convert_rgba8(&input, input.len, 4, 1, 16, 4, 1, &options, &output, output.len),
    );
    try std.testing.expectEqualSlices(u8, output[0..4], output[4..8]);
    try std.testing.expectEqualSlices(u8, output[8..12], output[12..16]);
    try std.testing.expect(output[0] != output[8]);
    for (0..4) |index| try std.testing.expectEqual(@as(u8, 255), output[index * 4 + 3]);
}

test "palette generation preserves pixel positions" {
    var options: Options = undefined;
    _ = madeitpx_options_init(&options);
    options.palette_colors = 4;
    const input = [_]u8{
        255, 0, 0,   255, 0,   255, 0,   255,
        0,   0, 255, 255, 255, 255, 255, 255,
    };
    var output: [16]u8 = undefined;
    try std.testing.expectEqual(
        Status.ok,
        madeitpx_convert_rgba8(&input, input.len, 4, 1, 16, 4, 1, &options, &output, output.len),
    );
    try std.testing.expectEqualSlices(u8, &input, &output);
}

test "conversion composites transparent pixels onto the configured background" {
    var options: Options = undefined;
    _ = madeitpx_options_init(&options);
    options.background_rgb = 0x000000;
    options.sample_mode = @backingInt(SampleMode.area);
    const input = [_]u8{ 255, 0, 0, 0, 0, 0, 255, 255 };
    var output: [4]u8 = undefined;
    try std.testing.expectEqual(
        Status.ok,
        madeitpx_convert_rgba8(&input, input.len, 2, 1, 8, 1, 1, &options, &output, output.len),
    );
    try std.testing.expectEqual([_]u8{ 0, 0, 128, 255 }, output);
}

test "fully transparent input becomes the configured opaque color" {
    var options: Options = undefined;
    _ = madeitpx_options_init(&options);
    options.background_rgb = 0x123456;
    const input = [_]u8{ 255, 0, 255, 0 };
    var output: [4]u8 = undefined;
    try std.testing.expectEqual(
        Status.ok,
        madeitpx_convert_rgba8(&input, input.len, 1, 1, 4, 1, 1, &options, &output, output.len),
    );
    try std.testing.expectEqual([_]u8{ 0x12, 0x34, 0x56, 255 }, output);
}

test "conversion validates options and buffer lengths" {
    var options: Options = undefined;
    _ = madeitpx_options_init(&options);
    const input = [_]u8{ 1, 2, 3, 4 };
    var output: [4]u8 = undefined;

    try std.testing.expectEqual(
        Status.buffer_too_small,
        madeitpx_convert_rgba8(&input, 3, 1, 1, 4, 1, 1, &options, &output, output.len),
    );
    try std.testing.expectEqual(
        Status.buffer_too_small,
        madeitpx_convert_rgba8(&input, input.len, 1, 1, 4, 1, 1, &options, &output, 3),
    );
    options.reserved = 1;
    try std.testing.expectEqual(
        Status.invalid_argument,
        madeitpx_convert_rgba8(&input, input.len, 1, 1, 4, 1, 1, &options, &output, output.len),
    );
    options.reserved = 0;
    options.palette_colors = 1;
    try std.testing.expectEqual(
        Status.invalid_argument,
        madeitpx_convert_rgba8(&input, input.len, 1, 1, 4, 1, 1, &options, &output, output.len),
    );
    options.palette_colors = 0;
    options.sample_mode = 2;
    try std.testing.expectEqual(
        Status.invalid_argument,
        madeitpx_convert_rgba8(&input, input.len, 1, 1, 4, 1, 1, &options, &output, output.len),
    );
}

test "pixelart preset is accepted by the public entry point" {
    var options: Options = undefined;
    _ = madeitpx_options_init(&options);
    options.preset = @backingInt(Preset.pixelart);
    var input: [4 * 4 * 4]u8 = undefined;
    for (0..16) |pixel| {
        input[pixel * 4] = 90;
        input[pixel * 4 + 1] = 120;
        input[pixel * 4 + 2] = 150;
        input[pixel * 4 + 3] = 255;
    }
    var output: [2 * 2 * 4]u8 = undefined;
    try std.testing.expectEqual(
        Status.ok,
        madeitpx_convert_rgba8(&input, input.len, 4, 4, 16, 2, 2, &options, &output, output.len),
    );
    for (0..4) |pixel| {
        try std.testing.expectEqualSlices(u8, &[_]u8{ 90, 120, 150, 255 }, output[pixel * 4 .. pixel * 4 + 4]);
    }
    options.preset = 4;
    try std.testing.expectEqual(
        Status.invalid_argument,
        madeitpx_convert_rgba8(&input, input.len, 4, 4, 16, 2, 2, &options, &output, output.len),
    );
}

test "pixelart options init and per-field reset restore defaults" {
    var detail: PixelArtOptions = undefined;
    try std.testing.expectEqual(Status.ok, madeitpx_pixelart_options_init(&detail));
    try std.testing.expectEqual(@as(u32, 2), detail.version);
    try std.testing.expectEqual(@as(u32, 14), detail.color_tolerance);
    detail.version = 1;
    detail.color_tolerance = 90;
    detail.palette_max = 8;
    try std.testing.expectEqual(Status.ok, madeitpx_pixelart_options_reset_field(&detail, @backingInt(PixelArtField.color_tolerance)));
    try std.testing.expectEqual(@as(u32, 14), detail.color_tolerance);
    try std.testing.expectEqual(@as(u32, 1), detail.version);
    try std.testing.expectEqual(@as(u32, 8), detail.palette_max);
    try std.testing.expectEqual(Status.invalid_argument, madeitpx_pixelart_options_reset_field(&detail, 99));
    _ = madeitpx_pixelart_options_init(&detail);
    try std.testing.expectEqual(api.pixelart_defaults, detail);
}

test "pixelart version 1 through the detailed entry matches preset 3" {
    var options: Options = undefined;
    _ = madeitpx_options_init(&options);
    var detail: PixelArtOptions = undefined;
    _ = madeitpx_pixelart_options_init(&detail);
    detail.version = 1;
    var input: [16 * 16 * 4]u8 = undefined;
    for (0..256) |pixel| {
        const dark = (pixel % 16 == 7) or (pixel / 16 == 9);
        const value: u8 = if (dark) 20 else 220;
        @memset(input[pixel * 4 .. pixel * 4 + 3], value);
        input[pixel * 4 + 3] = 255;
    }
    var legacy: [8 * 8 * 4]u8 = undefined;
    var detailed: [8 * 8 * 4]u8 = undefined;
    options.preset = @backingInt(Preset.pixelart);
    try std.testing.expectEqual(Status.ok, madeitpx_convert_rgba8(&input, input.len, 16, 16, 64, 8, 8, &options, &legacy, legacy.len));
    try std.testing.expectEqual(Status.ok, madeitpx_convert_pixelart_rgba8(&input, input.len, 16, 16, 64, 8, 8, &options, &detail, &detailed, detailed.len));
    try std.testing.expectEqualSlices(u8, &legacy, &detailed);
}

test "pixelart detailed entry validates settings and buffers" {
    var options: Options = undefined;
    _ = madeitpx_options_init(&options);
    var detail: PixelArtOptions = undefined;
    _ = madeitpx_pixelart_options_init(&detail);
    const input = [_]u8{ 1, 2, 3, 255 };
    var output: [4]u8 = undefined;
    try std.testing.expectEqual(Status.ok, madeitpx_convert_pixelart_rgba8(&input, input.len, 1, 1, 4, 1, 1, &options, &detail, &output, output.len));
    try std.testing.expectEqualSlices(u8, &input, &output);
    try std.testing.expectEqual(Status.buffer_too_small, madeitpx_convert_pixelart_rgba8(&input, input.len, 1, 1, 4, 1, 1, &options, &detail, &output, 3));
    detail.version = 3;
    try std.testing.expectEqual(Status.invalid_argument, madeitpx_convert_pixelart_rgba8(&input, input.len, 1, 1, 4, 1, 1, &options, &detail, &output, output.len));
    detail.version = 2;
    detail.palette_max = 1;
    try std.testing.expectEqual(Status.invalid_argument, madeitpx_convert_pixelart_rgba8(&input, input.len, 1, 1, 4, 1, 1, &options, &detail, &output, output.len));
}
