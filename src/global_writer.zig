// //! Comptime print: Debug or stdout or log in a file

// const std = @import("std");
// const builtin = @import("builtin");

// pub const GlobalWriter = struct {
//     var file: ?std.fs.File = null;
//     var writer: ?std.fs.File.Writer = null;

//     pub fn initLog(path: []const u8) !void {
//         // Open file for append or create if not existing
//         const f = try std.fs.cwd().createFile(path, .{
//             .truncate = false,
//             .read = false,
//         });
//         file = f;
//         writer = f.writer();
//     }

//     pub fn deinitLog() void {
//         if (file) |f| {
//             f.close();
//         }
//         file = null;
//         writer = null;
//     }

//     pub fn print(comptime fmt: []const u8, args: anytype) void {
//         if (builtin.mode == .Debug) {
//             std.debug.print(fmt, args);
//         } else {
//             std.io.getStdOut().writer().print(fmt, args) catch {};
//         }
//     }

//     pub fn log(comptime fmt: []const u8, args: anytype) void {
//         // Empty for now - can be implemented later for file logging
//         if (writer) |w| {
//             w.print(fmt, args) catch {};
//         } else {
//             // fallback if log not initialized
//             std.io.getStdOut().writer().print(fmt, args) catch {};
//         }
//     }
// };
