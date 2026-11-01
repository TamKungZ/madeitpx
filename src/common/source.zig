const Rgb = @import("color.zig").Rgb;

pub const Source = struct {
    pixels: [*]const u8,
    stride: usize,
    matte: Rgb,
    alpha_min: u8,

    pub fn init(pixels: [*]const u8, stride: usize, background_rgb: u32, alpha_min: u8) Source {
        return .{
            .pixels = pixels,
            .stride = stride,
            .matte = .{ @truncate(background_rgb >> 16), @truncate(background_rgb >> 8), @truncate(background_rgb) },
            .alpha_min = alpha_min,
        };
    }

    pub fn sample(self: Source, x: usize, y: usize) ?Rgb {
        if (self.alpha_min == 0) return self.at(x, y);
        const base = y * self.stride + x * 4;
        if (self.pixels[base + 3] < self.alpha_min) return null;
        return .{ self.pixels[base], self.pixels[base + 1], self.pixels[base + 2] };
    }

    pub fn at(self: Source, x: usize, y: usize) Rgb {
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
