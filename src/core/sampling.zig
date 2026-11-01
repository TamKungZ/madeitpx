const std = @import("std");

fn resampleWithSum(
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

pub fn resample(
    source: [*]const u8,
    input_width: u32,
    input_height: u32,
    input_stride: usize,
    target_width: u32,
    target_height: u32,
    destination: [*]u8,
) void {
    const pixel_count = @as(u64, input_width) * input_height;
    if (pixel_count <= std.math.maxInt(u64) / 65025) {
        resampleWithSum(u64, source, input_width, input_height, input_stride, target_width, target_height, destination);
    } else {
        resampleWithSum(u128, source, input_width, input_height, input_stride, target_width, target_height, destination);
    }
}

pub fn nearest(
    source: [*]const u8,
    input_width: u32,
    input_height: u32,
    input_stride: usize,
    target_width: u32,
    target_height: u32,
    destination: [*]u8,
) void {
    const x_denominator: u64 = @as(u64, target_width) * 2;
    const x_increment: u64 = @as(u64, input_width) * 2;
    const y_denominator: u64 = @as(u64, target_height) * 2;
    const y_increment: u64 = @as(u64, input_height) * 2;
    const y_numerator: u64 = input_height;
    var y_remainder = y_numerator % y_denominator;
    var source_y = y_numerator / y_denominator;

    for (0..target_height) |output_y| {
        const x_numerator: u64 = input_width;
        var x_remainder = x_numerator % x_denominator;
        var source_x = x_numerator / x_denominator;
        for (0..target_width) |output_x| {
            const source_index = @as(usize, @intCast(@min(source_y, input_height - 1))) * input_stride +
                @as(usize, @intCast(@min(source_x, input_width - 1))) * 4;
            const destination_index = (output_y * @as(usize, target_width) + output_x) * 4;
            @memcpy(destination[destination_index .. destination_index + 4], source[source_index .. source_index + 4]);

            const x_accumulated = x_remainder + x_increment;
            source_x += x_accumulated / x_denominator;
            x_remainder = x_accumulated % x_denominator;
        }

        const y_accumulated = y_remainder + y_increment;
        source_y += y_accumulated / y_denominator;
        y_remainder = y_accumulated % y_denominator;
    }
}

test "narrow and wide accumulation produce the same pixels" {
    const input = [_]u8{
        255, 0,  0,   255, 0,   255, 0,   128,
        0,   0,  255, 64,  255, 255, 255, 0,
        40,  80, 120, 192, 200, 160, 120, 255,
    };
    var narrow: [8]u8 = undefined;
    var wide: [8]u8 = undefined;
    resampleWithSum(u64, &input, 3, 2, 12, 2, 1, &narrow);
    resampleWithSum(u128, &input, 3, 2, 12, 2, 1, &wide);
    try std.testing.expectEqualSlices(u8, &narrow, &wide);
}

test "nearest sampling matches center mapping for varied image sizes" {
    const input_stride = 64 * 4;
    var input: [input_stride * 53]u8 = undefined;
    for (0..53) |y| {
        for (0..64) |x| {
            const index = y * input_stride + x * 4;
            input[index] = @intCast(x);
            input[index + 1] = @intCast(y);
            input[index + 2] = @truncate(x * 13 + y * 7);
            input[index + 3] = 255;
        }
    }

    const cases = [_][4]u32{
        .{ 7, 11, 13, 17 },
        .{ 31, 27, 14, 9 },
        .{ 64, 53, 83, 91 },
        .{ 1, 53, 71, 1 },
        .{ 64, 1, 1, 88 },
    };
    var output: [83 * 91 * 4]u8 = undefined;
    for (cases) |case| {
        const input_width = case[0];
        const input_height = case[1];
        const target_width = case[2];
        const target_height = case[3];
        nearest(&input, input_width, input_height, input_stride, target_width, target_height, &output);
        for (0..target_height) |y| {
            const expected_y = @min(@as(u32, @intCast(
                (@as(u128, @intCast(y)) * 2 + 1) * input_height / (@as(u128, target_height) * 2),
            )), input_height - 1);
            for (0..target_width) |x| {
                const expected_x = @min(@as(u32, @intCast(
                    (@as(u128, @intCast(x)) * 2 + 1) * input_width / (@as(u128, target_width) * 2),
                )), input_width - 1);
                const output_index = (y * @as(usize, target_width) + x) * 4;
                const input_index = @as(usize, expected_y) * input_stride + @as(usize, expected_x) * 4;
                try std.testing.expectEqualSlices(u8, input[input_index .. input_index + 4], output[output_index .. output_index + 4]);
            }
        }
    }
}
