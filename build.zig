const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lexbor_static_lib_path = b.path("lexbor_src_2.5.0/build/liblexbor_static.a");
    const lexbor_src_path = b.path("lexbor_src_2.5.0/source");

    // Wrapper library
    const wrapper_lib = b.addLibrary(.{
        .name = "minimal",
        .linkage = .static,
        .root_module = b.createModule(.{
            // .root_source_file = b.path("src/minimal.c"),
            .target = target,
            .optimize = optimize,
        }),
    });
    wrapper_lib.addCSourceFile(.{
        .file = b.path("src/minimal.c"),
        .flags = &.{"-std=c99"},
    });
    wrapper_lib.addIncludePath(lexbor_src_path);
    wrapper_lib.linkLibC();

    const zhtml_module = b.addModule(
        "zhtml",
        .{
            .root_source_file = b.path("src/zhtml.zig"),
            .target = target,
            .optimize = optimize,
        },
    );

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zhtml",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
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
    const lib_test = b.step("test", "Run units tests");

    const unit_tests = b.addTest(.{
        // .name = "unit_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zhtml.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add dependencies to test
    unit_tests.addCSourceFile(.{
        .file = b.path("src/minimal.c"),
        .flags = &.{"-std=c99"},
    });
    unit_tests.addIncludePath(lexbor_src_path);
    unit_tests.addObjectFile(lexbor_static_lib_path);
    unit_tests.linkLibrary(wrapper_lib);
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.skip_foreign_checks = true;
    lib_test.dependOn(&run_unit_tests.step);
}
