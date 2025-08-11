const std = @import("std");
const z = @import("zhtml.zig");
const Err = z.LexborError;

const print = std.debug.print;
const testing = std.testing;
const writer = std.io.getStdOut().writer();

/// Represents different types of HTML nodes
pub const HtmlNode = union(enum) {
    /// Element: {tag_name, attributes, children}
    element: struct {
        tag: []const u8,
        attributes: []z.AttributePair,
        children: []HtmlNode, // Changed to HtmlNode instead of *z.DomNode
    },

    /// Text content: "text content"
    text: []const u8,

    /// Comment: {tag: "comment", text: "comment text"}
    comment: struct { tag: []const u8, text: []const u8 },
};

/// Top-level tree (array of nodes)
pub const HtmlTree = []HtmlNode;

/// Convert DOM node to HtmlNode recursively
pub fn domNodeToTree(allocator: std.mem.Allocator, node: *z.DomNode) !HtmlNode {
    const node_type = z.getNodeType(node);

    switch (node_type) {
        .element => {
            const element = z.nodeToElement(node).?;
            // Use the owned version for safety
            const tag_name = try z.getNodeNameOwned(allocator, node);

            // Get attributes
            const elt_attrs = try z.attributes(allocator, element);

            // Convert child nodes recursively
            var children_list = std.ArrayList(HtmlNode).init(allocator);
            defer children_list.deinit();

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
            const text_content = try z.getNodeTextContentsOpts(allocator, node, .{});
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

/// Free memory allocated for HtmlTree
pub fn freeHtmlTree(allocator: std.mem.Allocator, tree: HtmlTree) void {
    for (tree) |node| {
        freeHtmlNode(allocator, node);
    }
    allocator.free(tree);
}

/// Free memory allocated for a single HtmlNode
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

/// Convert entire DOM document to HtmlTree
pub fn documentToTree(allocator: std.mem.Allocator, doc: *z.HtmlDocument) !HtmlTree {
    const body_node = try z.getDocumentBodyNode(doc);

    var tree_list = std.ArrayList(HtmlNode).init(allocator);
    defer tree_list.deinit();

    var child = z.firstChild(body_node);
    while (child != null) {
        const child_tree = try domNodeToTree(allocator, child.?);
        try tree_list.append(child_tree);
        child = z.nextSibling(child.?);
    }

    return try tree_list.toOwnedSlice();
}

/// Convert entire document including HTML element (for full document structure)
pub fn fullDocumentToTree(allocator: std.mem.Allocator, doc: *z.HtmlDocument) !HtmlNode {
    // Try to get HTML element if it exists
    const html_element = z.getDocumentBodyElement(doc) catch {
        // Fallback to body if no HTML element found
        const body_node = try z.getDocumentBodyNode(doc);
        return try domNodeToTree(allocator, body_node);
    };

    // Get parent of body (should be HTML element)
    const body_node = z.elementToNode(html_element);
    const html_node = z.parentNode(body_node) orelse body_node;

    return try domNodeToTree(allocator, html_node);
}

//=============================================================================
// REVERSE OPERATION: Tree → HTML
//=============================================================================

/// Convert HtmlNode back to HTML string
pub fn nodeToHtml(allocator: std.mem.Allocator, node: HtmlNode) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    try nodeToHtmlWriter(node, result.writer());
    return try result.toOwnedSlice();
}

/// Convert HtmlTree (array of nodes) back to HTML string
pub fn treeToHtml(allocator: std.mem.Allocator, tree: HtmlTree) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    for (tree) |node| {
        try nodeToHtmlWriter(node, result.writer());
    }

    return try result.toOwnedSlice();
}

/// Internal writer function for converting nodes to HTML
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
            const is_void = isVoidElement(elem.tag);

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

/// Check if an element is a void (self-closing) element
fn isVoidElement(tag: []const u8) bool {
    const void_elements = [_][]const u8{
        "AREA",  "BASE",   "BR",    "COL",    "EMBED", "HR",    "IMG",  "INPUT",
        "LINK",  "META",   "PARAM", "SOURCE", "TRACK", "WBR",
        // Also check lowercase versions
          "area", "base",
        "br",    "col",    "embed", "hr",     "img",   "input", "link", "meta",
        "param", "source", "track", "wbr",
    };

    for (void_elements) |void_elem| {
        if (std.mem.eql(u8, tag, void_elem)) {
            return true;
        }
    }
    return false;
}

/// Write text with HTML escaping
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

/// Round-trip conversion: HTML → Tree → HTML
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

test "DOM tree conversion with your primitives" {
    const allocator = testing.allocator;

    const html = "<div></div><!-- Link --><a href=\"https://elixir-lang.org\">Elixir</a>";

    print("\n=== DOM Tree Conversion ===\n", .{});

    // ✅ Parse using your existing functions
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // ✅ Convert DOM → Tree
    const tree = try documentToTree(allocator, doc);
    defer freeHtmlTree(allocator, tree);

    // ✅ Print tree structure
    print("Tree structure:\n", .{});
    for (tree, 0..) |node, i| {
        print("[{}]: ", .{i});
        printNode(node, 0);
    }

    // ✅ Verify structure
    try testing.expect(tree.len >= 2); // Should have at least div and a
}

test "complex HTML structure conversion" {
    const allocator = testing.allocator;

    // Your target HTML structure
    const html = "<html><head><title>Page</title></head><body>Hello world<!-- Link --></body></html>";

    print("\n=== Complex HTML Structure ===\n", .{});

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

    // Your exact target
    const html = "<html><head><title>Page</title></head><body>Hello world<!-- Link --></body></html>";

    print("\n=== Target Format Test ===\n", .{});
    print("Input: {s}\n", .{html});
    print("Expected: {{\"html\", [], [{{\"head\", [], [{{\"title\", [], [\"Page\"]}}]}}, {{\"body\", [], [\"Hello world\", {{\"comment\", \" Link \"}}]}}]}}\n", .{});

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Try to get the full document tree starting from HTML
    const full_tree = try fullDocumentToTree(allocator, doc);
    defer freeHtmlNode(allocator, full_tree);

    print("Actual: ", .{});
    printNode(full_tree, 0);

    // Verify it's an HTML element with children
    switch (full_tree) {
        .element => |elem| {
            try testing.expectEqualStrings("HTML", elem.tag);
            try testing.expect(elem.children.len > 0);
        },
        else => try testing.expect(false), // Should be an element
    }
}

test "reverse operation: tree to HTML" {
    const allocator = testing.allocator;

    print("\n=== Reverse Operation Test ===\n", .{});

    // Test simple structure
    const simple_html = "<div><p>Hello</p><span>World</span></div>";

    const doc = try z.parseFromString(simple_html);
    defer z.destroyDocument(doc);

    // Convert to tree
    const tree = try documentToTree(allocator, doc);
    defer freeHtmlTree(allocator, tree);

    print("Original HTML: {s}\n", .{simple_html});

    // Convert back to HTML
    const reconstructed = try treeToHtml(allocator, tree);
    defer allocator.free(reconstructed);

    print("Reconstructed: {s}\n", .{reconstructed});

    // Should contain the same elements
    try testing.expect(std.mem.indexOf(u8, reconstructed, "<DIV>") != null);
    try testing.expect(std.mem.indexOf(u8, reconstructed, "<P>Hello</P>") != null);
    try testing.expect(std.mem.indexOf(u8, reconstructed, "<SPAN>World</SPAN>") != null);
}

test "round trip conversion" {
    const allocator = testing.allocator;

    print("\n=== Round Trip Test ===\n", .{});

    const original_html = "<div class=\"test\"><p>Hello &amp; world</p><!-- comment --><br /></div>";

    print("Original: {s}\n", .{original_html});

    // Round trip: HTML → Tree → HTML
    const result = try roundTripConversion(allocator, original_html);
    defer allocator.free(result);

    print("Round trip result: {s}\n", .{result});

    // Should contain the same structure
    try testing.expect(std.mem.indexOf(u8, result, "DIV") != null);
    try testing.expect(std.mem.indexOf(u8, result, "class=\"test\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Hello &amp; world") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<!-- comment -->") != null);
}

test "void elements handling" {
    const allocator = testing.allocator;

    print("\n=== Void Elements Test ===\n", .{});

    const html_with_void = "<div><br /><img src=\"test.jpg\" alt=\"test\" /><p>Text</p></div>";

    const doc = try z.parseFromString(html_with_void);
    defer z.destroyDocument(doc);

    const tree = try documentToTree(allocator, doc);
    defer freeHtmlTree(allocator, tree);

    const result = try treeToHtml(allocator, tree);
    defer allocator.free(result);

    print("Void elements HTML: {s}\n", .{result});

    // Should not have closing tags for void elements
    try testing.expect(std.mem.indexOf(u8, result, "</BR>") == null);
    try testing.expect(std.mem.indexOf(u8, result, "</IMG>") == null);
    try testing.expect(std.mem.indexOf(u8, result, "</P>") != null); // P should have closing tag
}

test "HTML escaping in reverse operation" {
    const allocator = testing.allocator;

    print("\n=== HTML Escaping Test ===\n", .{});

    const html_with_entities = "<div>&lt;script&gt;alert('test')&lt;/script&gt;</div>";

    const doc = try z.parseFromString(html_with_entities);
    defer z.destroyDocument(doc);

    const tree = try documentToTree(allocator, doc);
    defer freeHtmlTree(allocator, tree);

    const result = try treeToHtml(allocator, tree);
    defer allocator.free(result);

    print("Escaped HTML: {s}\n", .{result});

    // Should properly escape dangerous content
    try testing.expect(std.mem.indexOf(u8, result, "&lt;") != null);
    try testing.expect(std.mem.indexOf(u8, result, "&gt;") != null);
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

    const body_node = try z.getDocumentBodyNode(doc);
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

    print("\nActual: ----------\n{s}\n\n", .{html});
    try z.printDocumentStructure(doc);
    print("\n\n Serialized: \n {s}\n\n", .{txt});
    printNode(full_tree, 0);
}
