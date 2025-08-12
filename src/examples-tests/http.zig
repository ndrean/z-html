const std = @import("std");
pub fn request(allocator: std.mem.Allocator, url: []const u8, mime: []const u8) !void {
    // Create the client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Initialize an array list that we will use for storage of the response body
    var body = std.ArrayList(u8).init(allocator);
    defer body.deinit();

    // Parse a URI. Conversely the "location" field below will also
    // accept a URL string, but using URI here for clarity.
    const uri = try std.Uri.parse(url);

    // Make the request
    const response = try client.fetch(.{
        .method = .GET,
        .location = .{ .uri = uri },
        .response_storage = .{ .dynamic = &body },
        .headers = .{
            .accept_encoding = .{ .override = mime },
        },
    });

    // Do whatever you need to in case of HTTP error.
    if (response.status != .ok) {
        @panic("Handle errors");
    }
    return;
}
