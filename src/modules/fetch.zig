const std = @import("std");
const z = @import("../zhtml.zig");

const testing = std.testing;

pub fn fetchTest(allocator: std.mem.Allocator) !void {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(allocator);
    const outw = std.Io.Writer;

    const uri = try std.Uri.parse("https://example.com");
    const response = try client.fetch(.{
        .method = .GET,
        .uri = uri,
        .payload = .{ .writer = outw },
        .headers = .{
            .accept_encoding = .{ .override = "tet/html" },
        },
    });
    std.debug.print("Response: {}\n", .{response});
    outw.flush();
}

test "fetch" {
    const allocator = std.testing.allocator;
    try fetchTest(allocator);
}
