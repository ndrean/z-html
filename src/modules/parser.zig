const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const testing = std.testing;
// const print = std.debug.print;
const print = z.Writer.print;

const HtmlParser = opaque {};
const HtmlTree = opaque {};
const LXB_HTML_SERIALIZE_OPT_UNDEF: c_int = 0x00;

extern "c" fn lxb_html_parser_create() *HtmlParser;
extern "c" fn lxb_html_parser_destroy(parser: *HtmlParser) *HtmlParser;
extern "c" fn lxb_html_parser_clean(parser: *HtmlParser) void;
extern "c" fn lxb_html_parser_init(parser: *HtmlParser) usize;
extern "c" fn lxb_html_parse(parser: *HtmlParser, html: [*:0]const u8, size: usize) *z.HTMLDocument;

extern "c" fn lxb_html_parse_fragment(
    parser: *HtmlParser,
    element: *z.HTMLElement,
    html: []const u8,
    size: usize,
) *z.DomNode;
extern "c" fn lxb_html_parser_tree_node(parser: *HtmlParser) *HtmlTree;

extern "c" fn lxb_html_parser_tree_node_init(parser: *HtmlParser) *HtmlTree;

// ===
// const lxbString = extern struct {
//     data: ?[*]u8, // Pointer to string data
//     length: usize, // String length
//     size: usize, // Allocated size
// };

// extern "c" fn lxb_html_serialize_pretty_tree_cb(
//     node: *z.DomNode,
//     opt: usize,
//     indent: usize,
//     cb: *const fn ([*:0]const u8, len: usize, ctx: *anyopaque) callconv(.C) c_int,
//     ctx: ?*anyopaque,
// ) c_int;
// extern "c" fn lxb_html_serialize_pretty_str(
//     node: *z.DomNode,
//     opt: usize,
//     indent: usize,
//     str: *lxbString,
// ) usize;

// ===

pub const Parser = struct {
    doc: *z.HTMLDocument,
    status: c_int,
    parser: *HtmlParser,

    pub fn init() !Parser {
        const new_doc = z.createDocument() catch return Err.DocCreateFailed;
        return .{
            .doc = new_doc,
            .status = z._OK,
            .parser = lxb_html_parser_create(),
        };
    }

    pub fn parse(self: *Parser, data: [*:0]const u8) !*z.HTMLDocument {
        if (self.status == z._OK and lxb_html_parser_init(self.parser) != z._OK) {
            self.status = 1;
        } else self.status = z._OK;
        const len = std.mem.len(data);
        return lxb_html_parse(self.parser, data, len);
    }

    pub fn deinit(self: *Parser) void {
        _ = lxb_html_parser_destroy(self.parser);
        z.destroyDocument(self.doc);
    }
};

// pub const Colors = struct {
//     pub const black = "\x1b[30m";
//     pub const red = "\x1b[31m";
//     pub const green = "\x1b[32m";
//     pub const yellow = "\x1b[33m";
//     pub const blue = "\x1b[34m";
//     pub const magenta = "\x1b[35m";
//     pub const cyan = "\x1b[36m";
//     pub const white = "\x1b[37m";
//     pub const reset = "\x1b[0m";
// };

// const SerializerCtx = struct {
//     indent: usize = 0,
//     opt: usize = LXB_HTML_SERIALIZE_OPT_UNDEF,
// };

// fn serializer_cb(data: [*:0]const u8, len: usize, context: *anyopaque) callconv(.C) c_int {
//     _ = len;
//     const ctx: *SerializerCtx = @ptrCast(@alignCast(context));
//     const l = std.mem.len(data);
//     _ = ctx;

//     if (std.mem.eql(u8, data[0..l], "body")) {
//         std.debug.print("{s}{s}{s}", .{ Colors.green, data, Colors.reset });
//     } else if (std.mem.eql(u8, data[0..l], "<") or std.mem.eql(u8, data[0..l], "</") or std.mem.eql(u8, data[0..l], ">")) {
//         std.debug.print("{s}{s}{s}", .{ Colors.yellow, data, Colors.reset });
//     } else {
//         std.debug.print("{s}", .{data});
//     }
//     return 0;
// }

