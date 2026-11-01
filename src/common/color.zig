pub const Rgb = [3]u8;

pub fn sqDistance(a: Rgb, b: Rgb) u32 {
    var total: u32 = 0;
    for (0..3) |channel| {
        const delta = @as(i32, a[channel]) - @as(i32, b[channel]);
        total += @intCast(delta * delta);
    }
    return total;
}

pub fn absDelta(a: Rgb, b: Rgb) u32 {
    var total: u32 = 0;
    for (0..3) |channel| total += @abs(@as(i32, a[channel]) - @as(i32, b[channel]));
    return total;
}

pub fn luma(color: Rgb) u32 {
    return (77 * @as(u32, color[0]) + 150 * @as(u32, color[1]) + 29 * @as(u32, color[2])) >> 8;
}

pub fn nearest(centres: []const Rgb, color: Rgb) usize {
    var best: usize = 0;
    var best_distance: u32 = @import("std").math.maxInt(u32);
    for (centres, 0..) |centre, position| {
        const d = sqDistance(color, centre);
        if (d < best_distance) {
            best_distance = d;
            best = position;
        }
    }
    return best;
}

pub fn meanOf(sums: [3]u64, count: u64) Rgb {
    return .{
        @intCast((sums[0] + count / 2) / count),
        @intCast((sums[1] + count / 2) / count),
        @intCast((sums[2] + count / 2) / count),
    };
}
