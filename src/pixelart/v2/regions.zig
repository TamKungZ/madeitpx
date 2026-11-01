const std = @import("std");

const color = @import("../../common/color.zig");
const Rgb = color.Rgb;
const Grid = @import("ink.zig").Grid;
const cells_mod = @import("cells.zig");

const ring_dx = [8]i64{ -1, 0, 1, 1, 1, 0, -1, -1 };
const ring_dy = [8]i64{ -1, -1, -1, 0, 1, 1, 1, 0 };
const side_dx = [4]i64{ 0, -1, 1, 0 };
const side_dy = [4]i64{ -1, 0, 0, 1 };

pub const Work = struct {
    next: []u8,
    component: []u32,
    queue: []usize,
};

pub fn majority(grid: Grid, labels: []u8, ink: []const bool, work: Work, passes: usize) void {
    for (0..passes) |_| {
        @memcpy(work.next, labels);
        var changed = false;
        for (0..grid.h) |uy| {
            for (0..grid.w) |ux| {
                const x: i64 = @intCast(ux);
                const y: i64 = @intCast(uy);
                const index = grid.index(x, y);
                if (ink[index]) continue;

                var counts: [256]u8 = @splat(0);
                var total: u8 = 0;
                for (0..8) |k| {
                    const nx = x + ring_dx[k];
                    const ny = y + ring_dy[k];
                    if (!grid.inside(nx, ny)) continue;
                    const neighbor = grid.index(nx, ny);
                    if (ink[neighbor]) continue;
                    counts[labels[neighbor]] += 1;
                    total += 1;
                }
                if (total < 5) continue;
                var best: usize = labels[index];
                for (0..256) |label| {
                    if (counts[label] > counts[best]) best = label;
                }
                if (best != labels[index] and counts[best] >= 5 and counts[labels[index]] <= 2) {
                    work.next[index] = @intCast(best);
                    changed = true;
                }
            }
        }
        @memcpy(labels, work.next);
        if (!changed) break;
    }
}

pub fn mergeSmall(
    grid: Grid,
    labels: []u8,
    ink: []const bool,
    fill: []const Rgb,
    colors: []const Rgb,
    min_cells: usize,
    work: Work,
) void {
    const total = grid.w * grid.h;
    var round: usize = 0;
    while (round < 8) : (round += 1) {
        @memset(work.component, std.math.maxInt(u32));
        var changed = false;
        for (0..total) |start| {
            if (ink[start] or work.component[start] != std.math.maxInt(u32)) continue;

            const label = labels[start];
            var head: usize = 0;
            var tail: usize = 1;
            work.queue[0] = start;
            work.component[start] = @intCast(start);
            var sums = [3]u64{ 0, 0, 0 };
            while (head < tail) {
                const current = work.queue[head];
                head += 1;
                for (0..3) |channel| sums[channel] += fill[current][channel];
                const x: i64 = @intCast(current % grid.w);
                const y: i64 = @intCast(current / grid.w);
                for (0..4) |k| {
                    const nx = x + side_dx[k];
                    const ny = y + side_dy[k];
                    if (!grid.inside(nx, ny)) continue;
                    const neighbor = grid.index(nx, ny);
                    if (ink[neighbor] or labels[neighbor] != label or work.component[neighbor] != std.math.maxInt(u32)) continue;
                    work.component[neighbor] = @intCast(start);
                    work.queue[tail] = neighbor;
                    tail += 1;
                }
            }
            if (tail >= min_cells) continue;

            const mean = color.meanOf(sums, tail);
            var best: ?usize = null;
            var best_distance: u32 = std.math.maxInt(u32);
            for (work.queue[0..tail]) |member| {
                const x: i64 = @intCast(member % grid.w);
                const y: i64 = @intCast(member / grid.w);
                for (0..4) |k| {
                    const nx = x + side_dx[k];
                    const ny = y + side_dy[k];
                    if (!grid.inside(nx, ny)) continue;
                    const neighbor = grid.index(nx, ny);
                    if (ink[neighbor] or labels[neighbor] == label) continue;
                    const d = color.sqDistance(mean, colors[labels[neighbor]]);
                    if (d < best_distance) {
                        best_distance = d;
                        best = labels[neighbor];
                    }
                }
            }
            const target = best orelse continue;
            for (work.queue[0..tail]) |member| labels[member] = @intCast(target);
            changed = true;
        }
        if (!changed) break;
    }
}

pub fn dropIslands(grid: Grid, cells: []cells_mod.Cell, min_cells: usize, work: Work) void {
    if (scanIslands(grid, cells, min_cells, work, false) < min_cells) return;
    _ = scanIslands(grid, cells, min_cells, work, true);
}

fn scanIslands(grid: Grid, cells: []cells_mod.Cell, min_cells: usize, work: Work, clear: bool) usize {
    var largest: usize = 0;
    const total = grid.w * grid.h;
    @memset(work.component, std.math.maxInt(u32));
    for (0..total) |start| {
        if (cells[start].empty or work.component[start] != std.math.maxInt(u32)) continue;
        var head: usize = 0;
        var tail: usize = 1;
        work.queue[0] = start;
        work.component[start] = @intCast(start);
        while (head < tail) {
            const current = work.queue[head];
            head += 1;
            const x: i64 = @intCast(current % grid.w);
            const y: i64 = @intCast(current / grid.w);
            for (0..8) |k| {
                const nx = x + ring_dx[k];
                const ny = y + ring_dy[k];
                if (!grid.inside(nx, ny)) continue;
                const neighbor = grid.index(nx, ny);
                if (cells[neighbor].empty or work.component[neighbor] != std.math.maxInt(u32)) continue;
                work.component[neighbor] = @intCast(start);
                work.queue[tail] = neighbor;
                tail += 1;
            }
        }
        largest = @max(largest, tail);
        if (!clear or tail >= min_cells) continue;
        for (work.queue[0..tail]) |member| {
            cells[member].empty = true;
            cells[member].coverage = 0;
        }
    }
    return largest;
}