// fn serialize_pretty_cb(node: *z.DomNode, ctx: *SerializerCtx) c_int {
//     // _ = ctx;
//     return lxb_html_serialize_pretty_tree_cb(
//         node,
//         ctx.opt,
//         ctx.indent,
//         serializer_cb,
//         ctx,
//     );
// }

// test "parse" {
//     var p = try Parser.init();
//     var ctx: SerializerCtx = SerializerCtx{ .indent = 0, .opt = 0 };
//     defer p.deinit();
//     const doc = try p.parse("<html><body><ul><li>1</li><li>2</li><li>3</li><li>4</li></ul></body></html>");
//     const body = try z.bodyNode(doc);
//     _ = serialize_pretty_cb(body, &ctx);
// }

// ==================================================================

// const std = @import("std");
// const z = @import("../zhtml.zig");
// const Err = z.Err;
// const testing = std.testing;
// const print = std.debug.print;

// const HtmlParser = opaque {};
// const HtmlTree = opaque {};
// const LXB_HTML_SERIALIZE_OPT_UNDEF: c_int = 0x00;

// extern "c" fn lxb_html_parser_create() *HtmlParser;
// extern "c" fn lxb_html_parser_destroy(parser: *HtmlParser) *HtmlParser;
// extern "c" fn lxb_html_parser_init(parser: *HtmlParser) usize;
// extern "c" fn lxb_html_parse(parser: *HtmlParser, html: [*:0]const u8, size: usize) *z.HTMLDocument;

// pub const Parser = struct {
//     doc: *z.HTMLDocument,
//     status: c_int,
//     parser: *HtmlParser,

//     pub fn init() !Parser {
//         const new_doc = z.createDocument() catch return Err.DocCreateFailed;
//         return .{
//             .doc = new_doc,
//             .status = z._OK,
//             .parser = lxb_html_parser_create(),
//         };
//     }

//     pub fn parse(self: *Parser, data: [*:0]const u8) !*z.HTMLDocument {
//         if (self.status == z._OK and lxb_html_parser_init(self.parser) != z._OK) {
//             self.status = 1;
//         }
//         const len = std.mem.len(data);
//         return lxb_html_parse(self.parser, data, len);
//     }

//     pub fn deinit(self: *Parser) void {
//         _ = lxb_html_parser_destroy(self.parser);
//         z.destroyDocument(self.doc);
//     }
// };

