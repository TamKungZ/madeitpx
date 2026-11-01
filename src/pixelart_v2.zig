const std = @import("std");

const api = @import("api_types.zig");

const Rgb = [3]u8;

const max_palette: usize = 256;
const bin_shift: u3 = 3;
const bin_side: usize = 256 >> bin_shift;
const bin_count: usize = bin_side * bin_side * bin_side;
const period_step_permille: f64 = 0.5;
const phase_step: f64 = 0.1;

const Source = struct {
    pixels: [*]const u8,
    stride: usize,
    matte: Rgb,

    fn at(self: Source, x: usize, y: usize) Rgb {
        const base = y * self.stride + x * 4;
        const alpha: u32 = self.pixels[base + 3];
        var color: Rgb = undefined;
        for (0..3) |channel| {
            const foreground = @as(u32, self.pixels[base + channel]) * alpha;
            const background = @as(u32, self.matte[channel]) * (255 - alpha);
            color[channel] = @intCast((foreground + background + 127) / 255);
        }
        return color;
    }
};

const Axis = struct {
    period: f64,
    offset: f64,

    fn start(self: Axis, cell: usize) f64 {
        return self.offset + @as(f64, @floatFromInt(cell)) * self.period;
    }
};

fn sqDistance(a: Rgb, b: Rgb) u32 {
    var total: u32 = 0;
    for (0..3) |channel| {
        const delta = @as(i32, a[channel]) - @as(i32, b[channel]);
        total += @intCast(delta * delta);
    }
    return total;
}

fn channelDelta(a: Rgb, b: Rgb) u32 {
    var total: u32 = 0;
    for (0..3) |channel| total += @abs(@as(i32, a[channel]) - @as(i32, b[channel]));
    return total;
}

fn edgeProfile(source: Source, width: u32, height: u32, horizontal: bool, profile: []f64) void {
    const along: usize = if (horizontal) width else height;
    const across: usize = if (horizontal) height else width;
    for (0..along - 1) |i| {
        var sum: u64 = 0;
        for (0..across) |j| {
            const first = if (horizontal) source.at(i, j) else source.at(j, i);
            const second = if (horizontal) source.at(i + 1, j) else source.at(j, i + 1);
            sum += channelDelta(first, second);
        }
        profile[i] = @floatFromInt(sum);
    }
}

fn boundaryScore(profile: []const f64, cells: u32, period: f64, offset: f64) f64 {
    var sum: f64 = 0;
    var used: f64 = 0;
    for (1..cells) |k| {
        const x = offset + @as(f64, @floatFromInt(k)) * period;
        const index = @floor(x - 0.5);
        if (index < 0 or index >= @as(f64, @floatFromInt(profile.len))) continue;
        sum += profile[@intFromFloat(index)];
        used += 1;
    }
    if (used == 0) return 0;
    return sum / used;
}

fn fitAxis(profile: []const f64, cells: u32, size: u32, options: *const api.PixelArtOptions) Axis {
    const nominal = @as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(cells));
    var best = Axis{ .period = nominal, .offset = 0 };
    if (options.grid_fit == 0 or cells < 2 or size < 3) return best;

    var best_score = boundaryScore(profile, cells, nominal, 0);
    const spread = nominal * @as(f64, @floatFromInt(options.grid_search_permille)) / 1000.0;
    const step = @max(nominal * period_step_permille / 1000.0, 1e-6);
    const steps: usize = @intFromFloat(@ceil(spread / step));
    var index: usize = 0;
    while (index <= 2 * steps) : (index += 1) {
        const period = nominal - spread + @as(f64, @floatFromInt(index)) * step;
        if (period <= 0) continue;
        var offset = -period / 2.0;
        while (offset < period / 2.0) : (offset += phase_step) {
            const score = boundaryScore(profile, cells, period, offset);
            if (score > best_score) {
                best_score = score;
                best = .{ .period = period, .offset = offset };
            }
        }
    }
    return best;
}

fn pixelRange(lo: f64, hi: f64, size: usize) [2]usize {
    const first_float = @max(@ceil(lo - 0.5), 0.0);
    const last_float = @min(@floor(hi - 0.5), @as(f64, @floatFromInt(size - 1)));
    if (first_float > last_float) {
        const mid = std.math.clamp((lo + hi) / 2.0 - 0.5, 0.0, @as(f64, @floatFromInt(size - 1)));
        const nearest: usize = @intFromFloat(@round(mid));
        return .{ nearest, nearest + 1 };
    }
    return .{ @intFromFloat(first_float), @as(usize, @intFromFloat(last_float)) + 1 };
}

