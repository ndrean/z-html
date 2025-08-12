//! Dom_tree module
//! This module provides functions to:
//! - convert DOM nodes to a tuple-like or JSON tree structure
//! - convert a tuple-like or JSON tree structure back to DOM nodes

const std = @import("std");
const z = @import("zhtml.zig");
const html_tags = @import("html_tags.zig");
const Err = z.LexborError;

const print = std.debug.print;
const testing = std.testing;
const writer = std.io.getStdOut().writer();

/// Represents different types of HTML nodes as tuples
///
/// - Elements are in the form `{tag_name, attributes, children}`
///
/// - Text nodes such are in the form `{text_content}`
///
/// - Comment nodes are in the form `{"comment", text_content}`
pub const HtmlNode = union(enum) {
    /// Element: {tag_name, attributes, children}
    element: struct {
        tag: []const u8,
        attributes: []z.AttributePair,
        children: []HtmlNode,
    },

    /// Text content: "text content"
    text: []const u8,

    /// Comment: {tag: "comment", text: "comment text"}
    comment: struct { tag: []const u8, text: []const u8 },
};

/// JSON-friendly DOM node representation (popular format)
///
///- Elements are in the form `{tag_name, attributes, children}`
///
/// - Text nodes such are in the form `{text_content}`
///
/// - Comment nodes are in the form `{"comment", text_content}`
pub const JsonNode = union(enum) {
    /// Element: {"tagName": "div", "attributes": {...}, "children": [...]}
    element: struct {
        tagName: []const u8,
        attributes: std.StringHashMap([]const u8),
        children: []JsonNode,
    },

    /// Text node: {"text": "content"}
    text: struct { text: []const u8 },

    /// Comment node: {"comment": "comment text"}
    comment: struct { comment: []const u8 },
};

/// Top-level tree (array of nodes)
pub const HtmlTree = []HtmlNode;

/// Top-level JSON tree (array of JSON nodes)
pub const JsonTree = []JsonNode;

/// [tree] Convert DOM node to HtmlNode recursively
pub fn domNodeToTree(allocator: std.mem.Allocator, node: *z.DomNode) !HtmlNode {
    const node_type = z.getType(node);

    switch (node_type) {
        .element => {
            const element = z.nodeToElement(node).?;
            // Use the owned version for safety
            const tag_name = try z.getNodeNameOwned(allocator, node);

            const elt_attrs = try z.getAttributes(allocator, element);

            // Convert child nodes recursively
            var children_list = std.ArrayList(HtmlNode).init(allocator);
            defer children_list.deinit();

            // Traverse child nodes

            var child = z.firstChild(node);
            while (child != null) {
                const child_tree = try domNodeToTree(allocator, child.?);
                try children_list.append(child_tree);
                child = z.nextSibling(child.?);
            }

            return HtmlNode{
                .element = .{
                    .tag = tag_name,
                    .attributes = elt_attrs,
                    .children = try children_list.toOwnedSlice(),
                },
            };
        },

        .text => {
            const text_content = try z.getNodeTextContentsOpts(
                allocator,
                node,
                .{}, // options, e.g.: .{ .escape = true },
            );
            return HtmlNode{ .text = text_content };
        },

        .comment => {
            const comment: *z.Comment = @ptrCast(node);
            const comment_content = try z.getCommentTextContent(allocator, comment);
            return HtmlNode{
                .comment = .{
                    .tag = try allocator.dupe(u8, "comment"),
                    .text = comment_content,
                },
            };
        },

        else => {
            // Skip other node types (return empty text)
            return HtmlNode{ .text = try allocator.dupe(u8, "") };
        },
    }
}

