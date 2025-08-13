// =============================================================================
// Serialization Nodes and Elements
// =============================================================================

const std = @import("std");
const z = @import("zhtml.zig");
const Err = @import("errors.zig").LexborError;

const testing = std.testing;
const print = std.debug.print;

pub const lxbString = extern struct {
    data: ?[*]u8, // Pointer to string data
    length: usize, // String length
    size: usize, // Allocated size
};

extern "c" fn lxb_html_serialize_tree_str(node: *z.DomNode, str: *lxbString) usize;
extern "c" fn lxb_html_serialize_str(node: *z.DomNode, str: *lxbString) usize;
extern "c" fn lxb_html_element_inner_html_set(body: *z.DomElement, inner: [*]const u8, inner_len: usize) *z.DomElement;

/// [Serialize] Serialize the node tree (most common use case).
///
/// Caller needs to free the returned slice.
pub fn serializeTree(allocator: std.mem.Allocator, node: *z.DomNode) ![]u8 {
    var str: lxbString = .{
        .data = null,
        .length = 0,
        .size = 0,
    };

    const status = lxb_html_serialize_tree_str(node, &str);
    if (status != z.LXB_STATUS_OK) {
        return Err.SerializeFailed;
    }

    if (str.data == null or str.length == 0) {
        return Err.NoBodyElement;
    }

    // to Zig-managed memory
    const result = try allocator.alloc(u8, str.length);
    @memcpy(result, str.data.?[0..str.length]);

    // Note: We don't free str.data - lexbor manages it internally?
    return result;
}

/// [Serialize] Serializes only the current node
///
/// Caller needs to free the returned slice.
pub fn serializeNode(allocator: std.mem.Allocator, node: *z.DomNode) ![]u8 {
    var str: lxbString = .{
        .data = null,
        .length = 0,
        .size = 0,
    };

    const status = lxb_html_serialize_str(node, &str);
    if (status != z.LXB_STATUS_OK) {
        return Err.SerializeFailed;
    }

    if (str.data == null or str.length == 0) {
        return Err.NoBodyElement;
    }

    const result = try allocator.alloc(u8, str.length);
    @memcpy(result, str.data.?[0..str.length]);

    return result;
}

/// [Serialize] Serializes the HTMLElement tree
///
/// Caller needs to free the returned slice.
pub fn serializeElement(allocator: std.mem.Allocator, element: *z.DomElement) ![]u8 {
    const node = z.elementToNode(element);
    return try serializeTree(allocator, node);
}

// -------------------------------------------------------------------------------------
// Inner - Outer HTML
// -------------------------------------------------------------------------------------

/// [Serialize] Get element's inner HTML
///
/// Caller needs to free the returned slice
pub fn innerHtml(allocator: std.mem.Allocator, element: *z.DomElement) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    const element_node = z.elementToNode(element);

    // Serialize all child nodes (excluding the element itself)
    var child = z.firstChild(element_node);
    while (child != null) {
        const child_html = try serializeTree(allocator, child.?);
        defer allocator.free(child_html);

        try result.appendSlice(child_html);

        child = z.nextSibling(child.?);
    }

    return result.toOwnedSlice();
}

/// [Serialize] Sets / replaces element's inner HTML.
///
/// Returns the updated element
pub fn setInnerHtml(element: *z.DomElement, inner: []const u8) *z.DomElement {
    return lxb_html_element_inner_html_set(
        element,
        inner.ptr,
        inner.len,
    );
}

/// [Serialize] Gets element's outer HTML (including the element itself)
///
/// Caller needs to free the returned slice
pub fn getElementOuterHTML(allocator: std.mem.Allocator, element: *z.DomElement) ![]u8 {
    return try serializeElement(allocator, element);
}

test "innerHTML functionality" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Create a container element
    const div = try z.createElement(
        doc,
        "div",
        &.{},
    );

    // test 1 --------------
    _ = setInnerHtml(div, "<p>Hello World</p>");
    const inner1 = try innerHtml(allocator, div);
    defer allocator.free(inner1);

    try testing.expect(
        std.mem.indexOf(u8, inner1, "<p>Hello World</p>") != null,
    );

    const complex_html =
        \\<h1>Title</h1>
        \\<p class="intro">Introduction paragraph</p>
        \\<ul>
        \\
        \\  <li>Item 1</li>
        \\  <li>Item 2</li>
        \\</ul>
    ;

    // test 2 --------------
    _ = setInnerHtml(div, complex_html);

    const inner2 = try innerHtml(allocator, div);
    defer allocator.free(inner2);

    try testing.expect(
        std.mem.indexOf(u8, inner2, "<h1>Title") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, inner2, "<ul>") != null,
    );
    // removed old inner HTML
    try testing.expect(
        std.mem.indexOf(u8, inner2, "<p>Hello World</p>") == null,
    );

    // Test 3: Get outer HTML (includes the div itself) --------------
    const outer = try getElementOuterHTML(allocator, div);
    defer allocator.free(outer);

    try testing.expect(
        std.mem.indexOf(u8, outer, "<div>") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, outer, "</div>") != null,
    );

    // const txt = try serializeElement(allocator, div);
    // defer allocator.free(txt);
}

