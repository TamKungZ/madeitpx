const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const shared = b.addLibrary(.{
        .name = "madeitpx",
        .linkage = .dynamic,
        .root_module = root_module,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    b.installArtifact(shared);

    const static = b.addLibrary(.{
        .name = "madeitpx",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(static);

}
