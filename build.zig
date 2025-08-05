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

    const lexbor_tests = b.addTest(.{
        .root_source_file = b.path("src/lexbor.zig"),
        .target = target,
        .optimize = optimize,
    });
    addTestDependencies(b, lexbor_tests, wrapper_lib);

    const chunks_tests = b.addTest(.{
        .name = "chunks-tests",
        .root_source_file = b.path("src/chunks.zig"),
        .target = target,
        .optimize = optimize,
    });
    addTestDependencies(b, chunks_tests, wrapper_lib);

    // lexbor_tests.addCSourceFile(.{
    //     .file = b.path("src/minimal.c"),
    //     .flags = &.{"-std=c99"},
    // });

    // lexbor_tests.addIncludePath(b.path("vendor/lexbor/source"));
    // lexbor_tests.addObjectFile(b.path("vendor/lexbor/build/liblexbor_static.a"));
    // lexbor_tests.linkLibrary(wrapper_lib);
    // lexbor_tests.linkLibC();

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    // This allows the user to pass arguments to the application in the build
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);

    const test_lexbor = b.addRunArtifact(lexbor_tests);
    const test_chunks = b.addRunArtifact(chunks_tests);

    var lexbor_test_step = b.step("lexbor-test", "Run lexbor.zig tests");
    lexbor_test_step.dependOn(&test_lexbor.step);

    var chunks_test_step = b.step("chunks-test", "Run chunks.zig tests");
    chunks_test_step.dependOn(&test_chunks.step);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(lexbor_test_step);
    test_step.dependOn(chunks_test_step);
}

fn addTestDependencies(b: *std.Build, test_artifact: *std.Build.Step.Compile, lib: *std.Build.Step.Compile) void {
    test_artifact.addCSourceFile(.{
        .file = b.path("src/minimal.c"),
        .flags = &.{"-std=c99"},
    });
    test_artifact.addIncludePath(b.path("vendor/lexbor/source"));
    test_artifact.addObjectFile(b.path("vendor/lexbor/build/liblexbor_static.a"));
    // test_artifact.linkSystemLibrary("lexbor_static");
    test_artifact.linkLibrary(lib);
    test_artifact.linkLibC();
}
