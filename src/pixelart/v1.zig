const std = @import("std");

const api = @import("../api/types.zig");
const palette_mod = @import("../core/palette.zig");

const Rgb = [3]u8;

pub const default_palette_colors: usize = 16;

const edge_dist: u32 = 9216;
const ink_max_luma: u32 = 150;
const ink_min_contrast: u32 = 40;
const cov_strong: u8 = 20;
const cov_weak: u8 = 12;
const ink_merge_dist: u32 = 5184;

const max_aligned_gap: i64 = 2;
const max_evidence_gap: i64 = 5;
const local_depth: u8 = 12;
const local_span: usize = 25;

const max_cleanup_iterations: usize = 16;

const ring_dx = [8]i64{ -1, 0, 1, 1, 1, 0, -1, -1 };
const ring_dy = [8]i64{ -1, -1, -1, 0, 1, 1, 1, 0 };
const thin_dx = [4]i64{ 0, -1, 1, 0 };
const thin_dy = [4]i64{ -1, 0, 0, 1 };
const lateral_order = [5]i64{ 0, -1, 1, -2, 2 };

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

const Region = struct {
    x0: usize,
    x1: usize,
    y0: usize,
    y1: usize,
};

const Split = struct {
    n0: u64,
    n1: u64,
    m0: Rgb,
    m1: Rgb,
};

const Grid = struct {
    w: usize,
    h: usize,

    fn inside(self: Grid, x: i64, y: i64) bool {
        return x >= 0 and y >= 0 and
            x < @as(i64, @intCast(self.w)) and y < @as(i64, @intCast(self.h));
    }

    fn index(self: Grid, x: i64, y: i64) usize {
        return @as(usize, @intCast(y)) * self.w + @as(usize, @intCast(x));
    }

    fn get(self: Grid, mask: []const bool, x: i64, y: i64) bool {
        return self.inside(x, y) and mask[self.index(x, y)];
    }
};

fn distance(a: Rgb, b: Rgb) u32 {
    return palette_mod.colorDistanceBetween(a, b);
}

fn luma(color: Rgb) u32 {
    return (77 * @as(u32, color[0]) + 150 * @as(u32, color[1]) + 29 * @as(u32, color[2])) >> 8;
}

fn sign(value: i64) i64 {
    if (value > 0) return 1;
    if (value < 0) return -1;
    return 0;
}

fn meanOf(sums: [3]u64, count: u64) Rgb {
    return .{
        @intCast((sums[0] + count / 2) / count),
        @intCast((sums[1] + count / 2) / count),
        @intCast((sums[2] + count / 2) / count),
    };
}

fn cellStart(cell: usize, source_size: u32, target_size: u32) usize {
    return @intCast(@as(u64, cell) * source_size / target_size);
}

fn cellRegion(ox: usize, oy: usize, input_width: u32, input_height: u32, target_width: u32, target_height: u32) Region {
    const x0 = cellStart(ox, input_width, target_width);
    const y0 = cellStart(oy, input_height, target_height);
    const x1 = @min(@max(cellStart(ox + 1, input_width, target_width), x0 + 1), @as(usize, input_width));
    const y1 = @min(@max(cellStart(oy + 1, input_height, target_height), y0 + 1), @as(usize, input_height));
    return .{ .x0 = x0, .x1 = x1, .y0 = y0, .y1 = y1 };
}

fn farthestFrom(source: Source, region: Region, from: Rgb) Rgb {
    var best = source.at(region.x0, region.y0);
    var best_distance = distance(best, from);
    for (region.y0..region.y1) |y| {
        for (region.x0..region.x1) |x| {
            const color = source.at(x, y);
            const candidate_distance = distance(color, from);
            if (candidate_distance > best_distance) {
                best = color;
                best_distance = candidate_distance;
            }
        }
    }
    return best;
}

fn classifyRound(source: Source, region: Region, c0: Rgb, c1: Rgb) ?Split {
    var sums0 = [3]u64{ 0, 0, 0 };
    var sums1 = [3]u64{ 0, 0, 0 };
    var n0: u64 = 0;
    var n1: u64 = 0;
    for (region.y0..region.y1) |y| {
        for (region.x0..region.x1) |x| {
            const color = source.at(x, y);
            if (distance(color, c1) < distance(color, c0)) {
                for (0..3) |channel| sums1[channel] += color[channel];
                n1 += 1;
            } else {
                for (0..3) |channel| sums0[channel] += color[channel];
                n0 += 1;
            }
        }
    }
    if (n0 == 0 or n1 == 0) return null;
    return .{ .n0 = n0, .n1 = n1, .m0 = meanOf(sums0, n0), .m1 = meanOf(sums1, n1) };
}

