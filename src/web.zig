const std = @import("std");

const root = @import("root.zig");

comptime {
    _ = root;
}

const allocator = std.heap.wasm_allocator;

export fn madeitpx_web_alloc(size: usize) usize {
    const memory = allocator.alignedAlloc(u8, .@"16", size) catch return 0;
    return @intFromPtr(memory.ptr);
}

export fn madeitpx_web_free(pointer: usize, size: usize) void {
    if (pointer == 0) return;
    const memory: [*]align(16) u8 = @ptrFromInt(pointer);
    allocator.free(memory[0..size]);
}

export fn madeitpx_web_convert(
    input_pointer: usize,
    input_size: usize,
    input_width: u32,
    input_height: u32,
    target_width: u32,
    target_height: u32,
    preset: u32,
    palette_colors: u32,
    background_rgb: u32,
    sample_mode: u32,
    cluster_cleanup: u32,
    output_pointer: usize,
    output_capacity: usize,
) u32 {
    const options = root.Options{
        .struct_size = @sizeOf(root.Options),
        .preset = preset,
        .palette_colors = palette_colors,
        .background_rgb = background_rgb,
        .sample_mode = sample_mode,
        .cluster_cleanup = cluster_cleanup,
        .reserved = 0,
    };
    const input: [*]const u8 = @ptrFromInt(input_pointer);
    const output: [*]u8 = @ptrFromInt(output_pointer);
    const status = root.madeitpx_convert_rgba8(
        input,
        input_size,
        input_width,
        input_height,
        @as(usize, input_width) * 4,
        target_width,
        target_height,
        &options,
        output,
        output_capacity,
    );
    return @intCast(@backingInt(status));
}