/// [json] Convert DOM node to JSON-friendly format
pub fn domNodeToJson(allocator: std.mem.Allocator, node: *z.DomNode) !JsonNode {
    const node_type = z.getType(node);

    switch (node_type) {
        .element => {
            const element = z.nodeToElement(node).?;
            const tag_name = try z.getNodeNameOwned(allocator, node);

            // Convert attributes to HashMap for JSON-friendly format
            var attributes = std.StringHashMap([]const u8).init(allocator);
            const elt_attrs = try z.getAttributes(allocator, element);
            defer {
                // Free the original attributes array since we're copying to HashMap
                for (elt_attrs) |attr| {
                    allocator.free(attr.name);
                    allocator.free(attr.value);
                }
                allocator.free(elt_attrs);
            }

            for (elt_attrs) |attr| {
                const name_copy = try allocator.dupe(u8, attr.name);
                const value_copy = try allocator.dupe(u8, attr.value);
                try attributes.put(name_copy, value_copy);
            }

            // Convert child nodes recursively
            var children_list = std.ArrayList(JsonNode).init(allocator);
            defer children_list.deinit();

            var child = z.firstChild(node);
            while (child != null) {
                const child_json = try domNodeToJson(allocator, child.?);
                try children_list.append(child_json);
                child = z.nextSibling(child.?);
            }

            return JsonNode{
                .element = .{
                    .tagName = tag_name,
                    .attributes = attributes,
                    .children = try children_list.toOwnedSlice(),
                },
            };
        },

        .text => {
            const text_content = try z.getNodeTextContentsOpts(
                allocator,
                node,
                .{},
            );
            return JsonNode{ .text = .{ .text = text_content } };
        },

        .comment => {
            const comment: *z.Comment = @ptrCast(node);
            const comment_content = try z.getCommentTextContent(allocator, comment);
            return JsonNode{ .comment = .{ .comment = comment_content } };
        },

        else => {
            // Skip other node types (return empty text)
            return JsonNode{ .text = .{ .text = try allocator.dupe(u8, "") } };
        },
    }
}

/// [tree] Free memory allocated for HtmlTree
pub fn freeHtmlTree(allocator: std.mem.Allocator, tree: HtmlTree) void {
    for (tree) |node| {
        freeHtmlNode(allocator, node);
    }
    allocator.free(tree);
}

/// [tree] Free memory allocated for a single HtmlNode
pub fn freeHtmlNode(allocator: std.mem.Allocator, node: HtmlNode) void {
    switch (node) {
        .element => |elem| {
            allocator.free(elem.tag);

            // Free attributes
            for (elem.attributes) |attr| {
                allocator.free(attr.name);
                allocator.free(attr.value);
            }
            allocator.free(elem.attributes);

            // Free children recursively
            for (elem.children) |child| {
                freeHtmlNode(allocator, child);
            }
            allocator.free(elem.children);
        },
        .text => |text| allocator.free(text),
        .comment => |comment| {
            allocator.free(comment.tag);
            allocator.free(comment.text);
        },
    }
}

/// [json] Free memory allocated for JsonTree
pub fn freeJsonTree(allocator: std.mem.Allocator, tree: JsonTree) void {
    for (tree) |node| {
        freeJsonNode(allocator, node);
    }
    allocator.free(tree);
}

/// [json] Free memory allocated for a single JsonNode
pub fn freeJsonNode(allocator: std.mem.Allocator, node: JsonNode) void {
    switch (node) {
        .element => |*elem| {
            allocator.free(elem.tagName);

            // Free attributes HashMap - need to get a mutable reference
            var iterator = elem.attributes.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            // Use @constCast to make it mutable for deinit
            @constCast(&elem.attributes).deinit();

            // Free children recursively
            for (elem.children) |child| {
                freeJsonNode(allocator, child);
            }
            allocator.free(elem.children);
        },
        .text => |text_node| allocator.free(text_node.text),
        .comment => |comment_node| allocator.free(comment_node.comment),
    }
}

/// Pretty print an HtmlNode with proper formatting
pub fn printNode(node: HtmlNode, indent: usize) void {
    switch (node) {
        .element => |elem| {
            print("{{\"{s}\", [", .{elem.tag});
            for (elem.attributes, 0..) |attr, i| {
                if (i > 0) print(", ", .{});
                print("{{\"{s}\", \"{s}\"}}", .{ attr.name, attr.value });
            }
            print("], [", .{});
            for (elem.children, 0..) |child, i| {
                if (i > 0) print(", ", .{});
                printNode(child, indent + 1);
            }
            print("]}}", .{});
        },
        .text => |text| print("\"{s}\"", .{text}),
        .comment => |comment| print("{{\"comment\", \"{s}\"}}", .{comment.text}),
    }
    if (indent == 0) print("\n", .{});
}