/// HTML node representation
///
/// - #element: {tag_name, attributes, children}
/// - #text: "text content"
/// - #comment: {tag: "comment", text: "comment text"}
pub const HtmlNode = union(enum) {
    element: struct {
        tag: []const u8,
        attributes: []z.AttributePair,
        children: []HtmlNode,
    },
    text: []const u8,
    comment: struct { tag: []const u8, text: []const u8 },
    document: struct {
        children: []HtmlNode,
    },

    pub fn deinit(self: *HtmlNode, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .element => |*elem| {
                allocator.free(elem.tag);
                // Free attributes
                for (elem.attributes) |*attr| {
                    allocator.free(attr.name);
                    allocator.free(attr.value);
                }
                allocator.free(elem.attributes);
                // Free children recursively
                for (elem.children) |*child| {
                    child.deinit(allocator);
                }
                allocator.free(elem.children);
            },
            .text => |text| {
                allocator.free(text);
            },
            .comment => |*comment| {
                allocator.free(comment.tag);
                allocator.free(comment.text);
            },
            .document => |*doc| {
                for (doc.children) |*child| {
                    child.deinit(allocator);
                }
                allocator.free(doc.children);
            },
        }
    }

    pub fn output(self: HtmlNode, allocator: std.mem.Allocator, should_print: bool) !?[]u8 {
        if (should_print) {
            self.printTupleRecursive();
            return null;
        } else {
            var buffer = std.ArrayList(u8).init(allocator);
            defer buffer.deinit();
            try self.toStringRecursive(&buffer);
            return buffer.toOwnedSlice();
        }
    }
    pub fn display(self: HtmlNode) void {
        self.printTuple();
    }

    pub fn printTuple(self: HtmlNode) void {
        switch (self) {
            .element => |elem| {
                print("{{\"{s}\",[", .{elem.tag});

                // Print attributes array
                for (elem.attributes, 0..) |attr, i| {
                    print("{{\"{s}\",\"{s}\"}}", .{ attr.name, attr.value });
                    if (i < elem.attributes.len - 1) print(",", .{});
                }
                print("],[", .{});

                // Print children array - only non-empty children
                var printed_count: usize = 0;
                for (elem.children) |child| {
                    // Skip empty text nodes
                    if (child == .text) {
                        const trimmed = std.mem.trim(u8, child.text, " \t\n\r");
                        if (trimmed.len == 0) continue;
                    }

                    if (printed_count > 0) print(",", .{});
                    child.printTuple();
                    printed_count += 1;
                }
                print("]}}", .{});
            },
            .text => |text| {
                // Only print non-empty, non-whitespace text
                const trimmed = std.mem.trim(u8, text, " \t\n\r");
                if (trimmed.len > 0) {
                    print("\"{s}\"", .{trimmed});
                }
            },
            .comment => |comment| {
                print("{{\"comment\",\"{s}\"}}", .{comment.text});
            },
            .document => |doc| {
                print("[", .{});
                var printed_count: usize = 0;
                for (doc.children) |child| {
                    // Skip empty text nodes
                    if (child == .text) {
                        const trimmed = std.mem.trim(u8, child.text, " \t\n\r");
                        if (trimmed.len == 0) continue;
                    }

                    if (printed_count > 0) print(",", .{});
                    child.printTuple();
                    printed_count += 1;
                }
                print("]", .{});
            },
        }
    }
};

pub fn domNodeToTree(allocator: std.mem.Allocator, node: *z.DomNode) !HtmlNode {
    const node_type = z.nodeType(node);

    switch (node_type) {
        .element => {
            const element = z.nodeToElement(node).?;
            const tag_name = try z.nodeName(allocator, node);
            const elt_attrs = try z.getAttributes(allocator, element);

            // Convert child nodes recursively
            var children_list = std.ArrayList(HtmlNode).init(allocator);
            errdefer {
                // Clean up on error
                for (children_list.items) |*child| {
                    child.deinit(allocator);
                }
                children_list.deinit();
            }

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
            const text_content = try z.textContent(allocator, node);
            return HtmlNode{ .text = text_content };
        },

        .comment => {
            const comment: *z.Comment = @ptrCast(node);
            const comment_content = try z.commentContent(allocator, comment);
            return HtmlNode{
                .comment = .{
                    .tag = try allocator.dupe(u8, "comment"),
                    .text = comment_content,
                },
            };
        },

        .document => {
            // Handle document nodes (useful for full document parsing)
            var children_list = std.ArrayList(HtmlNode).init(allocator);
            errdefer {
                for (children_list.items) |*child| {
                    child.deinit(allocator);
                }
                children_list.deinit();
            }

            var child = z.firstChild(node);
            while (child != null) {
                const child_tree = try domNodeToTree(allocator, child.?);
                try children_list.append(child_tree);
                child = z.nextSibling(child.?);
            }

            return HtmlNode{
                .document = .{
                    .children = try children_list.toOwnedSlice(),
                },
            };
        },

        else => {
            // For other node types, return empty text or handle specifically
            std.log.warn("Unhandled node type: {}", .{node_type});
            return HtmlNode{ .text = try allocator.dupe(u8, "") };
        },
    }
}

