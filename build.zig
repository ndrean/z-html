const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wrapper_lib = b.addStaticLibrary(.{
        .name = "minimal",
        .target = target,
        .optimize = optimize,
    });

    wrapper_lib.addCSourceFile(.{
        .file = b.path("src/minimal.c"),
        .flags = &.{"-std=c99"},
    });
    wrapper_lib.addIncludePath(b.path("vendor/lexbor/source"));
    wrapper_lib.linkLibC();

    const exe = b.addExecutable(.{
        .name = "zhtml",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // exe.linkSystemLibrary("lexbor");
    exe.addObjectFile(b.path("vendor/lexbor/build/liblexbor_static.a"));
    // exe.addIncludePath(b.path("vendor/lexbor/source"));
    exe.linkLibC();
    exe.linkLibrary(wrapper_lib);

    b.installArtifact(exe);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/lexbor.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.addCSourceFile(.{
        .file = b.path("src/minimal.c"),
        .flags = &.{"-std=c99"},
    });

    unit_tests.addIncludePath(b.path("vendor/lexbor/source"));
    unit_tests.addObjectFile(b.path("vendor/lexbor/build/liblexbor_static.a"));
    unit_tests.linkLibrary(wrapper_lib);
    unit_tests.linkLibC();

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    // This allows the user to pass arguments to the application in the build
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