test "set innerHTML" {
    const allocator = std.testing.allocator;
    const html = "<div><span>blah-blah-blah</div>";
    const inner = "<ul><li>1<li>2<li>3</ul>";
    const doc = try z.parseFromString(html);
    const body = try z.getBodyElement(doc);
    const div_elt = z.firstElementChild(body);
    defer z.destroyDocument(doc);

    const inner_html = try serializeElement(allocator, div_elt.?);
    defer allocator.free(inner_html);

    try testing.expectEqualStrings(
        inner_html,
        "<div><span>blah-blah-blah</span></div>",
    );

    const element = setInnerHtml(div_elt.?, inner);
    const serialized = try serializeElement(allocator, element);
    defer allocator.free(serialized);

    try testing.expectEqualStrings(
        serialized,
        "<div><ul><li>1</li><li>2</li><li>3</li></ul></div>",
    );

    const set_new_body = setInnerHtml(
        body,
        "<p>New body content</p>",
    );
    const new_body_html = try serializeElement(allocator, set_new_body);
    defer allocator.free(new_body_html);

    try testing.expectEqualStrings(
        new_body_html,
        "<body><p>New body content</p></body>",
    );
}

test "direct serialization" {
    const allocator = testing.allocator;
    const fragment = "<div><p>Hi <strong>there</strong></p></div>";
    const doc = try z.parseFromString(fragment);
    defer z.destroyDocument(doc);

    const body_node = try z.getBodyNode(doc);

    if (z.firstChild(body_node)) |div_node| {
        const serialized = try serializeTree(allocator, div_node);
        defer allocator.free(serialized);

        try testing.expect(
            std.mem.indexOf(u8, serialized, "<div>") != null,
        );
        try testing.expect(
            std.mem.indexOf(u8, serialized, "there") != null,
        );
    }
}

test "serialize Node vs tree functionality" {
    const allocator = testing.allocator;
    const fragment = "<div id=\"my-div\"><p class=\"bold\">Hello <strong>World</strong></p>   </div>";
    const doc = try z.parseFromString(fragment);
    defer z.destroyDocument(doc);

    const body = try z.getBodyElement(doc);
    const body_node = z.elementToNode(body);

    // Get the div element
    const div_node = z.firstChild(body_node) orelse {
        try testing.expect(false); // Should have div
        return;
    };

    // Test serializeNode vs serializeTree difference
    const node_html = try serializeNode(allocator, div_node);
    defer allocator.free(node_html);

    const tree_html = try serializeTree(
        allocator,
        div_node,
    );
    defer allocator.free(tree_html);

    // Both should contain the div tag
    try testing.expect(
        std.mem.indexOf(u8, node_html, "div") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, tree_html, "div") != null,
    );

    // Node_html contains only "<div id='my-div'>"
    try testing.expect(
        std.mem.indexOf(u8, node_html, "<p>") == null,
    );
    try testing.expectEqualStrings(
        "<div id=\"my-div\">",
        node_html,
    );
    // Tree should definitely contain all content
    try testing.expect(
        std.mem.indexOf(u8, tree_html, "Hello") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, tree_html, "<strong>World</strong>") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, tree_html, "class=\"bold\"") != null,
    );
}

// test "serializeNode on elements only" {
//     const allocator = testing.allocator;

//     const fragment =
//         \\<div id="container">
//         \\
//         \\  <h1 class="title">Heading</h1>\t
//         \\  <p class="content">Paragraph text</p>
//         \\  <ul id="list">\n
//         \\    <li>Item 1</li>
//         \\    <li class="special">Item 2</li>
//         \\  </ul>
//         \\</div>
//     ;

//     const doc = try z.parseFromString(fragment);
//     defer z.destroyDocument(doc);
//     z.printDocumentStructure(doc);

//     const body = z.getBodyElement(doc).?;
//     const body_node = z.elementToNode(body);
//     const container_node = z.firstChild(body_node).?;

