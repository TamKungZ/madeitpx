const std = @import("std");

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
const max_palette_colors = 64;

const PaletteBucket = struct {
    start: usize,
    len: usize,
};

const Palette = struct {
    colors: [max_palette_colors][3]u8,
    len: usize,
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

fn validOptions(options: *const Options) bool {
    return options.struct_size >= @sizeOf(Options) and
        options.reserved == 0 and
        (options.palette_colors == 0 or (options.palette_colors >= 2 and options.palette_colors <= max_palette_colors)) and
        options.preset <= @backingInt(Preset.bold) and
        options.sample_mode <= @backingInt(SampleMode.nearest) and
        options.cluster_cleanup <= 1;
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

fn sampleNearest(
    source: [*]const u8,
    input_width: u32,
    input_height: u32,
    input_stride: usize,
    target_width: u32,
    target_height: u32,
    destination: [*]u8,
) void {
    for (0..target_height) |output_y| {
        const source_y = @min(@as(u32, @intCast(
            (@as(u128, @intCast(output_y)) * 2 + 1) * input_height / (@as(u128, target_height) * 2),
        )), input_height - 1);
        for (0..target_width) |output_x| {
            const source_x = @min(@as(u32, @intCast(
                (@as(u128, @intCast(output_x)) * 2 + 1) * input_width / (@as(u128, target_width) * 2),
            )), input_width - 1);
            const source_index = @as(usize, @intCast(source_y)) * input_stride +
                @as(usize, @intCast(source_x)) * 4;
            const destination_index = (output_y * @as(usize, target_width) + output_x) * 4;
            @memcpy(destination[destination_index .. destination_index + 4], source[source_index .. source_index + 4]);
        }
    }
}

fn paletteLimit(options: *const Options) usize {
    if (options.palette_colors != 0) return options.palette_colors;
    return switch (options.preset) {
        0 => 32,
        1 => 64,
        2 => 16,
        else => unreachable,
    };
}

fn pixelChannel(pixel: [*]const u8, index: usize, component: usize) u8 {
    return pixel[index * 4 + component];
}

fn colorRange(pixels: [*]const u8, indices: []const usize, bucket: PaletteBucket, component: usize) u16 {
    var minimum: u8 = 255;
    var maximum: u8 = 0;
    for (bucket.start..bucket.start + bucket.len) |slot| {
        const index = indices[slot];
        minimum = @min(minimum, pixelChannel(pixels, index, component));
        maximum = @max(maximum, pixelChannel(pixels, index, component));
    }
    return @as(u16, maximum) - minimum;
}

fn bucketMean(pixels: [*]const u8, indices: []const usize, bucket: PaletteBucket) [3]u8 {
    var sums = [_]u128{ 0, 0, 0 };
    for (bucket.start..bucket.start + bucket.len) |slot| {
        const index = indices[slot];
        for (0..3) |component| sums[component] += pixelChannel(pixels, index, component);
    }
    return .{
        @intCast((sums[0] + bucket.len / 2) / bucket.len),
        @intCast((sums[1] + bucket.len / 2) / bucket.len),
        @intCast((sums[2] + bucket.len / 2) / bucket.len),
    };
}

fn splitBucket(pixels: [*]const u8, indices: []usize, bucket: PaletteBucket, component: usize) ?usize {
    var histogram: [256]usize = @splat(0);
    for (bucket.start..bucket.start + bucket.len) |slot| {
        const index = indices[slot];
        histogram[pixels[index * 4 + component]] += 1;
    }

    var accumulated: usize = 0;
    var threshold: usize = 0;
    for (histogram, 0..) |count, value| {
        accumulated += count;
        if (accumulated >= (bucket.len + 1) / 2) {
            threshold = value;
            break;
        }
    }

    var split = bucket.start;
    const split_below = threshold == 255;
    for (bucket.start..bucket.start + bucket.len) |slot| {
        const index = indices[slot];
        const value = pixels[index * 4 + component];
        if ((if (split_below) value < threshold else value <= threshold)) {
            std.mem.swap(usize, &indices[split], &indices[slot]);
            split += 1;
        }
    }
    if (split == bucket.start or split == bucket.start + bucket.len) return null;
    return split - bucket.start;
}

fn colorDistance(pixel: [*]const u8, index: usize, color: [3]u8) u32 {
    const red = @as(i32, pixelChannel(pixel, index, 0)) - color[0];
    const green = @as(i32, pixelChannel(pixel, index, 1)) - color[1];
    const blue = @as(i32, pixelChannel(pixel, index, 2)) - color[2];
    return @intCast(3 * red * red + 4 * green * green + 2 * blue * blue);
}

fn nearestColor(pixels: [*]const u8, index: usize, palette: []const [3]u8) usize {
    var best_index: usize = 0;
    var best_distance: u32 = std.math.maxInt(u32);
    for (palette, 0..) |color, palette_index| {
        const distance = colorDistance(pixels, index, color);
        if (distance < best_distance) {
            best_distance = distance;
            best_index = palette_index;
        }
    }
    return best_index;
}

fn buildPalette(pixels: [*]u8, pixel_count: usize, limit: usize, indices: []usize) Palette {
    var buckets: [max_palette_colors]PaletteBucket = undefined;
    var palette: [max_palette_colors][3]u8 = undefined;
    var unique_colors: [max_palette_colors][3]u8 = undefined;
    var unique_count: usize = 0;
    var exceeds_limit = false;

    for (0..pixel_count) |pixel_index| {
        const color = [3]u8{
            pixelChannel(pixels, pixel_index, 0),
            pixelChannel(pixels, pixel_index, 1),
            pixelChannel(pixels, pixel_index, 2),
        };
        var found = false;
        for (unique_colors[0..unique_count]) |known_color| {
            if (std.mem.eql(u8, &known_color, &color)) {
                found = true;
                break;
            }
        }
        if (found) continue;
        if (unique_count == limit) {
            exceeds_limit = true;
            break;
        }
        unique_colors[unique_count] = color;
        unique_count += 1;
    }
    if (!exceeds_limit) {
        return .{ .colors = unique_colors, .len = unique_count };
    }

    var bucket_count: usize = 1;
    buckets[0] = .{ .start = 0, .len = pixel_count };
    for (indices, 0..) |*index, value| index.* = value;

    while (bucket_count < @min(limit, pixel_count)) {
        var selected: ?usize = null;
        var selected_component: usize = 0;
        var selected_score: u128 = 0;

        for (buckets[0..bucket_count], 0..) |bucket, bucket_index| {
            if (bucket.len < 2) continue;
            var component: usize = 0;
            var range = colorRange(pixels, indices, bucket, 0);
            for (1..3) |candidate| {
                const candidate_range = colorRange(pixels, indices, bucket, candidate);
                if (candidate_range > range) {
                    range = candidate_range;
                    component = candidate;
                }
            }
            if (range == 0) continue;
            const score = @as(u128, range) * bucket.len;
            if (selected == null or score > selected_score) {
                selected = bucket_index;
                selected_component = component;
                selected_score = score;
            }
        }

        const selected_index = selected orelse break;
        const bucket = buckets[selected_index];
        const left_len = splitBucket(pixels, indices, bucket, selected_component) orelse break;
        buckets[selected_index].len = left_len;
        buckets[bucket_count] = .{
            .start = bucket.start + left_len,
            .len = bucket.len - left_len,
        };
        bucket_count += 1;
    }

    for (buckets[0..bucket_count], 0..) |bucket, index| {
        palette[index] = bucketMean(pixels, indices, bucket);
    }

    return .{ .colors = palette, .len = bucket_count };
}

fn colorDistanceBetween(a: [3]u8, b: [3]u8) u32 {
    const red = @as(i32, a[0]) - b[0];
    const green = @as(i32, a[1]) - b[1];
    const blue = @as(i32, a[2]) - b[2];
    return @intCast(3 * red * red + 4 * green * green + 2 * blue * blue);
}

fn refineClusterLabels(
    labels: [*]const u8,
    width: u32,
    height: u32,
    palette: Palette,
    refined: []usize,
) void {
    for (0..height) |y| {
        for (0..width) |x| {
            const pixel_index = y * @as(usize, width) + x;
            const current = labels[pixel_index * 4 + 3];
            var counts: [max_palette_colors]u8 = @splat(0);

            for (0..3) |row| {
                const neighbor_y = @as(i64, @intCast(y)) + @as(i64, @intCast(row)) - 1;
                if (neighbor_y < 0 or neighbor_y >= height) continue;
                for (0..3) |column| {
                    if (row == 1 and column == 1) continue;
                    const neighbor_x = @as(i64, @intCast(x)) + @as(i64, @intCast(column)) - 1;
                    if (neighbor_x < 0 or neighbor_x >= width) continue;
                    const neighbor_index = @as(usize, @intCast(neighbor_y)) * width +
                        @as(usize, @intCast(neighbor_x));
                    counts[labels[neighbor_index * 4 + 3]] += 1;
                }
            }

            var candidate: usize = current;
            var candidate_count: u8 = 0;
            for (0..palette.len) |palette_index| {
                if (counts[palette_index] > candidate_count) {
                    candidate = palette_index;
                    candidate_count = counts[palette_index];
                }
            }

            refined[pixel_index] = if (candidate_count >= 4 and candidate_count > counts[current] and
                colorDistanceBetween(palette.colors[current], palette.colors[candidate]) <= 20000)
                candidate
            else
                current;
        }
    }
}

fn compositeAndQuantize(
    pixels: [*]u8,
    pixel_count: usize,
    options: *const Options,
    width: u32,
    height: u32,
    indices: []usize,
) void {
    const matte = [_]u8{
        @truncate(options.background_rgb >> 16),
        @truncate(options.background_rgb >> 8),
        @truncate(options.background_rgb),
    };

    for (0..pixel_count) |index| {
        const alpha = pixels[index * 4 + 3];
        for (0..3) |component| {
            const source = @as(u32, pixels[index * 4 + component]) * alpha;
            const background = @as(u32, matte[component]) * (255 - alpha);
            pixels[index * 4 + component] = @intCast((source + background + 127) / 255);
        }
        pixels[index * 4 + 3] = 255;
    }

    const palette = buildPalette(pixels, pixel_count, paletteLimit(options), indices);
    for (0..pixel_count) |pixel_index| {
        pixels[pixel_index * 4 + 3] = @intCast(nearestColor(pixels, pixel_index, palette.colors[0..palette.len]));
    }
    if (options.cluster_cleanup == 1) {
        refineClusterLabels(pixels, width, height, palette, indices);
    } else {
        for (0..pixel_count) |pixel_index| indices[pixel_index] = pixels[pixel_index * 4 + 3];
    }
    for (0..pixel_count) |pixel_index| {
        const color = palette.colors[indices[pixel_index]];
        @memcpy(pixels[pixel_index * 4 .. pixel_index * 4 + 3], &color);
        pixels[pixel_index * 4 + 3] = 255;
    }
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
    const output_pixel_count = required_output_size / 4;
    const indices = std.heap.page_allocator.alloc(usize, output_pixel_count) catch return .out_of_memory;
    defer std.heap.page_allocator.free(indices);

    if (config.sample_mode == @backingInt(SampleMode.nearest)) {
        sampleNearest(source, input_width, input_height, input_stride, target_width, target_height, destination);
    } else {
        const pixel_count = @as(u64, input_width) * input_height;
        if (pixel_count <= std.math.maxInt(u64) / 65025) {
            resample(u64, source, input_width, input_height, input_stride, target_width, target_height, destination);
        } else {
            resample(u128, source, input_width, input_height, input_stride, target_width, target_height, destination);
        }
    }
    compositeAndQuantize(destination, output_pixel_count, config, target_width, target_height, indices);
    return .ok;
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

test "cluster cleanup removes similar isolated pixels but keeps high contrast" {
    var labels: [36]u8 = @splat(0);
    labels[4 * 4 + 3] = 1;
    var refined: [9]usize = undefined;
    var palette = Palette{
        .colors = @splat(.{ 100, 100, 100 }),
        .len = 2,
    };
    palette.colors[1] = .{ 110, 110, 110 };
    refineClusterLabels(&labels, 3, 3, palette, &refined);
    try std.testing.expectEqual(@as(usize, 0), refined[4]);

    palette.colors[1] = .{ 255, 255, 255 };
    refineClusterLabels(&labels, 3, 3, palette, &refined);
    try std.testing.expectEqual(@as(usize, 1), refined[4]);
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
