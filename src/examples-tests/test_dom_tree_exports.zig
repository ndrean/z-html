const std = @import("std");
const z = @import("zhtml");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const html = "<html><head><title>Test</title></head><body><h1>Hello</h1><p>World</p></body></html>";

    // Test parsing HTML
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test DOM tree conversion
    const tree: z.DomTreeNode = try z.fulldocumentToTupleTree(allocator, doc);
    defer z.freeDomTreeNode(allocator, tree);

    std.debug.print("DOM tree conversion successful!\n", .{});
    std.debug.print("Tree root is an element\n", .{});

    // Test round-trip conversion
    const result = try z.roundTripConversion(allocator, html);
    defer allocator.free(result);

    std.debug.print("Round-trip conversion successful!\n", .{});
    std.debug.print("Result: {s}\n", .{result});
}
