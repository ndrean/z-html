const std = @import("std");
const z = @import("../zhtml.zig");

test "DOM traversal utilities" {
    const allocator = std.testing.allocator;

    // Parse some HTML
    const html = "<div><p>Hello</p><span>World</span><p>Again</p></div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.getDocumentBodyElement(doc);
    const div = z.firstElementChild(body).?;

    std.debug.print("\n=== Testing forEach traversal ===\n", .{});

    // Simple callback that works
    const testCallback = struct {
        fn call(element: *z.DomElement) bool {
            const tag = z.getElementName(element);
            std.debug.print("Found element: {s}\n", .{tag});
            return true;
        }
    }.call;

    z.forEachChildElement(div, testCallback);

    std.debug.print("\n=== Testing collect for specific elements ===\n", .{});

    // Test the collector function
    const pCollector = struct {
        fn collect(element: *z.DomElement) ?*z.DomElement {
            if (z.matchesTagName(element, "P")) {
                return element;
            }
            return null;
        }
    }.collect;

    const p_elements = try z.collectChildElements(allocator, div, *z.DomElement, pCollector);
    defer allocator.free(p_elements);

    std.debug.print("Found {} P elements\n", .{p_elements.len});
    try std.testing.expect(p_elements.len == 2);

    std.debug.print("\n=== Testing matcher utilities ===\n", .{});

    // Test matchers
    var child = z.firstElementChild(div);
    while (child) |element| {
        const tag = z.getElementName(element);
        std.debug.print("Element {s}: is P? {}, is SPAN? {}\n", .{ tag, z.matchesTagName(element, "P"), z.matchesTagName(element, "SPAN") });
        child = z.nextElementSibling(element);
    }
}
