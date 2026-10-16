const std = @import("std");

pub const Status = enum(c_int) {
    ok = 0,
    invalid_argument = 1,
    buffer_too_small = 2,
    size_overflow = 3,
};

pub const Options = extern struct {
    struct_size: u32,
    reserved: u32,
};

pub const abi_version: u32 = 0x00010000;

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
    return options.struct_size >= @sizeOf(Options) and options.reserved == 0;
}

fn rgbaSize(width: u32, height: u32) ?usize {
    const pixels = checkedMul(@as(usize, width), @as(usize, height)) orelse return null;
    return checkedMul(pixels, 4);
}

fn resample(
    comptime Sum: type,
    source: [*]const u8,
    input_width: u32,
    input_height: u32,
    input_stride: usize,
    target_width: u32,
    target_height: u32,
    destination: [*]u8,
) void {
    const source_width: u64 = input_width;
    const source_height: u64 = input_height;
    const destination_width: u64 = target_width;
    const destination_height: u64 = target_height;

    for (0..target_height) |output_y| {
        const y_start = @as(u64, @intCast(output_y)) * source_height;
        const y_end = (@as(u64, @intCast(output_y)) + 1) * source_height;
        const first_y = y_start / destination_height;
        const last_y = (y_end + destination_height - 1) / destination_height;

        for (0..target_width) |output_x| {
            const x_start = @as(u64, @intCast(output_x)) * source_width;
            const x_end = (@as(u64, @intCast(output_x)) + 1) * source_width;
            const first_x = x_start / destination_width;
            const last_x = (x_end + destination_width - 1) / destination_width;
            var color_sums = [_]Sum{ 0, 0, 0 };
            var alpha_sum: Sum = 0;
            var total_weight: Sum = 0;

            var source_y = first_y;
            while (source_y < last_y) : (source_y += 1) {
                const overlap_y = @min((source_y + 1) * destination_height, y_end) -
                    @max(source_y * destination_height, y_start);
                var source_x = first_x;
                while (source_x < last_x) : (source_x += 1) {
                    const overlap_x = @min((source_x + 1) * destination_width, x_end) -
                        @max(source_x * destination_width, x_start);
                    const weight: Sum = @as(Sum, @intCast(overlap_x)) * @as(Sum, @intCast(overlap_y));
                    const source_index = @as(usize, @intCast(source_y)) * input_stride +
                        @as(usize, @intCast(source_x)) * 4;
                    const alpha: Sum = source[source_index + 3];
                    alpha_sum += alpha * weight;
                    for (0..3) |channel| {
                        color_sums[channel] += @as(Sum, source[source_index + channel]) * alpha * weight;
                    }
                    total_weight += weight;
                }
            }

            const destination_index = (output_y * @as(usize, target_width) + output_x) * 4;
            destination[destination_index + 3] = @intCast((alpha_sum + total_weight / 2) / total_weight);
            for (0..3) |channel| {
                destination[destination_index + channel] = if (alpha_sum == 0)
                    0
                else
                    @intCast((color_sums[channel] + alpha_sum / 2) / alpha_sum);
            }
        }
    }
}

export fn madeitpx_version() u32 {
    return abi_version;
}

export fn madeitpx_options_init(options: ?*Options) Status {
    const value = options orelse return .invalid_argument;
    value.* = .{
        .struct_size = @sizeOf(Options),
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
    if (!validOptions(config) or input_width == 0 or input_height == 0 or
        target_width == 0 or target_height == 0)
        return .invalid_argument;

    const source_row_size = checkedMul(@as(usize, input_width), 4) orelse return .size_overflow;
    if (input_stride < source_row_size) return .invalid_argument;
    const source_offset = checkedMul(@as(usize, input_height - 1), input_stride) orelse return .size_overflow;
    const required_input_size = checkedAdd(source_offset, source_row_size) orelse return .size_overflow;
    if (input_size < required_input_size) return .buffer_too_small;

    const required_output_size = rgbaSize(target_width, target_height) orelse return .size_overflow;
    if (output_capacity < required_output_size) return .buffer_too_small;

    const pixel_count = @as(u64, input_width) * input_height;
    if (pixel_count <= std.math.maxInt(u64) / 65025) {
        resample(u64, source, input_width, input_height, input_stride, target_width, target_height, destination);
    } else {
        resample(u128, source, input_width, input_height, input_stride, target_width, target_height, destination);
    }
    return .ok;
}

test "version and options initialization" {
    var options: Options = undefined;
    try std.testing.expectEqual(Status.ok, madeitpx_options_init(&options));
    try std.testing.expectEqual(@as(u32, @sizeOf(Options)), options.struct_size);
    try std.testing.expectEqual(@as(u32, 0), options.reserved);
    try std.testing.expectEqual(@as(u32, 0x00010000), madeitpx_version());
}

test "output size uses tightly packed RGBA8" {
    var size: usize = 0;
    try std.testing.expectEqual(Status.ok, madeitpx_get_output_size(3, 2, &size));
    try std.testing.expectEqual(@as(usize, 24), size);
}

test "conversion area averages colors and preserves alpha" {
    var options: Options = undefined;
    _ = madeitpx_options_init(&options);
    const input = [_]u8{ 255, 0, 0, 255, 0, 0, 255, 255 };
    var output: [4]u8 = undefined;
    try std.testing.expectEqual(
        Status.ok,
        madeitpx_convert_rgba8(&input, input.len, 2, 1, 8, 1, 1, &options, &output, output.len),
    );
    try std.testing.expectEqual([_]u8{ 128, 0, 128, 255 }, output);
}

test "conversion resamples transparent colors without fringes" {
    var options: Options = undefined;
    _ = madeitpx_options_init(&options);
    const input = [_]u8{ 255, 0, 0, 0, 0, 0, 255, 255 };
    var output: [4]u8 = undefined;
    try std.testing.expectEqual(
        Status.ok,
        madeitpx_convert_rgba8(&input, input.len, 2, 1, 8, 1, 1, &options, &output, output.len),
    );
    try std.testing.expectEqual([_]u8{ 0, 0, 255, 128 }, output);
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
}

test "narrow and wide accumulation produce the same pixels" {
    const input = [_]u8{
        255, 0,  0,   255, 0,   255, 0,   128,
        0,   0,  255, 64,  255, 255, 255, 0,
        40,  80, 120, 192, 200, 160, 120, 255,
    };
    var narrow: [8]u8 = undefined;
    var wide: [8]u8 = undefined;
    resample(u64, &input, 3, 2, 12, 2, 1, &narrow);
    resample(u128, &input, 3, 2, 12, 2, 1, &wide);
    try std.testing.expectEqualSlices(u8, &narrow, &wide);
}
