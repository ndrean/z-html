// compile time safety check
const std = @import("std");
const z = @import("zhtml.zig");

const testing = std.testing;
const print = std.debug.print;

pub const HtmlTag = enum {
    // Common HTML5 elements
    div,
    p,
    span,
    a,
    img,
    br,
    hr,
    h1,
    h2,
    h3,
    h4,
    h5,
    h6,
    ul,
    ol,
    li,
    table,
    tr,
    td,
    th,
    thead,
    tbody,
    form,
    input,
    button,
    textarea,
    select,
    option,
    script,
    style,
    link,
    meta,
    title,
    head,
    body,
    html,
    section,
    article,
    header,
    footer,
    nav,
    aside,
    main,
    strong,
    em,
    b,
    i,
    u,
    s,
    pre,
    code,
    blockquote,
    canvas,
    svg,
    video,
    audio,
    source,
    pub fn toString(self: HtmlTag) []const u8 {
        return @tagName(self);
    }
};

test "HtmlTag edge cases" {
    // const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Test all enum variants work
    const tags = [_]z.HtmlTag{ .div, .p, .span, .a, .img, .br, .h1, .h2 };

    for (tags) |tag| {
        const element = try z.createElement(doc, .{ .tag = tag });
        const node_name = z.getNodeName(z.elementToNode(element));
        const expected_name = tag.toString();

        // print("Created: {s} -> DOM name: {s}\n", .{ expected_name, node_name });

        // Note: DOM names are typically uppercase
        try testing.expect(std.ascii.eqlIgnoreCase(expected_name, node_name));
    }

    // print("✅ All enum tags work correctly!\n", .{});
}

test "mixing enum and string creation" {
    // const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Type-safe enum creation
    const div = try z.createElement(
        doc,
        .{ .tag = .div },
    );

    // Flexible string creation (for custom elements)
    const custom = try z.createElement(
        doc,
        .{ .custom = "my-custom-element" },
    );
    const web_component = try z.createElement(
        doc,
        .{ .custom = "x-widget" },
    );

    // Verify they work
    try testing.expectEqualStrings("DIV", z.getNodeName(z.elementToNode(div)));
    try testing.expectEqualStrings("MY-CUSTOM-ELEMENT", z.getNodeName(z.elementToNode(custom)));
    try testing.expectEqualStrings("X-WIDGET", z.getNodeName(z.elementToNode(web_component)));

    // print("✅ Both enum and string creation work!\n", .{});
}
