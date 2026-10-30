const std = @import("std");
const api = @import("api_types.zig");

pub const max_colors = 64;

const Bucket = struct {
    start: usize,
    len: usize,
    minimum: [3]u8,
    maximum: [3]u8,
};

const BucketSplit = struct {
    left: Bucket,
    right: Bucket,
};

pub const Palette = struct {
    colors: [max_colors][3]u8,
    len: usize,
};

pub const PaletteLookup = struct {
    channels: [3][max_colors]u8,
};

fn pixelChannel(pixels: [*]const u8, index: usize, component: usize) u8 {
    return pixels[index * 4 + component];
}

fn bucketBounds(pixels: [*]const u8, indices: []const usize, start: usize, len: usize) Bucket {
    var minimum: [3]u8 = @splat(255);
    var maximum: [3]u8 = @splat(0);
    for (start..start + len) |slot| {
        const index = indices[slot];
        for (0..3) |component| {
            const value = pixelChannel(pixels, index, component);
            minimum[component] = @min(minimum[component], value);
            maximum[component] = @max(maximum[component], value);
        }
    }
    return .{ .start = start, .len = len, .minimum = minimum, .maximum = maximum };
}

fn bucketRange(bucket: Bucket, component: usize) u16 {
    return @as(u16, bucket.maximum[component]) - bucket.minimum[component];
}

