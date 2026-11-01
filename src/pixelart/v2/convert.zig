const std = @import("std");

const api = @import("../../api/types.zig");
const color = @import("../../common/color.zig");
const Rgb = color.Rgb;
const Source = @import("../../common/source.zig").Source;
const cells_mod = @import("cells.zig");
const grid_mod = @import("grid.zig");
const ink_mod = @import("ink.zig");
const palette_mod = @import("palette.zig");
const regions = @import("regions.zig");

const grid_contrast_min: f64 = 3.0;
const illustration_colors: usize = 32;
const ink_colors: usize = 3;
const ink_min_tolerance: u32 = 24;
const majority_passes: usize = 2;

const Buffers = struct {
    cells: []cells_mod.Cell,
    fills: []Rgb,
    list: []Rgb,
    ink: []bool,
    locked: []bool,
    labels: []u8,
    scratch: []u8,
    component: []u32,
    queue: []usize,
    next: []u8,

    fn init(allocator: std.mem.Allocator, count: usize) !Buffers {
        var result: Buffers = undefined;
        result.cells = try allocator.alloc(cells_mod.Cell, count);
        errdefer allocator.free(result.cells);
        result.fills = try allocator.alloc(Rgb, count);
        errdefer allocator.free(result.fills);
        result.list = try allocator.alloc(Rgb, count);
        errdefer allocator.free(result.list);
        result.ink = try allocator.alloc(bool, count);
        errdefer allocator.free(result.ink);
        result.locked = try allocator.alloc(bool, count);
        errdefer allocator.free(result.locked);
        result.labels = try allocator.alloc(u8, count);
        errdefer allocator.free(result.labels);
        result.scratch = try allocator.alloc(u8, count);
        errdefer allocator.free(result.scratch);
        result.component = try allocator.alloc(u32, count);
        errdefer allocator.free(result.component);
        result.queue = try allocator.alloc(usize, count);
        errdefer allocator.free(result.queue);
        result.next = try allocator.alloc(u8, count);
        return result;
    }

    fn deinit(self: Buffers, allocator: std.mem.Allocator) void {
        allocator.free(self.cells);
        allocator.free(self.fills);
        allocator.free(self.list);
        allocator.free(self.ink);
        allocator.free(self.locked);
        allocator.free(self.labels);
        allocator.free(self.scratch);
        allocator.free(self.component);
        allocator.free(self.queue);
        allocator.free(self.next);
    }
};

const Layout = struct {
    illustration: bool,
    grid_x: grid_mod.Axis,
    grid_y: grid_mod.Axis,
};

