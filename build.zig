const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ccl_p2p_tst",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "src/cinclude" } });
    exe.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "/opt/rocm/include" } });
    exe.addLibraryPath(.{ .src_path = .{ .owner = b, .sub_path = "/home/user/bkitor/rccl/build/debug" } });
    exe.addLibraryPath(.{ .src_path = .{ .owner = b, .sub_path = "/opt/rocm/lib" } });
    // exe.linkSystemLibrary("hsa-runtime64");
    exe.linkSystemLibrary("amdhip64");
    exe.linkSystemLibrary("rccl");
    // exe.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "/usr/local/cuda/include" } });
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