/// [tree] Convert entire DOM document to HtmlTree
///
/// Caller must free the returned HtmlTree slice
pub fn documentToTree(allocator: std.mem.Allocator, doc: *z.HtmlDocument) !HtmlTree {
    const body_node = try z.getBodyNode(doc);

    var tree_list = std.ArrayList(HtmlNode).init(allocator);
    defer tree_list.deinit();

    // Simple loop approach - collectChildNodes doesn't handle allocator errors well
    var child = z.firstChild(body_node);
    while (child != null) {
        const child_tree = try domNodeToTree(allocator, child.?);
        try tree_list.append(child_tree);
        child = z.nextSibling(child.?);
    }

    return try tree_list.toOwnedSlice();
}

/// [tree] Convert entire document including HTML element (for full document structure)
pub fn fullDocumentToTree(allocator: std.mem.Allocator, doc: *z.HtmlDocument) !HtmlNode {
    // Try to get HTML element if it exists
    const html_element = z.getBodyElement(doc) catch {
        // Fallback to body if no HTML element found
        const body_node = try z.getBodyNode(doc);
        return try domNodeToTree(allocator, body_node);
    };

    // Get parent of body (should be HTML element)
    const body_node = z.elementToNode(html_element);
    const html_node = z.parentNode(body_node) orelse body_node;

    return try domNodeToTree(allocator, html_node);
}

/// [json] Convert entire DOM document to JsonTree
pub fn documentToJsonTree(allocator: std.mem.Allocator, doc: *z.HtmlDocument) !JsonTree {
    const body_node = try z.getBodyNode(doc);

    var tree_list = std.ArrayList(JsonNode).init(allocator);
    defer tree_list.deinit();

    var child = z.firstChild(body_node);
    while (child != null) {
        const child_json = try domNodeToJson(allocator, child.?);
        try tree_list.append(child_json);
        child = z.nextSibling(child.?);
    }

    return try tree_list.toOwnedSlice();
}

/// [json] Convert entire document including HTML element to JSON format
pub fn fullDocumentToJsonTree(allocator: std.mem.Allocator, doc: *z.HtmlDocument) !JsonNode {
    // Try to get HTML element if it exists
    const html_element = z.getBodyElement(doc) catch {
        // Fallback to body if no HTML element found
        const body_node = try z.getBodyNode(doc);
        return try domNodeToJson(allocator, body_node);
    };

    // Get parent of body (should be HTML element)
    const body_node = z.elementToNode(html_element);
    const html_node = z.parentNode(body_node) orelse body_node;

    return try domNodeToJson(allocator, html_node);
}

//=============================================================================
// REVERSE OPERATION: Tree → HTML
//=============================================================================

/// [tree] Convert HtmlNode back to HTML string
pub fn nodeToHtml(allocator: std.mem.Allocator, node: HtmlNode) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    try nodeToHtmlWriter(node, result.writer());
    return try result.toOwnedSlice();
}

/// [tree] Convert HtmlTree (array of nodes) back to HTML string
pub fn treeToHtml(allocator: std.mem.Allocator, tree: HtmlTree) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    for (tree) |node| {
        try nodeToHtmlWriter(node, result.writer());
    }

    return try result.toOwnedSlice();
}

/// [tree] Internal writer function for converting nodes to HTML
fn nodeToHtmlWriter(node: HtmlNode, html_writer: anytype) !void {
    switch (node) {
        .element => |elem| {
            // Opening tag
            try html_writer.print("<{s}", .{elem.tag});

            // Attributes
            for (elem.attributes) |attr| {
                try html_writer.print(" {s}=\"{s}\"", .{ attr.name, attr.value });
            }

            // Check if it's a void element (self-closing)
            const is_void = z.isVoidElement(elem.tag);

            if (is_void and elem.children.len == 0) {
                try html_writer.print(" />", .{});
            } else {
                try html_writer.print(">", .{});

                // Children
                for (elem.children) |child| {
                    try nodeToHtmlWriter(child, html_writer);
                }

                // Closing tag (skip for void elements)
                if (!is_void) {
                    try html_writer.print("</{s}>", .{elem.tag});
                }
            }
        },

        .text => |text| {
            // Escape HTML special characters in text
            try writeEscapedText(html_writer, text);
        },

        .comment => |comment| {
            try html_writer.print("<!--{s}-->", .{comment.text});
        },
    }
}