fn medianOf(histogram: *const [256]u32, count: u32) u8 {
    const target = (count + 1) / 2;
    var seen: u32 = 0;
    for (0..256) |value| {
        seen += histogram[value];
        if (seen >= target) return @intCast(value);
    }
    return 255;
}

fn sampleCells(
    source: Source,
    input_width: u32,
    input_height: u32,
    grid_x: Axis,
    grid_y: Axis,
    target_width: u32,
    target_height: u32,
    inset_percent: u32,
    cells: []Rgb,
) void {
    const inset = @as(f64, @floatFromInt(inset_percent)) / 100.0;
    for (0..target_height) |cy| {
        const y_lo = grid_y.start(cy);
        const y_hi = grid_y.start(cy + 1);
        const rows = pixelRange(y_lo + (y_hi - y_lo) * inset, y_hi - (y_hi - y_lo) * inset, input_height);
        for (0..target_width) |cx| {
            const x_lo = grid_x.start(cx);
            const x_hi = grid_x.start(cx + 1);
            const columns = pixelRange(x_lo + (x_hi - x_lo) * inset, x_hi - (x_hi - x_lo) * inset, input_width);

            var histograms: [3][256]u32 = undefined;
            for (&histograms) |*histogram| @memset(histogram, 0);
            var count: u32 = 0;
            for (rows[0]..rows[1]) |y| {
                for (columns[0]..columns[1]) |x| {
                    const color = source.at(x, y);
                    for (0..3) |channel| histograms[channel][color[channel]] += 1;
                    count += 1;
                }
            }
            var median: Rgb = undefined;
            for (0..3) |channel| median[channel] = medianOf(&histograms[channel], count);
            cells[cy * target_width + cx] = median;
        }
    }
}

const BinEntry = struct {
    count: u32,
    index: u32,
};

fn binGreater(_: void, a: BinEntry, b: BinEntry) bool {
    if (a.count != b.count) return a.count > b.count;
    return a.index < b.index;
}

fn nearestCentre(centres: []const Rgb, color: Rgb) usize {
    var best: usize = 0;
    var best_distance: u32 = std.math.maxInt(u32);
    for (centres, 0..) |centre, position| {
        const d = sqDistance(color, centre);
        if (d < best_distance) {
            best_distance = d;
            best = position;
        }
    }
    return best;
}

fn leaders(allocator: std.mem.Allocator, cells: []const Rgb, tolerance: u32, centres: *[max_palette]Rgb) !usize {
    const counts = try allocator.alloc(u32, bin_count);
    defer allocator.free(counts);
    const sums = try allocator.alloc([3]u32, bin_count);
    defer allocator.free(sums);
    @memset(counts, 0);
    @memset(sums, .{ 0, 0, 0 });

    for (cells) |color| {
        const bin = (@as(usize, color[0] >> bin_shift) * bin_side + (color[1] >> bin_shift)) * bin_side + (color[2] >> bin_shift);
        counts[bin] += 1;
        for (0..3) |channel| sums[bin][channel] += color[channel];
    }

    var order = try std.ArrayList(BinEntry).initCapacity(allocator, 0);
    defer order.deinit(allocator);
    for (0..bin_count) |bin| {
        if (counts[bin] != 0) try order.append(allocator, .{ .count = counts[bin], .index = @intCast(bin) });
    }
    std.mem.sort(BinEntry, order.items, {}, binGreater);

    const limit_sq = tolerance * tolerance;
    var length: usize = 0;
    for (order.items) |entry| {
        const bin = entry.index;
        var color: Rgb = undefined;
        for (0..3) |channel| color[channel] = @intCast((sums[bin][channel] + entry.count / 2) / entry.count);
        if (length > 0) {
            const nearest = nearestCentre(centres[0..length], color);
            if (sqDistance(color, centres[nearest]) <= limit_sq) continue;
        }
        if (length == max_palette) break;
        centres[length] = color;
        length += 1;
    }
    return length;
}