// Helper function to build tree from document
pub fn buildDomTree(allocator: std.mem.Allocator, doc: *z.HTMLDocument) !HtmlNode {
    const root = z.documentRoot(doc); // Gets <html> element
    return domNodeToTree(allocator, root.?);
}

// Helper functions for tree traversal and analysis
fn findListItems(node: *const HtmlNode, count: *usize) void {
    switch (node.*) {
        .element => |elem| {
            // Check for both lowercase and uppercase (HTML parsers often normalize to uppercase)
            if (std.mem.eql(u8, elem.tag, "li") or std.mem.eql(u8, elem.tag, "LI")) {
                count.* += 1;
                print("Found list item #{} with {} children\n", .{ count.*, elem.children.len });
            }
            for (elem.children) |*child| {
                findListItems(child, count);
            }
        },
        .document => |doc| {
            for (doc.children) |*child| {
                findListItems(child, count);
            }
        },
        else => {},
    }
}

fn findElementsByTag(node: *const HtmlNode, tag: []const u8, results: *std.ArrayList(*const HtmlNode)) !void {
    switch (node.*) {
        .element => |elem| {
            // Check for both lowercase and uppercase versions
            if (std.mem.eql(u8, elem.tag, tag) or
                (std.ascii.eqlIgnoreCase(elem.tag, tag)))
            {
                try results.append(node);
            }
            for (elem.children) |*child| {
                try findElementsByTag(child, tag, results);
            }
        },
        .document => |doc| {
            for (doc.children) |*child| {
                try findElementsByTag(child, tag, results);
            }
        },
        else => {},
    }
}

fn collectAllText(node: *const HtmlNode, allocator: std.mem.Allocator) ![]u8 {
    var text_parts = std.ArrayList([]const u8).init(allocator);
    defer text_parts.deinit();

    try collectTextRecursive(node, &text_parts);

    return std.mem.join(allocator, " ", text_parts.items);
}

fn collectTextRecursive(node: *const HtmlNode, text_parts: *std.ArrayList([]const u8)) !void {
    switch (node.*) {
        .text => |text| {
            const trimmed = std.mem.trim(u8, text, " \t\n\r");
            if (trimmed.len > 0) {
                try text_parts.append(trimmed);
            }
        },
        .element => |elem| {
            for (elem.children) |*child| {
                try collectTextRecursive(child, text_parts);
            }
        },
        .document => |doc| {
            for (doc.children) |*child| {
                try collectTextRecursive(child, text_parts);
            }
        },
        else => {},
    }
}

test "basic DOM tree construction" {
    print("\n=== Basic DOM Tree Construction Test ===\n", .{});

    var p = try Parser.init();
    defer p.deinit();

    const html = "<html><body><h1>Hello</h1><p>World</p></body></html>";
    const doc = try p.parse(html);

    var tree = try buildDomTree(testing.allocator, doc);
    defer tree.deinit(testing.allocator);

    print("DOM Tree Structure:\n", .{});
    tree.display();

    // Verify it's an element
    try testing.expect(tree == .element);
    try testing.expectEqualStrings("HTML", tree.element.tag); // Updated to expect uppercase
}

