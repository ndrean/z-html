const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lexbor_static_lib_path = b.path("lexbor_src_2.5.0/build/liblexbor_static.a");
    const lexbor_src_path = b.path("lexbor_src_2.5.0/source");

    // Wrapper library
    const wrapper_lib = b.addStaticLibrary(.{
        .name = "minimal",
        .target = target,
        .optimize = optimize,
    });
    wrapper_lib.addCSourceFile(.{ .file = b.path("src/minimal.c"), .flags = &.{"-std=c99"} });
    wrapper_lib.addIncludePath(lexbor_src_path);
    wrapper_lib.linkLibC();

    const zhtml_module = b.addModule("zhtml", .{
        .root_source_file = b.path("src/zhtml.zig"),
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zhtml",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zhtml", zhtml_module);
    exe.addObjectFile(lexbor_static_lib_path);
    exe.linkLibC();
    exe.linkLibrary(wrapper_lib);
    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);

    // SINGLE TEST TARGET - this runs ALL tests from all modules
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/zhtml.zig"), // Main library file
        .target = target,
        .optimize = optimize,
    });

    // Add dependencies to test
    lib_tests.addCSourceFile(.{
        .file = b.path("src/minimal.c"),
        .flags = &.{"-std=c99"},
    });
    lib_tests.addIncludePath(lexbor_src_path);
    lib_tests.addObjectFile(lexbor_static_lib_path);
    lib_tests.linkLibrary(wrapper_lib);
    lib_tests.linkLibC();

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run all library tests");
    test_step.dependOn(&run_lib_tests.step);
}