fn assign(cells: []const Rgb, centres: []const Rgb, labels: []u8) void {
    for (cells, 0..) |color, cell| labels[cell] = @intCast(nearestCentre(centres, color));
}

fn recentre(cells: []const Rgb, labels: []const u8, centres: []Rgb, weights: *[max_palette]u32) void {
    var sums: [max_palette][3]u64 = undefined;
    @memset(&sums, .{ 0, 0, 0 });
    @memset(weights, 0);
    for (cells, 0..) |color, cell| {
        const label = labels[cell];
        weights[label] += 1;
        for (0..3) |channel| sums[label][channel] += color[channel];
    }
    for (centres, 0..) |*centre, k| {
        if (weights[k] == 0) continue;
        for (0..3) |channel| centre[channel] = @intCast((sums[k][channel] + weights[k] / 2) / weights[k]);
    }
}

fn mergeDown(centres: []Rgb, weights: *[max_palette]u32, length: usize, limit: usize) usize {
    var count = length;
    while (count > limit) {
        var best_a: usize = 0;
        var best_b: usize = 1;
        var best_cost: u64 = std.math.maxInt(u64);
        for (0..count) |a| {
            for (a + 1..count) |b| {
                const wa: u64 = weights[a];
                const wb: u64 = weights[b];
                const cost = @as(u64, sqDistance(centres[a], centres[b])) * wa * wb / @max(wa + wb, 1);
                if (cost < best_cost) {
                    best_cost = cost;
                    best_a = a;
                    best_b = b;
                }
            }
        }
        const wa: u64 = weights[best_a];
        const wb: u64 = weights[best_b];
        const total = @max(wa + wb, 1);
        for (0..3) |channel| {
            centres[best_a][channel] = @intCast((@as(u64, centres[best_a][channel]) * wa + @as(u64, centres[best_b][channel]) * wb + total / 2) / total);
        }
        weights[best_a] = @intCast(wa + wb);
        count -= 1;
        centres[best_b] = centres[count];
        weights[best_b] = weights[count];
    }
    return count;
}

pub fn convert(
    source_pixels: [*]const u8,
    input_width: u32,
    input_height: u32,
    input_stride: usize,
    target_width: u32,
    target_height: u32,
    background_rgb: u32,
    options: *const api.PixelArtOptions,
    destination: [*]u8,
) api.Status {
    const allocator = std.heap.page_allocator;
    const source = Source{
        .pixels = source_pixels,
        .stride = input_stride,
        .matte = .{ @truncate(background_rgb >> 16), @truncate(background_rgb >> 8), @truncate(background_rgb) },
    };
    const cell_count = @as(usize, target_width) * target_height;

    const profile_x = allocator.alloc(f64, @max(input_width, 2) - 1) catch return .out_of_memory;
    defer allocator.free(profile_x);
    const profile_y = allocator.alloc(f64, @max(input_height, 2) - 1) catch return .out_of_memory;
    defer allocator.free(profile_y);
    const cells = allocator.alloc(Rgb, cell_count) catch return .out_of_memory;
    defer allocator.free(cells);
    const labels = allocator.alloc(u8, cell_count) catch return .out_of_memory;
    defer allocator.free(labels);

    var grid_x = Axis{ .period = @as(f64, @floatFromInt(input_width)) / @as(f64, @floatFromInt(target_width)), .offset = 0 };
    var grid_y = Axis{ .period = @as(f64, @floatFromInt(input_height)) / @as(f64, @floatFromInt(target_height)), .offset = 0 };
    if (options.grid_fit == 1) {
        if (input_width >= 2) {
            edgeProfile(source, input_width, input_height, true, profile_x);
            grid_x = fitAxis(profile_x, target_width, input_width, options);
        }
        if (input_height >= 2) {
            edgeProfile(source, input_width, input_height, false, profile_y);
            grid_y = fitAxis(profile_y, target_height, input_height, options);
        }
    }

    sampleCells(source, input_width, input_height, grid_x, grid_y, target_width, target_height, options.sample_inset_percent, cells);

    var centres: [max_palette]Rgb = undefined;
    var weights: [max_palette]u32 = undefined;
    var length = leaders(allocator, cells, options.color_tolerance, &centres) catch return .out_of_memory;

    assign(cells, centres[0..length], labels);
    recentre(cells, labels, centres[0..length], &weights);
    if (options.palette_max != 0 and length > options.palette_max) {
        length = mergeDown(centres[0..length], &weights, length, options.palette_max);
    }
    var pass: u32 = 0;
    while (pass < options.refine_iterations) : (pass += 1) {
        assign(cells, centres[0..length], labels);
        recentre(cells, labels, centres[0..length], &weights);
    }
    assign(cells, centres[0..length], labels);

    for (0..cell_count) |cell| {
        @memcpy(destination[cell * 4 .. cell * 4 + 3], &centres[labels[cell]]);
        destination[cell * 4 + 3] = 255;
    }
    return .ok;
}

