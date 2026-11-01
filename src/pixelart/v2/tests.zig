const std = @import("std");

const api = @import("../../api/types.zig");
const Rgb = @import("../../common/color.zig").Rgb;
const convert = @import("convert.zig").convert;

fn expectNear(expected: u8, actual: u8) !void {
    try std.testing.expect(@abs(@as(i32, expected) - @as(i32, actual)) <= 3);
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

fn fillInput(buffer: []u8, red: u8, green: u8, blue: u8) void {
    for (0..buffer.len / 4) |pixel| {
        buffer[pixel * 4] = red;
        buffer[pixel * 4 + 1] = green;
        buffer[pixel * 4 + 2] = blue;
        buffer[pixel * 4 + 3] = 255;
    }
}

fn setPixel(buffer: []u8, width: usize, x: usize, y: usize, value: u8) void {
    const base = (y * width + x) * 4;
    buffer[base] = value;
    buffer[base + 1] = value;
    buffer[base + 2] = value;
    buffer[base + 3] = 255;
}

test "auto mode recovers a noisy scaled-up grid" {
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

test "grid mode keeps a single cell detail" {
    const cells = 8;
    const size = 24;
    var art: [cells * cells]Rgb = undefined;
    @memset(&art, .{ 100, 150, 100 });
    art[3 * cells + 4] = .{ 250, 250, 250 };
    var input: [size * size * 4]u8 = undefined;
    scaledArt(cells, size, &art, &input);
    var output: [cells * cells * 4]u8 = undefined;
    var options = api.pixelart_defaults;
    options.mode = @backingInt(api.PixelArtMode.grid);
    try std.testing.expectEqual(api.Status.ok, convert(&input, size, size, size * 4, cells, cells, 0, &options, &output));
    try expectNear(250, output[(3 * cells + 4) * 4]);
    try expectNear(100, output[0]);
}

test "palette_max merges the closest colours" {
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
    options.mode = @backingInt(api.PixelArtMode.grid);
    options.color_tolerance = 5;
    options.palette_max = 2;
    try std.testing.expectEqual(api.Status.ok, convert(&input, size, size, size * 4, cells, cells, 0, &options, &output));
    try std.testing.expectEqualSlices(u8, output[0..4], output[4..8]);
    try std.testing.expectEqualSlices(u8, output[8..12], output[12..16]);
    try std.testing.expect(output[0] != output[8]);
}

test "illustration mode merges an isolated cell into its surroundings" {
    var input: [32 * 32 * 4]u8 = undefined;
    fillInput(&input, 120, 120, 120);
    for (12..16) |y| {
        for (16..20) |x| setPixel(&input, 32, x, y, 170);
    }
    var output: [8 * 8 * 4]u8 = undefined;
    var options = api.pixelart_defaults;
    options.mode = @backingInt(api.PixelArtMode.illustration);
    try std.testing.expectEqual(api.Status.ok, convert(&input, 32, 32, 128, 8, 8, 0, &options, &output));
    for (0..64) |pixel| try std.testing.expectEqualSlices(u8, output[0..4], output[pixel * 4 .. pixel * 4 + 4]);
}

test "illustration mode keeps a thin dark line dark" {
    var input: [48 * 48 * 4]u8 = undefined;
    fillInput(&input, 230, 230, 230);
    for (4..44) |x| {
        setPixel(&input, 48, x, 23, 20);
        setPixel(&input, 48, x, 24, 20);
    }
    var output: [12 * 12 * 4]u8 = undefined;
    var options = api.pixelart_defaults;
    options.mode = @backingInt(api.PixelArtMode.illustration);
    try std.testing.expectEqual(api.Status.ok, convert(&input, 48, 48, 192, 12, 12, 0, &options, &output));
    for (2..10) |x| {
        const upper = output[(5 * 12 + x) * 4];
        const lower = output[(6 * 12 + x) * 4];
        try std.testing.expect(@min(upper, lower) < 60);
        try std.testing.expect(@max(upper, lower) > 200);
    }
    try std.testing.expect(output[0] > 200);
}

test "auto mode treats a smooth gradient as an illustration" {
    var input: [64 * 64 * 4]u8 = undefined;
    for (0..64) |y| {
        for (0..64) |x| setPixel(&input, 64, x, y, @intCast(x * 3 + y));
    }
    var output: [16 * 16 * 4]u8 = undefined;
    const options = api.pixelart_defaults;
    try std.testing.expectEqual(api.Status.ok, convert(&input, 64, 64, 256, 16, 16, 0, &options, &output));
    var seen: [256]bool = @splat(false);
    var distinct: usize = 0;
    for (0..256) |pixel| {
        if (!seen[output[pixel * 4]]) {
            seen[output[pixel * 4]] = true;
            distinct += 1;
        }
    }
    try std.testing.expect(distinct <= 32);
}

test "faint alpha fringe neither darkens the edge nor becomes a cell" {
    var input: [24 * 24 * 4]u8 = undefined;
    @memset(&input, 0);
    for (0..24) |y| {
        for (0..24) |x| {
            const base = (y * 24 + x) * 4;
            const inside = x >= 4 and x < 20 and y >= 4 and y < 20;
            const fringe = !inside and x >= 3 and x < 21 and y >= 3 and y < 21;
            if (inside) {
                input[base] = 120;
                input[base + 1] = 120;
                input[base + 2] = 120;
                input[base + 3] = 255;
            } else if (fringe) {
                input[base + 3] = 60;
            }
        }
    }
    var output: [6 * 6 * 4]u8 = undefined;
    var options = api.pixelart_defaults;
    options.mode = @backingInt(api.PixelArtMode.illustration);
    try std.testing.expectEqual(api.Status.ok, convert(&input, 24, 24, 96, 6, 6, 0x102030, &options, &output));
    for (0..6) |y| {
        for (0..6) |x| {
            const inside = x >= 1 and x <= 4 and y >= 1 and y <= 4;
            const expected: [3]u8 = if (inside) .{ 120, 120, 120 } else .{ 0x10, 0x20, 0x30 };
            try std.testing.expectEqualSlices(u8, &expected, output[(y * 6 + x) * 4 .. (y * 6 + x) * 4 + 3]);
        }
    }
}
