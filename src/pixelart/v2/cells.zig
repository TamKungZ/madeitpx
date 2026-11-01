const std = @import("std");

const color = @import("../../common/color.zig");
const Rgb = color.Rgb;
const Source = @import("../../common/source.zig").Source;
const Axis = @import("grid.zig").Axis;

const edge_min_luma: u32 = 30;
const ink_max_luma: u32 = 150;
const ink_min_contrast: u32 = 40;
const ink_weak_percent: u64 = 12;

pub const Cell = struct {
    fill: Rgb,
    ink: Rgb,
    coverage: u8,
    empty: bool,
};

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

pub fn sampleGrid(
    source: Source,
    input_width: u32,
    input_height: u32,
    grid_x: Axis,
    grid_y: Axis,
    target_width: u32,
    target_height: u32,
    inset_percent: u32,
    cells: []Cell,
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
            var total: u32 = 0;
            var solid: u32 = 0;
            for (rows[0]..rows[1]) |y| {
                for (columns[0]..columns[1]) |x| {
                    total += 1;
                    const pixel = source.sample(x, y) orelse continue;
                    for (0..3) |channel| histograms[channel][pixel[channel]] += 1;
                    solid += 1;
                }
            }
            const cell = &cells[cy * target_width + cx];
            cell.* = .{ .fill = source.matte, .ink = .{ 0, 0, 0 }, .coverage = 0, .empty = true };
            if (solid == 0 or solid * 2 < total) continue;
            var median: Rgb = undefined;
            for (0..3) |channel| median[channel] = medianOf(&histograms[channel], solid);
            cell.fill = median;
            cell.empty = false;
        }
    }
}

fn otsuThreshold(histogram: *const [256]u32, count: u64) ?usize {
    var total_sum: u64 = 0;
    for (0..256) |level| total_sum += @as(u64, level) * histogram[level];
    var weight_dark: u64 = 0;
    var sum_dark: u64 = 0;
    var best: ?usize = null;
    var best_variance: u128 = 0;
    for (0..255) |level| {
        weight_dark += histogram[level];
        sum_dark += @as(u64, level) * histogram[level];
        const weight_light = count - weight_dark;
        if (weight_dark == 0 or weight_light == 0) continue;
        const mean_dark = sum_dark * 1024 / weight_dark;
        const mean_light = (total_sum - sum_dark) * 1024 / weight_light;
        const gap = if (mean_dark > mean_light) mean_dark - mean_light else mean_light - mean_dark;
        const variance = @as(u128, weight_dark) * weight_light * (gap * gap);
        if (variance > best_variance) {
            best_variance = variance;
            best = level;
        }
    }
    return best;
}

pub fn sampleArea(
    source: Source,
    input_width: u32,
    input_height: u32,
    target_width: u32,
    target_height: u32,
    cells: []Cell,
) void {
    for (0..target_height) |cy| {
        const y0: usize = @intCast(@as(u64, cy) * input_height / target_height);
        const y1 = @min(@max(@as(usize, @intCast(@as(u64, cy + 1) * input_height / target_height)), y0 + 1), @as(usize, input_height));
        for (0..target_width) |cx| {
            const x0: usize = @intCast(@as(u64, cx) * input_width / target_width);
            const x1 = @min(@max(@as(usize, @intCast(@as(u64, cx + 1) * input_width / target_width)), x0 + 1), @as(usize, input_width));

            var histogram: [256]u32 = @splat(0);
            var sums = [3]u64{ 0, 0, 0 };
            var count: u64 = 0;
            var total: u64 = 0;
            for (y0..y1) |y| {
                for (x0..x1) |x| {
                    total += 1;
                    const pixel = source.sample(x, y) orelse continue;
                    histogram[color.luma(pixel)] += 1;
                    for (0..3) |channel| sums[channel] += pixel[channel];
                    count += 1;
                }
            }
            const cell = &cells[cy * target_width + cx];
            cell.* = .{ .fill = source.matte, .ink = .{ 0, 0, 0 }, .coverage = 0, .empty = true };
            if (count == 0 or count * 2 < total) continue;
            cell.fill = color.meanOf(sums, count);
            cell.empty = false;

            const threshold = otsuThreshold(&histogram, count) orelse continue;
            var dark_sums = [3]u64{ 0, 0, 0 };
            var light_sums = [3]u64{ 0, 0, 0 };
            var dark_count: u64 = 0;
            var light_count: u64 = 0;
            for (y0..y1) |y| {
                for (x0..x1) |x| {
                    const pixel = source.sample(x, y) orelse continue;
                    if (color.luma(pixel) <= threshold) {
                        for (0..3) |channel| dark_sums[channel] += pixel[channel];
                        dark_count += 1;
                    } else {
                        for (0..3) |channel| light_sums[channel] += pixel[channel];
                        light_count += 1;
                    }
                }
            }
            if (dark_count == 0 or light_count == 0) continue;
            const dark_mean = color.meanOf(dark_sums, dark_count);
            const light_mean = color.meanOf(light_sums, light_count);
            const dark_luma = color.luma(dark_mean);
            const light_luma = color.luma(light_mean);
            if (light_luma < dark_luma + edge_min_luma) continue;

            cell.fill = if (dark_count > light_count) dark_mean else light_mean;
            if (dark_luma <= ink_max_luma and light_luma - dark_luma >= ink_min_contrast) {
                const percent = dark_count * 100 / count;
                if (percent >= ink_weak_percent) {
                    cell.coverage = @intCast(percent);
                    cell.ink = dark_mean;
                }
            }
        }
    }
}