fn reduceCells(
    source: Source,
    input_width: u32,
    input_height: u32,
    target_width: u32,
    target_height: u32,
    fill: []Rgb,
    ink_color: []Rgb,
    coverage: []u8,
) void {
    for (0..target_height) |oy| {
        for (0..target_width) |ox| {
            const cell = oy * @as(usize, target_width) + ox;
            const region = cellRegion(ox, oy, input_width, input_height, target_width, target_height);

            var sums = [3]u64{ 0, 0, 0 };
            var count: u64 = 0;
            for (region.y0..region.y1) |y| {
                for (region.x0..region.x1) |x| {
                    const color = source.at(x, y);
                    for (0..3) |channel| sums[channel] += color[channel];
                    count += 1;
                }
            }
            fill[cell] = meanOf(sums, count);
            ink_color[cell] = .{ 0, 0, 0 };
            coverage[cell] = 0;
            if (count < 2) continue;

            const first = source.at(region.x0, region.y0);
            const far_a = farthestFrom(source, region, first);
            const far_b = farthestFrom(source, region, far_a);
            const round1 = classifyRound(source, region, far_a, far_b) orelse continue;
            const round2 = classifyRound(source, region, round1.m0, round1.m1) orelse continue;
            const round3 = classifyRound(source, region, round2.m0, round2.m1) orelse continue;
            if (distance(round3.m0, round3.m1) < edge_dist) continue;

            const luma0 = luma(round3.m0);
            const luma1 = luma(round3.m1);
            const dark_is_first = luma0 <= luma1;
            const dark_mean = if (dark_is_first) round3.m0 else round3.m1;
            const light_mean = if (dark_is_first) round3.m1 else round3.m0;
            const dark_count = if (dark_is_first) round3.n0 else round3.n1;
            const light_count = if (dark_is_first) round3.n1 else round3.n0;
            const dark_luma = @min(luma0, luma1);
            const light_luma = @max(luma0, luma1);

            fill[cell] = if (dark_count > light_count) dark_mean else light_mean;

            if (dark_luma <= ink_max_luma and light_luma - dark_luma >= ink_min_contrast) {
                const percent = dark_count * 100 / count;
                if (percent >= cov_weak) {
                    coverage[cell] = @intCast(percent);
                    ink_color[cell] = dark_mean;
                }
            }
        }
    }
}

fn ringComponents(fg: [8]bool) u32 {
    var visited: [8]bool = @splat(false);
    var components: u32 = 0;
    for (0..8) |start| {
        if (!fg[start] or visited[start]) continue;
        components += 1;
        var stack: [8]usize = undefined;
        var top: usize = 1;
        stack[0] = start;
        visited[start] = true;
        while (top > 0) {
            top -= 1;
            const current = stack[top];
            for (0..8) |other| {
                if (!fg[other] or visited[other]) continue;
                const step_x = ring_dx[current] - ring_dx[other];
                const step_y = ring_dy[current] - ring_dy[other];
                if (@abs(step_x) <= 1 and @abs(step_y) <= 1) {
                    visited[other] = true;
                    stack[top] = other;
                    top += 1;
                }
            }
        }
    }
    return components;
}

fn isSimple(grid: Grid, ink: []const bool, x: i64, y: i64) bool {
    var fg: [8]bool = undefined;
    for (0..8) |k| fg[k] = grid.get(ink, x + ring_dx[k], y + ring_dy[k]);
    return ringComponents(fg) == 1;
}

fn inkNeighborCount(grid: Grid, ink: []const bool, x: i64, y: i64) usize {
    var count: usize = 0;
    for (0..8) |k| {
        if (grid.get(ink, x + ring_dx[k], y + ring_dy[k])) count += 1;
    }
    return count;
}

fn localSlot(dx: i64, dy: i64) usize {
    const radius: i64 = local_depth;
    return @as(usize, @intCast(dy + radius)) * local_span + @as(usize, @intCast(dx + radius));
}

