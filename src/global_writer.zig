//! Comptime print: Debug or stdout or log in a file

const std = @import("std");
const builtin = @import("builtin");

pub const GlobalWriter = struct {
    pub fn print(comptime fmt: []const u8, args: anytype) void {
        if (builtin.mode == .Debug) {
            std.debug.print(fmt, args);
        } else {
            std.io.getStdOut().writer().print(fmt, args) catch {};
        }
    }

    pub fn log(comptime fmt: []const u8, args: anytype) void {
        // Empty for now - can be implemented later for file logging
        _ = fmt;
        _ = args;
    }
};
