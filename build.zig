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

    // Link Lexbor C library
    // const lexbor_lib = b.addStaticLibrary(.{
    //     .name = "lexbor",
    //     .target = target,
    //     .optimize = optimize,
    // });
    // lexbor_lib.addIncludePath(b.path("vendor/lexbor/build/liblexbor_static.a"));
    // lexbor_lib.addCSourceFile(.{ .file = b.path("vendor/lexbor/source") });
    // lexbor_lib.linkLibC();

    const exe = b.addExecutable(.{
        .name = "zhtml",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // exe.linkSystemLibrary("lexbor");
    exe.addObjectFile(b.path("vendor/lexbor/build/liblexbor_static.a"));
    exe.addIncludePath(b.path("vendor/lexbor/src"));
    exe.linkLibC();
    exe.linkLibrary(wrapper_lib);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);
}