fn locallyConnected(grid: Grid, ink: []const bool, x0: i64, y0: i64, x1: i64, y1: i64) bool {
    var seen: [local_span * local_span]bool = @splat(false);
    var queue: [local_span * local_span][2]i64 = undefined;
    var depth: [local_span * local_span]u8 = undefined;
    var head: usize = 0;
    var tail: usize = 1;
    queue[0] = .{ x0, y0 };
    depth[0] = 0;
    seen[localSlot(0, 0)] = true;
    while (head < tail) {
        const current = queue[head];
        const current_depth = depth[head];
        head += 1;
        if (current_depth >= local_depth) continue;
        for (0..8) |k| {
            const nx = current[0] + ring_dx[k];
            const ny = current[1] + ring_dy[k];
            if (!grid.get(ink, nx, ny)) continue;
            const slot = localSlot(nx - x0, ny - y0);
            if (seen[slot]) continue;
            if (nx == x1 and ny == y1) return true;
            seen[slot] = true;
            queue[tail] = .{ nx, ny };
            depth[tail] = current_depth + 1;
            tail += 1;
        }
    }
    return false;
}

fn linePath(x0: i64, y0: i64, x1: i64, y1: i64, out: *[16][2]i64) usize {
    const dx: i64 = @intCast(@abs(x1 - x0));
    const dy: i64 = -@as(i64, @intCast(@abs(y1 - y0)));
    const step_x: i64 = if (x0 < x1) 1 else -1;
    const step_y: i64 = if (y0 < y1) 1 else -1;
    var err = dx + dy;
    var x = x0;
    var y = y0;
    var count: usize = 0;
    while (true) {
        if (x == x1 and y == y1) break;
        const doubled = 2 * err;
        if (doubled >= dy) {
            err += dy;
            x += step_x;
        }
        if (doubled <= dx) {
            err += dx;
            y += step_y;
        }
        if (x == x1 and y == y1) break;
        if (count < out.len) {
            out[count] = .{ x, y };
            count += 1;
        }
    }
    return count;
}

fn buildInk(
    grid: Grid,
    coverage: []const u8,
    ink_color: []const Rgb,
    ink: []bool,
    color: []Rgb,
) void {
    const total = grid.w * grid.h;
    for (0..total) |cell| {
        ink[cell] = coverage[cell] >= cov_strong;
        color[cell] = ink_color[cell];
    }

    for (0..grid.h) |uy| {
        for (0..grid.w) |ux| {
            const x: i64 = @intCast(ux);
            const y: i64 = @intCast(uy);
            const cell = grid.index(x, y);
            if (!ink[cell]) continue;
            var higher = false;
            for (0..4) |k| {
                const nx = x + thin_dx[k];
                const ny = y + thin_dy[k];
                if (!grid.get(ink, nx, ny)) continue;
                const neighbor = grid.index(nx, ny);
                if (coverage[neighbor] > coverage[cell] or
                    (coverage[neighbor] == coverage[cell] and neighbor < cell))
                {
                    higher = true;
                    break;
                }
            }
            if (higher and inkNeighborCount(grid, ink, x, y) >= 2 and isSimple(grid, ink, x, y)) {
                ink[cell] = false;
            }
        }
    }

    for (0..grid.h) |uy| {
        for (0..grid.w) |ux| {
            const x: i64 = @intCast(ux);
            const y: i64 = @intCast(uy);
            const cell = grid.index(x, y);
            if (ink[cell] and inkNeighborCount(grid, ink, x, y) == 0) ink[cell] = false;
        }
    }

    for (0..grid.h) |uy| {
        for (0..grid.w) |ux| {
            const x: i64 = @intCast(ux);
            const y: i64 = @intCast(uy);
            const cell = grid.index(x, y);
            if (!ink[cell]) continue;

            var neighbor_count: usize = 0;
            var sum_x: i64 = 0;
            var sum_y: i64 = 0;
            for (0..8) |k| {
                if (grid.get(ink, x + ring_dx[k], y + ring_dy[k])) {
                    neighbor_count += 1;
                    sum_x -= ring_dx[k];
                    sum_y -= ring_dy[k];
                }
            }
            if (neighbor_count == 0 or neighbor_count > 3 or !isSimple(grid, ink, x, y)) continue;
            const dir_x = sign(sum_x);
            const dir_y = sign(sum_y);
            if (dir_x == 0 and dir_y == 0) continue;
            const perp_x = -dir_y;
            const perp_y = dir_x;

            var gap: i64 = 1;
            search: while (gap <= max_evidence_gap) : (gap += 1) {
                const lateral_limit: i64 = if (gap <= 2) 1 else 2;
                for (lateral_order) |lateral| {
                    const lateral_abs: i64 = if (lateral < 0) -lateral else lateral;
                    if (lateral_abs > lateral_limit) continue;
                    const tx = x + (gap + 1) * dir_x + lateral * perp_x;
                    const ty = y + (gap + 1) * dir_y + lateral * perp_y;
                    if (!grid.get(ink, tx, ty)) continue;
                    if (locallyConnected(grid, ink, x, y, tx, ty)) continue;

                    var path: [16][2]i64 = undefined;
                    const length = linePath(x, y, tx, ty, &path);
                    var usable = true;
                    for (0..length) |p| {
                        const path_cell = grid.index(path[p][0], path[p][1]);
                        if (ink[path_cell]) {
                            usable = false;
                            break;
                        }
                        if (gap > max_aligned_gap and coverage[path_cell] == 0) {
                            usable = false;
                            break;
                        }
                    }
                    if (!usable) continue;

                    for (0..length) |p| {
                        const path_cell = grid.index(path[p][0], path[p][1]);
                        ink[path_cell] = true;
                        if (coverage[path_cell] == 0) color[path_cell] = color[cell];
                    }
                    break :search;
                }
            }
        }
    }
}