fn scaledArt(comptime cells: usize, comptime size: usize, art: *const [cells * cells]Rgb, out: *[size * size * 4]u8) void {
    var state: u32 = 12345;
    for (0..size) |y| {
        for (0..size) |x| {
            const cx = x * cells / size;
            const cy = y * cells / size;
            const base = art[cy * cells + cx];
            for (0..3) |channel| {
                state = state *% 1664525 +% 1013904223;
                const noise: i32 = @as(i32, @intCast((state >> 24) % 7)) - 3;
                out[(y * size + x) * 4 + channel] = @intCast(std.math.clamp(@as(i32, base[channel]) + noise, 0, 255));
            }
            out[(y * size + x) * 4 + 3] = 255;
        }
    }
}

fn expectNear(expected: u8, actual: u8) !void {
    try std.testing.expect(@abs(@as(i32, expected) - @as(i32, actual)) <= 3);
}

test "pixelart v2 recovers a noisy scaled-up grid exactly" {
    const cells = 10;
    const size = 32;
    const palette = [_]Rgb{ .{ 20, 20, 20 }, .{ 230, 230, 200 }, .{ 180, 90, 70 } };
    var art: [cells * cells]Rgb = undefined;
    for (0..cells * cells) |i| art[i] = palette[(i / 3 + i / cells) % 3];
    var input: [size * size * 4]u8 = undefined;
    scaledArt(cells, size, &art, &input);
    var output: [cells * cells * 4]u8 = undefined;
    const options = api.pixelart_defaults;
    try std.testing.expectEqual(api.Status.ok, convert(&input, size, size, size * 4, cells, cells, 0, &options, &output));
    for (0..cells * cells) |i| {
        for (0..3) |channel| try expectNear(art[i][channel], output[i * 4 + channel]);
        try std.testing.expectEqual(@as(u8, 255), output[i * 4 + 3]);
    }
}

test "pixelart v2 keeps a single cell detail" {
    const cells = 8;
    const size = 24;
    var art: [cells * cells]Rgb = undefined;
    @memset(&art, .{ 100, 150, 100 });
    art[3 * cells + 4] = .{ 250, 250, 250 };
    var input: [size * size * 4]u8 = undefined;
    scaledArt(cells, size, &art, &input);
    var output: [cells * cells * 4]u8 = undefined;
    const options = api.pixelart_defaults;
    try std.testing.expectEqual(api.Status.ok, convert(&input, size, size, size * 4, cells, cells, 0, &options, &output));
    try expectNear(250, output[(3 * cells + 4) * 4]);
    try expectNear(100, output[0]);
}

test "pixelart v2 palette_max merges the closest colours" {
    const cells = 4;
    const size = 16;
    var art: [cells * cells]Rgb = undefined;
    for (0..cells * cells) |i| art[i] = switch (i % 4) {
        0 => .{ 0, 0, 0 },
        1 => .{ 40, 0, 0 },
        2 => .{ 255, 255, 255 },
        else => .{ 255, 215, 255 },
    };
    var input: [size * size * 4]u8 = undefined;
    scaledArt(cells, size, &art, &input);
    var output: [cells * cells * 4]u8 = undefined;
    var options = api.pixelart_defaults;
    options.color_tolerance = 5;
    options.palette_max = 2;
    try std.testing.expectEqual(api.Status.ok, convert(&input, size, size, size * 4, cells, cells, 0, &options, &output));
    try std.testing.expectEqualSlices(u8, output[0..4], output[4..8]);
    try std.testing.expectEqualSlices(u8, output[8..12], output[12..16]);
    try std.testing.expect(output[0] != output[8]);
}
