const cells_mod = @import("cells.zig");

const ring_dx = [8]i64{ -1, 0, 1, 1, 1, 0, -1, -1 };
const ring_dy = [8]i64{ -1, -1, -1, 0, 1, 1, 1, 0 };
const thin_dx = [4]i64{ 0, -1, 1, 0 };
const thin_dy = [4]i64{ -1, 0, 0, 1 };

pub const Grid = struct {
    w: usize,
    h: usize,

    pub fn inside(self: Grid, x: i64, y: i64) bool {
        return x >= 0 and y >= 0 and x < @as(i64, @intCast(self.w)) and y < @as(i64, @intCast(self.h));
    }

    pub fn index(self: Grid, x: i64, y: i64) usize {
        return @as(usize, @intCast(y)) * self.w + @as(usize, @intCast(x));
    }

    pub fn get(self: Grid, mask: []const bool, x: i64, y: i64) bool {
        return self.inside(x, y) and mask[self.index(x, y)];
    }
};

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

fn isSimple(grid: Grid, mask: []const bool, x: i64, y: i64) bool {
    var fg: [8]bool = undefined;
    for (0..8) |k| fg[k] = grid.get(mask, x + ring_dx[k], y + ring_dy[k]);
    return ringComponents(fg) == 1;
}

fn neighborCount(grid: Grid, mask: []const bool, x: i64, y: i64) usize {
    var count: usize = 0;
    for (0..8) |k| {
        if (grid.get(mask, x + ring_dx[k], y + ring_dy[k])) count += 1;
    }
    return count;
}

pub fn build(grid: Grid, cells: []const cells_mod.Cell, min_percent: u32, ink: []bool) void {
    for (cells, 0..) |cell, index| ink[index] = cell.coverage >= min_percent;

    for (0..grid.h) |uy| {
        for (0..grid.w) |ux| {
            const x: i64 = @intCast(ux);
            const y: i64 = @intCast(uy);
            const index = grid.index(x, y);
            if (!ink[index]) continue;
            var higher = false;
            for (0..4) |k| {
                const nx = x + thin_dx[k];
                const ny = y + thin_dy[k];
                if (!grid.get(ink, nx, ny)) continue;
                const neighbor = grid.index(nx, ny);
                if (cells[neighbor].coverage > cells[index].coverage or
                    (cells[neighbor].coverage == cells[index].coverage and neighbor < index))
                {
                    higher = true;
                    break;
                }
            }
            if (higher and neighborCount(grid, ink, x, y) >= 2 and isSimple(grid, ink, x, y)) {
                ink[index] = false;
            }
        }
    }

    for (0..grid.h) |uy| {
        for (0..grid.w) |ux| {
            const x: i64 = @intCast(ux);
            const y: i64 = @intCast(uy);
            const index = grid.index(x, y);
            if (ink[index] and neighborCount(grid, ink, x, y) == 0) ink[index] = false;
        }
    }
}