fn nearestIn(palette: []const Rgb, color: Rgb) u8 {
    var best: usize = 0;
    var best_distance: u32 = std.math.maxInt(u32);
    for (palette, 0..) |entry, position| {
        const entry_distance = distance(color, entry);
        if (entry_distance < best_distance) {
            best_distance = entry_distance;
            best = position;
        }
    }
    return @intCast(best);
}

fn markSolid(grid: Grid, label: []const u8, ink: []const bool, solid: []bool) void {
    @memset(solid, false);
    if (grid.w < 2 or grid.h < 2) return;
    for (0..grid.h - 1) |y| {
        for (0..grid.w - 1) |x| {
            const a = y * grid.w + x;
            const b = a + 1;
            const c = a + grid.w;
            const d = c + 1;
            if (ink[a] or ink[b] or ink[c] or ink[d]) continue;
            if (label[a] == label[b] and label[a] == label[c] and label[a] == label[d]) {
                solid[a] = true;
                solid[b] = true;
                solid[c] = true;
                solid[d] = true;
            }
        }
    }
}

fn cleanup(
    grid: Grid,
    label: []u8,
    next_label: []u8,
    solid: []bool,
    ink: []const bool,
    fill: []const Rgb,
    colors: []const Rgb,
) void {
    var iteration: usize = 0;
    while (iteration < max_cleanup_iterations) : (iteration += 1) {
        markSolid(grid, label, ink, solid);
        @memcpy(next_label, label);
        var changed: usize = 0;

        for (0..grid.h) |uy| {
            for (0..grid.w) |ux| {
                const x: i64 = @intCast(ux);
                const y: i64 = @intCast(uy);
                const cell = grid.index(x, y);
                if (ink[cell] or solid[cell]) continue;

                var counts: [palette_mod.max_colors]u8 = @splat(0);
                var any = false;
                for (0..8) |k| {
                    const nx = x + ring_dx[k];
                    const ny = y + ring_dy[k];
                    if (!grid.inside(nx, ny)) continue;
                    const neighbor = grid.index(nx, ny);
                    if (ink[neighbor] or !solid[neighbor] or label[neighbor] == label[cell]) continue;
                    counts[label[neighbor]] += 1;
                    any = true;
                }
                if (!any) continue;

                var best: usize = 0;
                var best_distance: u32 = 0;
                var best_count: u8 = 0;
                var have = false;
                for (0..colors.len) |k| {
                    if (counts[k] == 0) continue;
                    const candidate_distance = distance(fill[cell], colors[k]);
                    if (!have or candidate_distance < best_distance or
                        (candidate_distance == best_distance and counts[k] > best_count))
                    {
                        have = true;
                        best = k;
                        best_distance = candidate_distance;
                        best_count = counts[k];
                    }
                }
                next_label[cell] = @intCast(best);
                changed += 1;
            }
        }

        @memcpy(label, next_label);
        if (changed == 0) break;
    }
}

