const std = @import("std");
const testing = std.testing;
const z = @import("src/zhtml.zig");

test "parseFragmentInto cross-document cloning" {
    const allocator = testing.allocator;

    // Create two separate documents
    const main_doc = try z.createDocument();
    defer z.destroyDocument(main_doc);

    const fragment_doc = try z.createDocument();
    defer z.destroyDocument(fragment_doc);

    // Create a container element in the main document
    const container = try z.createElement(main_doc, "div");

    // Parse a fragment and try to inject it into the main document
    const fragment_html = "<p>Hello from fragment</p><span>Another element</span>";
    const fragment_result = try z.parseFragment(allocator, fragment_html, .body);
    defer fragment_result.deinit();

    // This should work with cross-document cloning
    try z.parseFragmentInto(allocator, fragment_html, .body, main_doc, container);

    // Check that elements were added to container
    const children = try z.getChildren(allocator, container);
    defer allocator.free(children);

    try testing.expect(children.len == 2);
    try testing.expectEqualStrings("P", z.tagName(children[0]));
    try testing.expectEqualStrings("SPAN", z.qualifiedName(children[1]));

    const p_text = try z.getTextContent(allocator, children[0]);
    defer allocator.free(p_text);
    try testing.expectEqualStrings("Hello from fragment", p_text);
}

test "table fragment context parsing" {
    const allocator = testing.allocator;

    const table_fragment =
        \\<tr>
        \\  <td>John Doe</td>
        \\  <td>Engineer</td>
        \\</tr>
    ;

    const result = try z.parseFragment(allocator, table_fragment, .table);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    std.debug.print("Table elements found: {}\n", .{elements.len});
    for (elements, 0..) |element, i| {
        std.debug.print("Element {}: {s}\n", .{ i, z.tagName(element) });
    }

    // lexbor might wrap TR in TBODY for table context
    try testing.expect(elements.len >= 1);

    const first_tag = z.tagName(elements[0]);
    if (std.mem.eql(u8, first_tag, "TBODY")) {
        // Auto-wrapped in TBODY
        const tbody_children = try z.getChildren(allocator, elements[0]);
        defer allocator.free(tbody_children);
        try testing.expect(tbody_children.len == 1); // One TR element
        try testing.expectEqualStrings("TR", z.tagName(tbody_children[0]));
    } else {
        // Direct TR element
        try testing.expectEqualStrings("TR", z.tagName(elements[0]));
    }
}