//     // Walk children and only process ELEMENT nodes
//     var current_child = z.firstChild(container_node);
//     var element_count: u32 = 0;

//     while (current_child != null) {
//         // const element_name = z.getNodeName(current_child.?);

//         // print("Found node: '{s}'\n", .{element_name});

//         // Only process if it's an actual element (not #text)
//         if (z.nodeToElement(current_child.?)) |element| {
//             // const elt_name = z.getElementName(element);
//             // print("Processing element: '{s}'\n", .{elt_name});

//             const serialized = try serializeNode(allocator, current_child.?);
//             defer allocator.free(serialized);

//             // const trimmed = std.mem.trim(
//             //     u8,
//             //     serialized,
//             //     &std.ascii.whitespace,
//             // );
//             // const isEmpty = trimmed.len == 0;
//             // const isWhitespace = z.isWhitepaceOnlyText(trimmed);

//             // print("Element '{s}' serialized: '{s}, is empty?: {}, is whitespace?: {}'\n", .{ elt_name, trimmed, isEmpty, isWhitespace });

//             element_count += 1;
//         } else {
//             // print("Skipping text node: '{s}'\n", .{element_name});
//         }

//         current_child = z.getNodeNextSiblingcurrent_child.?);
//     }

//     // print("Found {} element nodes\n", .{element_count});
//     try testing.expect(element_count >= 3); // h1, p, ul
// }

test "behaviour of serializeNode" {
    const allocator = testing.allocator;

    // Test different types of elements
    const test_cases = [_]struct {
        html: []const u8,
        serialized_node: []const u8,
        serialized_tree: []const u8,
    }{
        // self-closing tags
        .{
            .html = "<br/>",
            .serialized_node = "<br>",
            .serialized_tree = "<br>",
        },
        .{
            .html = "<img src=\"my-image\"/>",
            .serialized_node = "<img src=\"my-image\">",
            .serialized_tree = "<img src=\"my-image\">",
        },
        .{
            .html = "<p><span></span></p>",
            .serialized_node = "<p>",
            .serialized_tree = "<p><span></span></p>",
        },
        .{
            .html = "<p></p>",
            .serialized_node = "<p>",
            .serialized_tree = "<p></p>",
        },
        .{
            .html = "<div data-id=\"myid\" class=\"test\">Simple text</div>",
            .serialized_node = "<div data-id=\"myid\" class=\"test\">",
            .serialized_tree = "<div data-id=\"myid\" class=\"test\">Simple text</div>",
        },
    };

    for (test_cases) |case| {
        const doc = try z.parseFromString(case.html);
        defer z.destroyDocument(doc);

        const body = try z.getBodyElement(doc);
        const body_node = z.elementToNode(body);
        const element_node = z.firstChild(body_node).?;

        const serial_node = try serializeNode(allocator, element_node);
        defer allocator.free(serial_node);

        const serialized_tree = try serializeTree(allocator, element_node);
        defer allocator.free(serialized_tree);

        try testing.expectEqualStrings(serial_node, case.serialized_node);
        try testing.expectEqualStrings(serialized_tree, case.serialized_tree);
    }
}

test "serializeNode vs serializeTree comparison" {
    const allocator = testing.allocator;

    const fragment = "<article><header>Title</header><section>Content <span>inside</span></section></article>";

    const doc = try z.parseFromString(fragment);
    defer z.destroyDocument(doc);

    const body = try z.getBodyElement(doc);
    const body_node = z.elementToNode(body);
    const article_node = z.firstChild(body_node).?;

    // Serialize the article element
    const node_result = try serializeNode(allocator, article_node);
    defer allocator.free(node_result);

    const tree_result = try serializeTree(allocator, article_node);
    defer allocator.free(tree_result);

    try testing.expect(node_result.len == 9);
    try testing.expect(tree_result.len == 87);

    try testing.expectEqualStrings(node_result, "<article>");
    try testing.expectEqualStrings(tree_result, fragment);

    // Both should contain the article tag
    try testing.expect(std.mem.indexOf(u8, node_result, "article") != null);
    try testing.expect(std.mem.indexOf(u8, tree_result, "article") != null);

    // Tree should definitely contain all nested content
    try testing.expect(std.mem.indexOf(u8, tree_result, "Title") != null);
    try testing.expect(std.mem.indexOf(u8, tree_result, "Content") != null);
    try testing.expect(std.mem.indexOf(u8, tree_result, "<span>inside</span>") != null);
}