fn paletteLimit(options: *const api.Options) usize {
    if (options.palette_colors != 0) return options.palette_colors;
    return default_palette_colors;
}

pub fn convert(
    source_pixels: [*]const u8,
    input_width: u32,
    input_height: u32,
    input_stride: usize,
    target_width: u32,
    target_height: u32,
    options: *const api.Options,
    destination: [*]u8,
) api.Status {
    const allocator = std.heap.page_allocator;
    const grid = Grid{ .w = target_width, .h = target_height };
    const cell_count = grid.w * grid.h;
    const source = Source{
        .pixels = source_pixels,
        .stride = input_stride,
        .matte = .{
            @truncate(options.background_rgb >> 16),
            @truncate(options.background_rgb >> 8),
            @truncate(options.background_rgb),
        },
    };

    const fill = allocator.alloc(Rgb, cell_count) catch return .out_of_memory;
    defer allocator.free(fill);
    const ink_color = allocator.alloc(Rgb, cell_count) catch return .out_of_memory;
    defer allocator.free(ink_color);
    const ink_final = allocator.alloc(Rgb, cell_count) catch return .out_of_memory;
    defer allocator.free(ink_final);
    const coverage = allocator.alloc(u8, cell_count) catch return .out_of_memory;
    defer allocator.free(coverage);
    const ink = allocator.alloc(bool, cell_count) catch return .out_of_memory;
    defer allocator.free(ink);
    const label = allocator.alloc(u8, cell_count) catch return .out_of_memory;
    defer allocator.free(label);
    const next_label = allocator.alloc(u8, cell_count) catch return .out_of_memory;
    defer allocator.free(next_label);
    const solid = allocator.alloc(bool, cell_count) catch return .out_of_memory;
    defer allocator.free(solid);
    const rgba = allocator.alloc(u8, cell_count * 4) catch return .out_of_memory;
    defer allocator.free(rgba);
    const indices = allocator.alloc(usize, cell_count) catch return .out_of_memory;
    defer allocator.free(indices);

    reduceCells(source, input_width, input_height, target_width, target_height, fill, ink_color, coverage);
    buildInk(grid, coverage, ink_color, ink, ink_final);

    const limit = paletteLimit(options);
    var colors: [palette_mod.max_colors]Rgb = undefined;

    var ink_cells: usize = 0;
    var ink_sums = [3]u64{ 0, 0, 0 };
    for (0..cell_count) |cell| {
        if (!ink[cell]) continue;
        @memcpy(rgba[ink_cells * 4 .. ink_cells * 4 + 3], &ink_final[cell]);
        rgba[ink_cells * 4 + 3] = 255;
        for (0..3) |channel| ink_sums[channel] += ink_final[cell][channel];
        ink_cells += 1;
    }
    var ink_len: usize = 0;
    if (ink_cells > 0) {
        const ink_cap: usize = if (limit >= 8) 2 else 1;
        const ink_palette = palette_mod.buildPalette(rgba.ptr, ink_cells, ink_cap, indices);
        ink_len = ink_palette.len;
        for (0..ink_len) |k| colors[k] = ink_palette.colors[k];
        if (ink_len == 2 and distance(colors[0], colors[1]) < ink_merge_dist) {
            colors[0] = meanOf(ink_sums, ink_cells);
            ink_len = 1;
        }
    }

    var fill_cells: usize = 0;
    for (0..cell_count) |cell| {
        if (ink[cell]) continue;
        @memcpy(rgba[fill_cells * 4 .. fill_cells * 4 + 3], &fill[cell]);
        rgba[fill_cells * 4 + 3] = 255;
        fill_cells += 1;
    }
    var total = ink_len;
    if (fill_cells > 0) {
        const fill_limit = @max(1, limit - ink_len);
        const fill_palette = palette_mod.buildPalette(rgba.ptr, fill_cells, fill_limit, indices);
        for (0..fill_palette.len) |k| {
            colors[total] = fill_palette.colors[k];
            total += 1;
        }
    }

    for (0..cell_count) |cell| {
        label[cell] = if (ink[cell])
            nearestIn(colors[0..ink_len], ink_final[cell])
        else
            nearestIn(colors[0..total], fill[cell]);
    }

    if (options.cluster_cleanup == 1) {
        cleanup(grid, label, next_label, solid, ink, fill, colors[0..total]);
    }

    for (0..cell_count) |cell| {
        const entry = colors[label[cell]];
        @memcpy(destination[cell * 4 .. cell * 4 + 3], &entry);
        destination[cell * 4 + 3] = 255;
    }
    return .ok;
}

