const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const executable = b.addExecutable(.{
        .name = "blockpaint2",
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });
    b.installArtifact(executable);

    const test_step = b.step("test", "Run tests");
    const tests = b.addTest(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    run_tests.step.dependOn(b.getInstallStep());
    test_step.dependOn(&run_tests.step);
}