fn bucketMean(pixels: [*]const u8, indices: []const usize, bucket: Bucket) [3]u8 {
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

fn splitBucket(pixels: [*]const u8, indices: []usize, bucket: Bucket, component: usize) ?BucketSplit {
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
    const split_below = threshold == bucket.maximum[component];
    for (bucket.start..bucket.start + bucket.len) |slot| {
        const index = indices[slot];
        const value = pixels[index * 4 + component];
        if ((if (split_below) value < threshold else value <= threshold)) {
            std.mem.swap(usize, &indices[split], &indices[slot]);
            split += 1;
        }
    }
    if (split == bucket.start or split == bucket.start + bucket.len) return null;
    const left_len = split - bucket.start;
    return .{
        .left = bucketBounds(pixels, indices, bucket.start, left_len),
        .right = bucketBounds(pixels, indices, split, bucket.len - left_len),
    };
}

pub fn paletteLookup(palette: []const [3]u8) PaletteLookup {
    var lookup: PaletteLookup = .{ .channels = @splat(@splat(0)) };
    for (palette, 0..) |color, index| {
        for (0..3) |component| lookup.channels[component][index] = color[component];
    }
    return lookup;
}

fn colorDistance(pixels: [*]const u8, index: usize, color: [3]u8) u32 {
    const red = @as(i32, pixelChannel(pixels, index, 0)) - color[0];
    const green = @as(i32, pixelChannel(pixels, index, 1)) - color[1];
    const blue = @as(i32, pixelChannel(pixels, index, 2)) - color[2];
    return @intCast(3 * red * red + 4 * green * green + 2 * blue * blue);
}

pub fn nearestColorLinear(pixels: [*]const u8, index: usize, palette: []const [3]u8) usize {
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

pub fn nearestColor(pixels: [*]const u8, index: usize, palette_len: usize, lookup: *const PaletteLookup) usize {
    if (palette_len <= 8) {
        const red = @as(i32, pixelChannel(pixels, index, 0));
        const green = @as(i32, pixelChannel(pixels, index, 1));
        const blue = @as(i32, pixelChannel(pixels, index, 2));
        var best_index: usize = 0;
        var best_distance: u32 = std.math.maxInt(u32);
        for (0..palette_len) |palette_index| {
            const red_diff = red - lookup.channels[0][palette_index];
            const green_diff = green - lookup.channels[1][palette_index];
            const blue_diff = blue - lookup.channels[2][palette_index];
            const distance: u32 = @intCast(
                3 * red_diff * red_diff + 4 * green_diff * green_diff + 2 * blue_diff * blue_diff,
            );
            if (distance == 0) return palette_index;
            if (distance < best_distance) {
                best_distance = distance;
                best_index = palette_index;
            }
        }
        return best_index;
    }

    const Bytes = @Vector(8, u8);
    const Distances = @Vector(8, i32);
    const red_pixel: Distances = @splat(@as(i32, pixelChannel(pixels, index, 0)));
    const green_pixel: Distances = @splat(@as(i32, pixelChannel(pixels, index, 1)));
    const blue_pixel: Distances = @splat(@as(i32, pixelChannel(pixels, index, 2)));
    var best_index: usize = 0;
    var best_distance: u32 = std.math.maxInt(u32);
    var base: usize = 0;
    while (base < palette_len) : (base += 8) {
        const red_bytes = @as(*align(1) const Bytes, @ptrCast(&lookup.channels[0][base])).*;
        const green_bytes = @as(*align(1) const Bytes, @ptrCast(&lookup.channels[1][base])).*;
        const blue_bytes = @as(*align(1) const Bytes, @ptrCast(&lookup.channels[2][base])).*;
        const red_diff = red_pixel - @as(Distances, @intCast(red_bytes));
        const green_diff = green_pixel - @as(Distances, @intCast(green_bytes));
        const blue_diff = blue_pixel - @as(Distances, @intCast(blue_bytes));
        var distances = red_diff * red_diff * @as(Distances, @splat(3)) +
            green_diff * green_diff * @as(Distances, @splat(4)) +
            blue_diff * blue_diff * @as(Distances, @splat(2));
        inline for (0..8) |lane| {
            if (base + lane >= palette_len) distances[lane] = std.math.maxInt(i32);
        }
        const group_minimum = @reduce(.Min, distances);
        const group_minimum_u32: u32 = @intCast(group_minimum);
        if (group_minimum_u32 < best_distance) {
            best_distance = group_minimum_u32;
            inline for (0..8) |lane| {
                const palette_index = base + lane;
                if (palette_index < palette_len and distances[lane] == group_minimum) {
                    best_index = palette_index;
                    break;
                }
            }
            if (best_distance == 0) return best_index;
        }
    }
    return best_index;
}

fn paletteLimit(options: *const api.Options) usize {
    if (options.palette_colors != 0) return options.palette_colors;
    return switch (options.preset) {
        0 => 32,
        1 => 64,
        2 => 16,
        3 => 16,
        else => unreachable,
    };
}

pub fn buildPalette(pixels: [*]u8, pixel_count: usize, limit: usize, indices: []usize) Palette {
    var buckets: [max_colors]Bucket = undefined;
    var palette: [max_colors][3]u8 = undefined;
    var unique_colors: [max_colors][3]u8 = undefined;
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
    if (!exceeds_limit) return .{ .colors = unique_colors, .len = unique_count };

    for (indices, 0..) |*index, value| index.* = value;
    var bucket_count: usize = 1;
    buckets[0] = bucketBounds(pixels, indices, 0, pixel_count);

    while (bucket_count < @min(limit, pixel_count)) {
        var selected: ?usize = null;
        var selected_component: usize = 0;
        var selected_score: u128 = 0;

        for (buckets[0..bucket_count], 0..) |bucket, bucket_index| {
            if (bucket.len < 2) continue;
            var component: usize = 0;
            var range = bucketRange(bucket, 0);
            for (1..3) |candidate| {
                const candidate_range = bucketRange(bucket, candidate);
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
        const split = splitBucket(pixels, indices, buckets[selected_index], selected_component) orelse break;
        buckets[selected_index] = split.left;
        buckets[bucket_count] = split.right;
        bucket_count += 1;
    }

    for (buckets[0..bucket_count], 0..) |bucket, index| {
        palette[index] = bucketMean(pixels, indices, bucket);
    }
    return .{ .colors = palette, .len = bucket_count };
}

pub fn colorDistanceBetween(a: [3]u8, b: [3]u8) u32 {
    const red = @as(i32, a[0]) - b[0];
    const green = @as(i32, a[1]) - b[1];
    const blue = @as(i32, a[2]) - b[2];
    return @intCast(3 * red * red + 4 * green * green + 2 * blue * blue);
}

pub fn refineClusterLabels(
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
            var counts: [max_colors]u8 = @splat(0);

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

pub fn compositeAndQuantize(
    pixels: [*]u8,
    pixel_count: usize,
    options: *const api.Options,
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
    const lookup = paletteLookup(palette.colors[0..palette.len]);
    for (0..pixel_count) |pixel_index| {
        pixels[pixel_index * 4 + 3] = @intCast(nearestColor(pixels, pixel_index, palette.len, &lookup));
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

test "cluster cleanup matches full neighborhood histogram" {
    const width = 13;
    const height = 11;
    var labels: [width * height * 4]u8 = undefined;
    var refined: [width * height]usize = undefined;
    var palette = Palette{
        .colors = @splat(.{ 0, 0, 0 }),
        .len = 16,
    };
    for (0..palette.len) |index| {
        const value: u32 = @intCast(index);
        palette.colors[index] = .{
            @truncate(value *% 17 +% 31),
            @truncate(value *% 37 +% 11),
            @truncate(value *% 53 +% 7),
        };
    }
    for (0..width * height) |pixel_index| {
        const value: u32 = @intCast(pixel_index);
        labels[pixel_index * 4 + 3] = @truncate((value *% 29 +% value / 3) % palette.len);
    }

    refineClusterLabels(&labels, width, height, palette, &refined);
    for (0..height) |y| {
        for (0..width) |x| {
            const pixel_index = y * width + x;
            const current = labels[pixel_index * 4 + 3];
            var counts: [max_colors]u8 = @splat(0);
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
            const expected = if (candidate_count >= 4 and candidate_count > counts[current] and
                colorDistanceBetween(palette.colors[current], palette.colors[candidate]) <= 20000)
                candidate
            else
                current;
            try std.testing.expectEqual(expected, refined[pixel_index]);
        }
    }
}

test "vector palette search matches exhaustive nearest-color selection" {
    var colors: [max_colors][3]u8 = undefined;
    for (0..colors.len) |index| {
        const value: u32 = @intCast(index);
        colors[index] = .{
            @truncate(value *% 73 +% 19),
            @truncate(value *% 151 +% 47),
            @truncate(value *% 199 +% 83),
        };
    }
    colors[1] = colors[0];

    var pixels: [1024 * 4]u8 = undefined;
    for (0..1024) |index| {
        const value: u32 = @intCast(index);
        pixels[index * 4] = @truncate(value *% 31 +% 7);
        pixels[index * 4 + 1] = @truncate(value *% 101 +% 13);
        pixels[index * 4 + 2] = @truncate(value *% 173 +% 29);
        pixels[index * 4 + 3] = 255;
    }

    for (1..max_colors + 1) |palette_len| {
        const lookup = paletteLookup(colors[0..palette_len]);
        for (0..1024) |pixel_index| {
            try std.testing.expectEqual(
                nearestColorLinear(&pixels, pixel_index, colors[0..palette_len]),
                nearestColor(&pixels, pixel_index, palette_len, &lookup),
            );
        }
    }
}

test "palette splitting handles a dominant maximum-channel color" {
    var pixels: [73 * 4]u8 = undefined;
    for (0..40) |index| {
        const offset = index * 4;
        pixels[offset] = 250;
        pixels[offset + 1] = 250;
        pixels[offset + 2] = 240;
        pixels[offset + 3] = 255;
    }
    for (0..33) |index| {
        const value: u8 = @intCast(index + 1);
        const offset = (index + 40) * 4;
        pixels[offset] = value;
        pixels[offset + 1] = value + 1;
        pixels[offset + 2] = value + 2;
        pixels[offset + 3] = 255;
    }

    var indices: [73]usize = undefined;
    const palette = buildPalette(&pixels, pixels.len / 4, 32, &indices);
    try std.testing.expect(palette.len > 1);
    try std.testing.expect(palette.len <= 32);
}
