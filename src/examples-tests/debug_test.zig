const std = @import("std");
const zhtml = @import("../zhtml.zig");

pub fn main() !void {
    const html =
        \\<div id="test">
        \\  <p id="para">Hello</p>
        \\</div>
    ;

    const doc = try zhtml.printDocStruct(html);
    defer zhtml.destroyDocument(doc);

    std.debug.print("Document parsed successfully\n", .{});

    // Try getElementsByAttributeName with smaller capacity
    const id_elements = try zhtml.getElementsByAttributeName(doc, "id", 2);
    if (id_elements) |collection| {
        defer zhtml.destroyCollection(collection);
        const count = zhtml.collectionLength(collection);
        std.debug.print("Found {} elements with 'id' attribute\n", .{count});
    } else {
        std.debug.print("Failed to create collection\n", .{});
    }
}