/// [tree] Write text with HTML escaping
fn writeEscapedText(html_writer: anytype, text: []const u8) !void {
    for (text) |ch| {
        switch (ch) {
            '<' => try html_writer.writeAll("&lt;"),
            '>' => try html_writer.writeAll("&gt;"),
            '&' => try html_writer.writeAll("&amp;"),
            '"' => try html_writer.writeAll("&quot;"),
            '\'' => try html_writer.writeAll("&#39;"),
            else => try html_writer.writeByte(ch),
        }
    }
}

/// [tree] Round-trip conversion: HTML → Tree → HTML
pub fn roundTripConversion(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    // Parse HTML to document
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Convert to tree
    const tree = try documentToTree(allocator, doc);
    defer freeHtmlTree(allocator, tree);

    // Convert back to HTML
    return try treeToHtml(allocator, tree);
}

// -----------------------------------------------------------------------------
// [tree] Debug: Walk and print DOM tree
pub fn walkTree(node: *z.DomNode, depth: u32) void {
    var child = z.firstChild(node);
    while (child != null) {
        const name = z.getNodeName(child.?);
        const indent = switch (@min(depth, 10)) {
            0 => "",
            1 => "  ",
            2 => "    ",
            3 => "      ",
            4 => "        ",
            5 => "          ",
            else => "            ", // For deeper levels
        };
        print("{s}{s}\n", .{ indent, name });

        walkTree(child.?, depth + 1);
        child = z.nextSibling(child.?);
    }
}

/// [tree] Debug: print document structure (for debugging)
pub fn printDocumentStructure(doc: *z.HtmlDocument) !void {
    print("\n--- DOCUMENT STRUCTURE ----\n", .{});
    const root = try z.getBodyNode(doc);
    walkTree(root, 0);
}

test "DOM tree conversion existing primitives" {
    const allocator = testing.allocator;

    const html = "<div></div><!-- Link --><a href=\"https://elixir-lang.org\">Elixir</a>";

    print("\n=== DOM Tree Conversion ===\n", .{});

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const tree = try documentToTree(allocator, doc);
    defer freeHtmlTree(allocator, tree);

    print("Tree structure:\n", .{});
    for (tree, 0..) |node, i| {
        print("[{}]: ", .{i});
        printNode(node, 0);
    }

    try testing.expect(tree.len >= 2);
}

test "JSON format conversion" {
    const allocator = testing.allocator;

    const html = "<div class=\"container\" id=\"main\"><p>Hello</p><!-- comment --><span>World</span></div>";

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const json_tree = try documentToJsonTree(allocator, doc);
    defer freeJsonTree(allocator, json_tree);

    print("\n=== JSON Format ===\n", .{});
    try testing.expect(json_tree.len > 0);

    // Check the structure matches expected JSON format
    switch (json_tree[0]) {
        .element => |elem| {
            try testing.expectEqualStrings("DIV", elem.tagName);
            try testing.expect(elem.attributes.count() == 2);
            try testing.expect(elem.children.len >= 2);

            // Check if attributes are accessible
            if (elem.attributes.get("class")) |class_value| {
                try testing.expectEqualStrings("container", class_value);
            }
            if (elem.attributes.get("id")) |id_value| {
                try testing.expectEqualStrings("main", id_value);
            }
        },
        else => try testing.expect(false),
    }
}

test "complex HTML structure conversion" {
    const allocator = testing.allocator;

    const html = "<html><head><title>Page</title></head><body>Hello world<!-- Link --></body></html>";

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Get body since HTML element access isn't directly available
    const tree = try documentToTree(allocator, doc);
    defer freeHtmlTree(allocator, tree);

    print("Full tree structure:\n", .{});
    for (tree, 0..) |node, i| {
        print("[{}]: ", .{i});
        printNode(node, 0);
    }
}

test "exact target format" {
    const allocator = testing.allocator;

    const html = "<html><head><title>Page</title></head><body>Hello world<!-- Link --></body></html>";

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Try to get the full document tree starting from HTML
    const full_tree = try fullDocumentToTree(allocator, doc);
    defer freeHtmlNode(allocator, full_tree);

    printNode(full_tree, 0);

    // Verify it's an HTML element with children
    switch (full_tree) {
        .element => |elem| {
            try testing.expectEqualStrings("HTML", elem.tag);
            try testing.expect(elem.children.len > 0);
        },
        else => try testing.expect(false),
    }
}