test "complex DOM tree with lists" {
    print("\n=== Complex DOM Tree Test ===\n", .{});

    var p = try Parser.init();
    defer p.deinit();

    const html =
        \\<html>
        \\  <head><title>Test Page</title></head>
        \\  <body>
        \\    <h1>My List</h1>
        \\    <ul id="main-list" class="styled">
        \\      <li>Item 1</li>
        \\      <li>Item 2</li>
        \\      <li>Item 3</li>
        \\      <li>Item 4</li>
        \\    </ul>
        \\    <!-- This is a comment -->
        \\    <p>End of list</p>
        \\  </body>
        \\</html>
    ;

    const doc = try p.parse(html);

    var tree = try buildDomTree(testing.allocator, doc);
    defer tree.deinit(testing.allocator);

    print("Complex DOM Tree Structure:\n", .{});
    tree.display();

    // Count list items
    print("\n=== Finding List Items ===\n", .{});
    var li_count: usize = 0;
    findListItems(&tree, &li_count);
    try testing.expect(li_count == 4);

    // Find all ul elements - search for uppercase since parser normalizes
    print("\n=== Finding UL Elements ===\n", .{});
    var ul_elements = std.ArrayList(*const HtmlNode).init(testing.allocator);
    defer ul_elements.deinit();
    try findElementsByTag(&tree, "UL", &ul_elements);

    print("Found {} UL elements\n", .{ul_elements.items.len});
    try testing.expect(ul_elements.items.len == 1);
    if (ul_elements.items.len > 0) {
        const ul = ul_elements.items[0];
        if (ul.* == .element) {
            std.debug.print("Found UL with {} attributes and {} children\n", .{ ul.element.attributes.len, ul.element.children.len });

            // Print attributes
            for (ul.element.attributes) |attr| {
                std.debug.print("  Attribute: {s}=\"{s}\"\n", .{ attr.name, attr.value });
            }
        }
    }

    // Extract all text content
    print("\n=== All Text Content ===\n", .{});
    const all_text = try collectAllText(&tree, testing.allocator);
    defer testing.allocator.free(all_text);
    std.debug.print("All text: \"{s}\"\n", .{all_text});
}

test "DOM tree with attributes and comments" {
    std.debug.print("\n=== Attributes and Comments Test ===\n", .{});

    var p = try Parser.init();
    defer p.deinit();

    const html =
        \\<div id="container" class="main active" data-value="123">
        \\  <!-- Start of content -->
        \\  <p class="text">Hello <strong>World</strong>!</p>
        \\  <!-- End of content -->
        \\</div>
    ;

    const doc = try p.parse(html);
    const body = try z.bodyNode(doc);

    var tree = try domNodeToTree(testing.allocator, body);
    defer tree.deinit(testing.allocator);

    std.debug.print("Tree with attributes and comments:\n", .{});
    tree.display();
}

test "empty and malformed HTML" {
    std.debug.print("\n=== Empty and Edge Cases Test ===\n", .{});

    var p = try Parser.init();
    defer p.deinit();

    // Test empty HTML
    {
        const html = "<div></div>";
        const doc = try p.parse(html);
        const body = try z.bodyNode(doc);

        var tree = try domNodeToTree(testing.allocator, body);
        defer tree.deinit(testing.allocator);

        std.debug.print("Empty div tree:\n", .{});
        tree.display();
    }

    // Test self-closing tags
    {
        const html = "<div><img src='test.jpg' alt='Test'/><br/><input type='text'/></div>";
        const doc = try p.parse(html);
        const body = try z.bodyNode(doc);

        var tree = try domNodeToTree(testing.allocator, body);
        defer tree.deinit(testing.allocator);

        print("Self-closing tags tree:\n", .{});
        tree.display();
    }
}

// =============================================================================

pub fn treeToHtml(allocator: std.mem.Allocator, tree: []const HtmlNode) ![]u8 {
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

            try html_writer.print(">", .{});

            // Children
            for (elem.children) |child| {
                try nodeToHtmlWriter(child, html_writer);
            }

            // Closing tag
            try html_writer.print("</{s}>", .{elem.tag});
        },

        .text => |text| {
            // Write text directly - no escaping needed since we're working with DOM
            try html_writer.writeAll(text);
        },

        .comment => |comment| {
            try html_writer.print("<!--{s}-->", .{comment.text});
        },

        .document => |doc| {
            // Handle document nodes by writing their children
            for (doc.children) |child| {
                try nodeToHtmlWriter(child, html_writer);
            }
        },
    }
}