fn resolveLayout(
    allocator: std.mem.Allocator,
    source: Source,
    input_width: u32,
    input_height: u32,
    target_width: u32,
    target_height: u32,
    options: *const api.PixelArtOptions,
) !Layout {
    var layout = Layout{
        .illustration = options.mode == @backingInt(api.PixelArtMode.illustration),
        .grid_x = grid_mod.Axis.even(input_width, target_width),
        .grid_y = grid_mod.Axis.even(input_height, target_height),
    };
    const searching = !layout.illustration and
        (options.mode == @backingInt(api.PixelArtMode.auto) or options.grid_fit == 1);
    if (!searching) return layout;

    const profile_x = try allocator.alloc(f64, @max(input_width, 2) - 1);
    defer allocator.free(profile_x);
    const profile_y = try allocator.alloc(f64, @max(input_height, 2) - 1);
    defer allocator.free(profile_y);
    @memset(profile_x, 0);
    @memset(profile_y, 0);
    grid_mod.edgeProfile(source, input_width, input_height, true, profile_x);
    grid_mod.edgeProfile(source, input_width, input_height, false, profile_y);
    const fit_x = grid_mod.fitAxis(profile_x, target_width, input_width, options.grid_search_permille);
    const fit_y = grid_mod.fitAxis(profile_y, target_height, input_height, options.grid_search_permille);

    if (options.mode == @backingInt(api.PixelArtMode.auto)) {
        const strength = @min(grid_mod.contrast(profile_x, target_width, fit_x), grid_mod.contrast(profile_y, target_height, fit_y));
        layout.illustration = strength < grid_contrast_min;
    }
    if (!layout.illustration and options.grid_fit == 1) {
        layout.grid_x = fit_x;
        layout.grid_y = fit_y;
    }
    return layout;
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
    const source = Source.init(source_pixels, input_stride, background_rgb, @intCast(options.alpha_threshold));
    const grid = ink_mod.Grid{ .w = target_width, .h = target_height };
    const count = grid.w * grid.h;

    const buffers = Buffers.init(allocator, count) catch return .out_of_memory;
    defer buffers.deinit(allocator);

    const layout = resolveLayout(allocator, source, input_width, input_height, target_width, target_height, options) catch return .out_of_memory;
    if (layout.illustration) {
        cells_mod.sampleArea(source, input_width, input_height, target_width, target_height, buffers.cells);
    } else {
        cells_mod.sampleGrid(source, input_width, input_height, layout.grid_x, layout.grid_y, target_width, target_height, options.sample_inset_percent, buffers.cells);
    }

    const work = regions.Work{ .next = buffers.next, .component = buffers.component, .queue = buffers.queue };
    if (layout.illustration and options.min_region > 1) {
        regions.dropIslands(grid, buffers.cells, options.min_region, work);
    }

    if (layout.illustration and options.ink_percent > 0) {
        ink_mod.build(grid, buffers.cells, options.ink_percent, buffers.ink);
    } else {
        @memset(buffers.ink, false);
    }

    var colors: [palette_mod.max_colors]Rgb = undefined;
    var ink_palette = palette_mod.Palette{};
    var fill_palette = palette_mod.Palette{};

    var ink_total: usize = 0;
    var fill_total: usize = 0;
    for (buffers.cells, 0..) |cell, index| {
        buffers.fills[index] = cell.fill;
        buffers.locked[index] = buffers.ink[index] or cell.empty;
        if (buffers.ink[index]) {
            buffers.list[ink_total] = cell.ink;
            ink_total += 1;
        }
    }
    palette_mod.build(allocator, buffers.list[0..ink_total], @max(options.color_tolerance, ink_min_tolerance), ink_colors, options.refine_iterations, buffers.scratch, &ink_palette) catch return .out_of_memory;
    for (buffers.cells, 0..) |cell, index| {
        if (buffers.locked[index]) continue;
        buffers.list[fill_total] = cell.fill;
        fill_total += 1;
    }
    const default_limit: usize = if (layout.illustration) illustration_colors else palette_mod.max_colors;
    const wanted: usize = if (options.palette_max != 0) options.palette_max else default_limit;
    palette_mod.build(allocator, buffers.list[0..fill_total], options.color_tolerance, @min(wanted, palette_mod.max_colors - ink_palette.len), options.refine_iterations, buffers.scratch, &fill_palette) catch return .out_of_memory;

    @memcpy(colors[0..ink_palette.len], ink_palette.colors[0..ink_palette.len]);
    @memcpy(colors[ink_palette.len .. ink_palette.len + fill_palette.len], fill_palette.colors[0..fill_palette.len]);
    const total = ink_palette.len + fill_palette.len;

    for (buffers.cells, 0..) |cell, index| {
        buffers.labels[index] = if (buffers.ink[index])
            @intCast(color.nearest(colors[0..ink_palette.len], cell.ink))
        else
            @intCast(ink_palette.len + color.nearest(colors[ink_palette.len..total], cell.fill));
    }

    if (layout.illustration and options.min_region > 1) {
        regions.majority(grid, buffers.labels, buffers.locked, work, majority_passes);
        regions.mergeSmall(grid, buffers.labels, buffers.locked, buffers.fills, colors[0..total], options.min_region, work);
    }

    for (0..count) |index| {
        const empty = buffers.cells[index].empty;
        const output = if (empty) source.matte else colors[buffers.labels[index]];
        @memcpy(destination[index * 4 .. index * 4 + 3], &output);
        destination[index * 4 + 3] = if (empty and options.keep_transparency == 1) 0 else 255;
    }
    return .ok;
}
