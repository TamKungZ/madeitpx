const std = @import("std");

const color = @import("../../common/color.zig");
const Source = @import("../../common/source.zig").Source;

const period_step_permille: f64 = 0.5;
const phase_step: f64 = 0.1;

pub const Axis = struct {
    period: f64,
    offset: f64,

    pub fn even(size: u32, cells: u32) Axis {
        return .{ .period = @as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(cells)), .offset = 0 };
    }

    pub fn start(self: Axis, cell: usize) f64 {
        return self.offset + @as(f64, @floatFromInt(cell)) * self.period;
    }
};

pub fn edgeProfile(source: Source, width: u32, height: u32, horizontal: bool, profile: []f64) void {
    const along: usize = if (horizontal) width else height;
    const across: usize = if (horizontal) height else width;
    for (0..along - 1) |i| {
        var sum: u64 = 0;
        for (0..across) |j| {
            const first = if (horizontal) source.at(i, j) else source.at(j, i);
            const second = if (horizontal) source.at(i + 1, j) else source.at(j, i + 1);
            sum += color.absDelta(first, second);
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

pub fn fitAxis(profile: []const f64, cells: u32, size: u32, search_permille: u32) Axis {
    const nominal = Axis.even(size, cells);
    var best = nominal;
    if (cells < 2 or size < 3) return best;

    var best_score = boundaryScore(profile, cells, nominal.period, 0);
    const spread = nominal.period * @as(f64, @floatFromInt(search_permille)) / 1000.0;
    const step = @max(nominal.period * period_step_permille / 1000.0, 1e-6);
    const steps: usize = @intFromFloat(@ceil(spread / step));
    var index: usize = 0;
    while (index <= 2 * steps) : (index += 1) {
        const period = nominal.period - spread + @as(f64, @floatFromInt(index)) * step;
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

pub fn contrast(profile: []const f64, cells: u32, axis: Axis) f64 {
    const on_border = boundaryScore(profile, cells, axis.period, axis.offset);
    const between = boundaryScore(profile, cells, axis.period, axis.offset + axis.period / 2.0);
    return on_border / @max(between, 1e-9);
}

test "even axis splits the source evenly" {
    const axis = Axis.even(100, 10);
    try std.testing.expectEqual(@as(f64, 10), axis.period);
    try std.testing.expectEqual(@as(f64, 30), axis.start(3));
}