// Alternative optimized version using C allocator and pre-sizing
pub fn treeToHtmlFast(tree: []const HtmlNode) ![]u8 {
    const c_allocator = std.heap.c_allocator;

    // Estimate size to avoid reallocations
    const estimated_size = estimateHtmlSize(tree);
    var result = try std.ArrayList(u8).initCapacity(c_allocator, estimated_size);
    defer result.deinit();

    for (tree) |node| {
        try nodeToHtmlWriter(node, result.writer());
    }

    return try result.toOwnedSlice();
}

// Rough size estimation to minimize reallocations
fn estimateHtmlSize(tree: []const HtmlNode) usize {
    var size: usize = 0;
    for (tree) |node| {
        size += estimateNodeSize(node);
    }
    return size;
}

fn estimateNodeSize(node: HtmlNode) usize {
    switch (node) {
        .element => |elem| {
            var size = elem.tag.len * 2 + 5; // <tag></tag>

            // Attributes
            for (elem.attributes) |attr| {
                size += attr.name.len + attr.value.len + 4; // name="value"
            }

            // Children
            for (elem.children) |child| {
                size += estimateNodeSize(child);
            }

            return size;
        },
        .text => |text| return text.len,
        .comment => |comment| return comment.text.len + 7, // <!---->
        .document => |doc| {
            var size: usize = 0;
            for (doc.children) |child| {
                size += estimateNodeSize(child);
            }
            return size;
        },
    }
}

// Test function
test "tree to HTML conversion" {

    // Create a simple tree structure for testing
    const text_node = HtmlNode{ .text = "Hello World" };
    const comment_node = HtmlNode{ .comment = .{ .tag = "comment", .text = " A comment " } };

    // Create children array
    var children = [_]HtmlNode{text_node};
    var attrs = [_]z.AttributePair{
        .{ .name = "class", .value = "greeting" },
        .{ .name = "id", .value = "hello" },
    };

    const elem_node = HtmlNode{
        .element = .{
            .tag = "div",
            .attributes = &attrs,
            .children = &children,
        },
    };

    var tree = [_]HtmlNode{ elem_node, comment_node };

    const html = try treeToHtml(testing.allocator, &tree);
    defer testing.allocator.free(html);

    std.debug.print("\n\n\nGenerated HTML:\n {s}\n", .{html});

    // Should produce: <div class="greeting" id="hello">Hello World</div><!-- A comment -->
    try testing.expect(std.mem.indexOf(u8, html, "<div") != null);
    try testing.expect(std.mem.indexOf(u8, html, "class=\"greeting\"") != null);
    try testing.expect(std.mem.indexOf(u8, html, "Hello World") != null);
    try testing.expect(std.mem.indexOf(u8, html, "</div>") != null);
    try testing.expect(std.mem.indexOf(u8, html, "<!-- A comment -->") != null);
}

// test "complex tree" {
//     const tree = "{\"BODY\",[],[{\"DIV\",[{\"id\",\"container\"},{\"class\",\"main active\"},{\"data-value\",\"123\"}],[{\"comment\",\" Start of content \"},{\"P\",[{\"class\",\"text\"}],[\"Hello\",{\"STRONG\",[],[\"World\"]},\"!\"]},{\"comment\",\" End of content \"}]}]}";

//     const html = try treeToHtml(testing.allocator, tree);
//     defer testing.allocator.free(html);

//     std.debug.print("\n\n\nGenerated HTML:\n {s}\n", .{html});

//     // Should produce: <div class="greeting" id="hello">Hello World</div><!-- A comment -->
//     try testing.expect(std.mem.indexOf(u8, html, "<div") != null);
//     try testing.expect(std.mem.indexOf(u8, html, "class=\"greeting\"") != null);
//     try testing.expect(std.mem.indexOf(u8, html, "Hello World") != null);
//     try testing.expect(std.mem.indexOf(u8, html, "</div>") != null);
//     try testing.expect(std.mem.indexOf(u8, html, "<!-- A comment -->") != null);
// }