fn testOptions() api.Options {
    return .{
        .struct_size = @sizeOf(api.Options),
        .preset = 3,
        .palette_colors = 0,
        .background_rgb = 0,
        .sample_mode = 0,
        .cluster_cleanup = 1,
        .reserved = 0,
    };
}

fn fillInput(buffer: []u8, red: u8, green: u8, blue: u8) void {
    for (0..buffer.len / 4) |pixel| {
        buffer[pixel * 4] = red;
        buffer[pixel * 4 + 1] = green;
        buffer[pixel * 4 + 2] = blue;
        buffer[pixel * 4 + 3] = 255;
    }
}

fn setPixel(buffer: []u8, width: usize, x: usize, y: usize, red: u8, green: u8, blue: u8) void {
    const base = (y * width + x) * 4;
    buffer[base] = red;
    buffer[base + 1] = green;
    buffer[base + 2] = blue;
    buffer[base + 3] = 255;
}

test "pixelart pulls an isolated pixel into its surroundings" {
    var input: [8 * 8 * 4]u8 = undefined;
    fillInput(&input, 120, 120, 120);
    setPixel(&input, 8, 4, 3, 160, 160, 160);
    var output: [8 * 8 * 4]u8 = undefined;
    const options = testOptions();
    try std.testing.expectEqual(api.Status.ok, convert(&input, 8, 8, 32, 8, 8, &options, &output));
    for (0..64) |pixel| {
        try std.testing.expectEqualSlices(u8, output[0..4], output[pixel * 4 .. pixel * 4 + 4]);
    }
}

test "pixelart removes a one pixel wide gradient band" {
    var input: [8 * 8 * 4]u8 = undefined;
    for (0..8) |y| {
        for (0..8) |x| {
            const value: u8 = if (x < 3) 100 else if (x == 3) 130 else 180;
            setPixel(&input, 8, x, y, value, value, value);
        }
    }
    var output: [8 * 8 * 4]u8 = undefined;
    const options = testOptions();
    try std.testing.expectEqual(api.Status.ok, convert(&input, 8, 8, 32, 8, 8, &options, &output));
    for (0..8) |y| {
        for (0..8) |x| {
            const expected: u8 = if (x < 4) 100 else 180;
            try std.testing.expectEqual(expected, output[(y * 8 + x) * 4]);
        }
    }
}

test "pixelart keeps a dark line dark and bridges a short gap" {
    var input: [24 * 24 * 4]u8 = undefined;
    fillInput(&input, 230, 230, 230);
    for (2..10) |x| setPixel(&input, 24, x, 11, 20, 20, 20);
    for (14..22) |x| setPixel(&input, 24, x, 11, 20, 20, 20);
    var output: [12 * 12 * 4]u8 = undefined;
    var options = testOptions();
    options.palette_colors = 2;
    try std.testing.expectEqual(api.Status.ok, convert(&input, 24, 24, 96, 12, 12, &options, &output));
    for (1..11) |x| {
        try std.testing.expectEqual(@as(u8, 20), output[(5 * 12 + x) * 4]);
    }
    try std.testing.expectEqual(@as(u8, 230), output[0]);
    for (0..144) |pixel| try std.testing.expectEqual(@as(u8, 255), output[pixel * 4 + 3]);
}

test "pixelart does not bridge two unrelated line ends that are far apart" {
    var input: [32 * 16 * 4]u8 = undefined;
    fillInput(&input, 230, 230, 230);
    for (2..6) |x| setPixel(&input, 32, x, 7, 20, 20, 20);
    for (26..30) |x| setPixel(&input, 32, x, 7, 20, 20, 20);
    var output: [16 * 8 * 4]u8 = undefined;
    const options = testOptions();
    try std.testing.expectEqual(api.Status.ok, convert(&input, 32, 16, 128, 16, 8, &options, &output));
    try std.testing.expectEqual(@as(u8, 230), output[(3 * 16 + 8) * 4]);
}
