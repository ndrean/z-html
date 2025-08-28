// const std = @import("std");

// pub fn build(b: *std.Build) void {
//     const target = b.standardTargetOptions(.{});
//     const optimize = b.standardOptimizeOption(.{});

//     // Create wrapper library
//     const wrapper_lib = createWrapperLib(
//         b,
//         target,
//         optimize,
//     );

//     // Create main executable
//     const exe = createExecutable(
//         b,
//         target,
//         optimize,
//         wrapper_lib,
//     );
//     b.installArtifact(exe);

//     // Create run command
//     const run_cmd = b.addRunArtifact(exe);
//     run_cmd.step.dependOn(b.getInstallStep());
//     if (b.args) |args| {
//         run_cmd.addArgs(args);
//     }
//     const run_step = b.step("run", "Run the example");
//     run_step.dependOn(&run_cmd.step);

//     // Define all test modules
//     const test_modules = [_]TestModule{
//         .{
//             .name = "lexbor-tests",
//             .path = "src/lexbor.zig",
//             .step_name = "lexbor-test",
//             .description = "Run lexbor.zig tests",
//         },
//         .{
//             .name = "chunks-tests",
//             .path = "src/chunks.zig",
//             .step_name = "chunks-test",
//             .description = "Run chunks.zig tests",
//         },
//         .{
//             .name = "css-tests",
//             .path = "src/css_selectors.zig",
//             .step_name = "css-test",
//             .description = "Run CSS selector tests",
//         },
//         // Add more modules here as needed
//     };

//     // Create all test artifacts and steps
//     const all_test_steps = createAllTests(
//         b,
//         target,
//         optimize,
//         wrapper_lib,
//         &test_modules,
//     );

//     // master test step that runs all tests
//     const test_step = b.step("test", "Run all tests");
//     for (all_test_steps) |step| {
//         test_step.dependOn(step);
//     }
// }

// //=============================================================================
// // HELPER TYPES AND FUNCTIONS
// //=============================================================================

// const TestModule = struct {
//     name: []const u8,
//     path: []const u8,
//     step_name: []const u8,
//     description: []const u8,
// };

// fn createWrapperLib(
//     b: *std.Build,
//     target: std.Build.ResolvedTarget,
//     optimize: std.builtin.OptimizeMode,
// ) *std.Build.Step.Compile {
//     const wrapper_lib = b.addStaticLibrary(.{
//         .name = "minimal",
//         .target = target,
//         .optimize = optimize,
//     });

//     wrapper_lib.addCSourceFile(.{
//         .file = b.path("src/minimal.c"),
//         .flags = &.{"-std=c99"},
//     });
//     wrapper_lib.addIncludePath(b.path("vendor/lexbor/source"));
//     wrapper_lib.linkLibC();

//     return wrapper_lib;
// }

// fn createExecutable(
//     b: *std.Build,
//     target: std.Build.ResolvedTarget,
//     optimize: std.builtin.OptimizeMode,
//     wrapper_lib: *std.Build.Step.Compile,
// ) *std.Build.Step.Compile {
//     const exe = b.addExecutable(.{
//         .name = "zhtml",
//         .root_source_file = b.path("src/main.zig"),
//         .target = target,
//         .optimize = optimize,
//     });

//     exe.addObjectFile(b.path("vendor/lexbor/build/liblexbor_static.a"));
//     exe.linkLibC();
//     exe.linkLibrary(wrapper_lib);

//     return exe;
// }

// fn createAllTests(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, wrapper_lib: *std.Build.Step.Compile, modules: []const TestModule) []*std.Build.Step {
//     var test_steps = std.ArrayList(*std.Build.Step).init(b.allocator);

//     for (modules) |module| {
//         // Create test artifact
//         const test_artifact = b.addTest(.{
//             .name = module.name,
//             .root_source_file = b.path(module.path),
//             .target = target,
//             .optimize = optimize,
//         });

//         // Add dependencies
//         addTestDependencies(b, test_artifact, wrapper_lib);

//         // Create run artifact
//         const run_test = b.addRunArtifact(test_artifact);

//         // Create step
//         const test_step = b.step(module.step_name, module.description);
//         test_step.dependOn(&run_test.step);

//         // Add to collection
//         test_steps.append(&run_test.step) catch @panic("OOM");

//         std.debug.print("Added test module: {s} -> {s}\n", .{ module.name, module.step_name });
//     }

//     return test_steps.toOwnedSlice() catch @panic("OOM");
// }

// fn addTestDependencies(b: *std.Build, test_artifact: *std.Build.Step.Compile, lib: *std.Build.Step.Compile) void {
//     test_artifact.addCSourceFile(.{
//         .file = b.path("src/minimal.c"),
//         .flags = &.{"-std=c99"},
//     });
//     test_artifact.addIncludePath(b.path("vendor/lexbor/source"));
//     test_artifact.addObjectFile(b.path("vendor/lexbor/build/liblexbor_static.a"));
//     test_artifact.linkLibrary(lib);
//     test_artifact.linkLibC();
// }