test "reverse operation: tree to HTML" {
    const allocator = testing.allocator;

    const simple_html = "<div><p>Hello</p><span>World</span></div>";

    const doc = try z.parseFromString(simple_html);
    defer z.destroyDocument(doc);

    const tree = try documentToTree(allocator, doc);
    defer freeHtmlTree(allocator, tree);

    const reconstructed = try treeToHtml(allocator, tree);
    defer allocator.free(reconstructed);

    try testing.expect(
        std.mem.indexOf(u8, reconstructed, "<DIV>") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, reconstructed, "<P>Hello</P>") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, reconstructed, "<SPAN>World</SPAN>") != null,
    );
}

test "round trip conversion" {
    const allocator = testing.allocator;

    const original_html = "<div class=\"test\"><p>Hello &amp; world</p><!-- comment --><br /></div>";

    const result = try roundTripConversion(allocator, original_html);
    defer allocator.free(result);

    try testing.expect(
        std.mem.indexOf(u8, result, "DIV") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, result, "class=\"test\"") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, result, "Hello &amp; world") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, result, "<!-- comment -->") != null,
    );
}

test "void elements handling" {
    const allocator = testing.allocator;

    const html_with_void = "<div><br /><img src=\"test.jpg\" alt=\"test\" /><p>Text</p></div>";

    const doc = try z.parseFromString(html_with_void);
    defer z.destroyDocument(doc);

    const tree = try documentToTree(allocator, doc);
    defer freeHtmlTree(allocator, tree);

    const result = try treeToHtml(allocator, tree);
    defer allocator.free(result);

    // Should not have closing tags for void elements
    try testing.expect(
        std.mem.indexOf(u8, result, "</BR>") == null,
    );
    try testing.expect(
        std.mem.indexOf(u8, result, "</IMG>") == null,
    );
    try testing.expect(
        std.mem.indexOf(u8, result, "</P>") != null,
    ); // P should have closing tag
}

test "HTML escaping in reverse operation" {
    const allocator = testing.allocator;

    const html_with_entities = "<div>&lt;script&gt;alert('test')&lt;/script&gt;</div>";

    const doc = try z.parseFromString(html_with_entities);
    defer z.destroyDocument(doc);

    const tree = try documentToTree(allocator, doc);
    defer freeHtmlTree(allocator, tree);

    const result = try treeToHtml(allocator, tree);
    defer allocator.free(result);

    // Should properly escape dangerous content
    try testing.expect(
        std.mem.indexOf(u8, result, "&lt;") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, result, "&gt;") != null,
    );
}

test "complex HTML structure" {
    const html =
        \\<!-- Top comment --><html><head>
        \\     <meta charset="UTF-8"/>
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
        \\    <title>Page</title>
        \\  </head>
        \\  <body>
        \\   <div id="root" class="layout">
        \\      Hello world
        \\     <!-- Inner comment -->
        \\     <p>
        \\       <span data-id="1">Hello</span>
        \\       <span data-id="2">world</span>
        \\     </p>
        \\     <img src="/assets/image.jpeg" alt="image"/>
        \\     <form>
        \\       <input class="input" value="" name="name"/>
        \\     </form>
        \\     <script>
        \\       console.log(1 && 2);
        \\     </script>
        \\     <style>
        \\       .parent > .child {
        \\         &:hover {
        \\            display: none;
        \\         }
        \\        }
        \\      </style>
        \\      &amp; &lt; &gt; &quot; &#39; € 🔥 🐈
        \\      <div class="&amp; &lt; &gt; &quot; &#39; € 🔥 🐈"></div>
        \\     </div>
        \\  </body></html>
    ;

    const allocator = testing.allocator;
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const full_tree = try fullDocumentToTree(
        allocator,
        doc,
    );
    defer freeHtmlNode(allocator, full_tree);

    const body_node = try z.getBodyNode(doc);
    try z.cleanDomTree(
        allocator,
        body_node,
        .{
            .remove_empty_elements = true,
            .remove_comments = true,
        },
    );
    const txt = try z.serializeTree(allocator, body_node);
    defer allocator.free(txt);

    // print("\nActual: ----------\n{s}\n\n", .{html});
    // try z.printDocumentStructure(doc);
    // print("\n\n Serialized: \n {s}\n\n", .{txt});
    // printNode(full_tree, 0);
}
