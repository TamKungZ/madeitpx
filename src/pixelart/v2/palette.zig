const std = @import("std");

const color = @import("../../common/color.zig");
const Rgb = color.Rgb;

pub const max_colors: usize = 256;

const bin_shift: u3 = 3;
const bin_side: usize = 256 >> bin_shift;
const bin_count: usize = bin_side * bin_side * bin_side;

pub const Palette = struct {
    colors: [max_colors]Rgb = undefined,
    len: usize = 0,
};

const BinEntry = struct {
    count: u32,
    index: u32,
};

fn binGreater(_: void, a: BinEntry, b: BinEntry) bool {
    if (a.count != b.count) return a.count > b.count;
    return a.index < b.index;
}

fn leaders(allocator: std.mem.Allocator, input: []const Rgb, tolerance: u32, palette: *Palette) !void {
    const counts = try allocator.alloc(u32, bin_count);
    defer allocator.free(counts);
    const sums = try allocator.alloc([3]u32, bin_count);
    defer allocator.free(sums);
    @memset(counts, 0);
    @memset(sums, .{ 0, 0, 0 });

    for (input) |pixel| {
        const bin = (@as(usize, pixel[0] >> bin_shift) * bin_side + (pixel[1] >> bin_shift)) * bin_side + (pixel[2] >> bin_shift);
        counts[bin] += 1;
        for (0..3) |channel| sums[bin][channel] += pixel[channel];
    }

    var order = try std.ArrayList(BinEntry).initCapacity(allocator, 0);
    defer order.deinit(allocator);
    for (0..bin_count) |bin| {
        if (counts[bin] != 0) try order.append(allocator, .{ .count = counts[bin], .index = @intCast(bin) });
    }
    std.mem.sort(BinEntry, order.items, {}, binGreater);

    const limit_sq = tolerance * tolerance;
    palette.len = 0;
    for (order.items) |entry| {
        const bin = entry.index;
        var candidate: Rgb = undefined;
        for (0..3) |channel| candidate[channel] = @intCast((sums[bin][channel] + entry.count / 2) / entry.count);
        if (palette.len > 0) {
            const nearest = color.nearest(palette.colors[0..palette.len], candidate);
            if (color.sqDistance(candidate, palette.colors[nearest]) <= limit_sq) continue;
        }
        if (palette.len == max_colors) break;
        palette.colors[palette.len] = candidate;
        palette.len += 1;
    }
}

pub fn assign(input: []const Rgb, palette: *const Palette, labels: []u8) void {
    for (input, 0..) |pixel, index| labels[index] = @intCast(color.nearest(palette.colors[0..palette.len], pixel));
}

fn recentre(input: []const Rgb, labels: []const u8, palette: *Palette, weights: *[max_colors]u32) void {
    var sums: [max_colors][3]u64 = undefined;
    @memset(&sums, .{ 0, 0, 0 });
    @memset(weights, 0);
    for (input, 0..) |pixel, index| {
        const label = labels[index];
        weights[label] += 1;
        for (0..3) |channel| sums[label][channel] += pixel[channel];
    }
    for (0..palette.len) |k| {
        if (weights[k] == 0) continue;
        for (0..3) |channel| palette.colors[k][channel] = @intCast((sums[k][channel] + weights[k] / 2) / weights[k]);
    }
}

fn mergeDown(palette: *Palette, weights: *[max_colors]u32, limit: usize) void {
    while (palette.len > limit) {
        var best_a: usize = 0;
        var best_b: usize = 1;
        var best_cost: u64 = std.math.maxInt(u64);
        for (0..palette.len) |a| {
            for (a + 1..palette.len) |b| {
                const wa: u64 = weights[a];
                const wb: u64 = weights[b];
                const cost = @as(u64, color.sqDistance(palette.colors[a], palette.colors[b])) * wa * wb / @max(wa + wb, 1);
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
            palette.colors[best_a][channel] = @intCast((@as(u64, palette.colors[best_a][channel]) * wa + @as(u64, palette.colors[best_b][channel]) * wb + total / 2) / total);
        }
        weights[best_a] = @intCast(wa + wb);
        palette.len -= 1;
        palette.colors[best_b] = palette.colors[palette.len];
        weights[best_b] = weights[palette.len];
    }
}

pub fn build(
    allocator: std.mem.Allocator,
    input: []const Rgb,
    tolerance: u32,
    limit: usize,
    refine: u32,
    scratch: []u8,
    palette: *Palette,
) !void {
    palette.len = 0;
    if (input.len == 0) return;
    var weights: [max_colors]u32 = undefined;
    try leaders(allocator, input, tolerance, palette);

    assign(input, palette, scratch);
    recentre(input, scratch, palette, &weights);
    if (palette.len > limit) mergeDown(palette, &weights, @max(limit, 1));
    var pass: u32 = 0;
    while (pass < refine) : (pass += 1) {
        assign(input, palette, scratch);
        recentre(input, scratch, palette, &weights);
    }
}
