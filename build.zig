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
        .version = .{ .major = 0, .minor = 1, .patch = 2 },
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

    b.installFile("include/madeitpx.h", "include/madeitpx.h");

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const c_test_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });
    c_test_module.addCSourceFile(.{
        .file = b.path("tests/test_abi.c"),
        .flags = &.{},
    });
    c_test_module.addIncludePath(b.path("include"));
    c_test_module.linkLibrary(static);
    c_test_module.link_libc = true;

    const c_test = b.addExecutable(.{
        .name = "test_abi",
        .root_module = c_test_module,
    });
    const run_c_test = b.addRunArtifact(c_test);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_c_test.step);
}
