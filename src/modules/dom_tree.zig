//! Dom_tree module
//! This module provides functions to:
//! - convert DOM nodes to a tuple-like or JSON tree structure
//! - convert a tuple-like or JSON tree structure back to DOM nodes
//! Prefer to use Arena allocator for easy memory management

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const print = std.debug.print;
const testing = std.testing;
const writer = std.io.getStdOut().writer();

// Structure ====================================================================

/// [tree] Debug: Walk and print DOM tree
pub fn walkTree(node: *z.DomNode, depth: u8) void {
    var child = z.firstChild(node);
    while (child != null) {
        const name = if (z.isTypeElement(child.?)) z.qualifiedName_zc(z.nodeToElement(child.?).?) else z.nodeName_zc(child.?);

        const ansi_colour = z.getStyleForElement(name) orelse z.Style.DIM_WHITE;
        const ansi_reset = z.Style.RESET;
        const indent = switch (@min(depth, 10)) {
            0 => "",
            1 => "  ",
            2 => "    ",
            3 => "      ",
            4 => "        ",
            5 => "          ",
            else => "            ",
        };
        print("{s}{s}{s}{s}\n", .{ indent, ansi_colour, name, ansi_reset });

        walkTree(child.?, depth + 1);
        child = z.nextSibling(child.?);
    }
}

/// [tree] Debug: print document structure (for debugging)
pub fn printDocStruct(doc: *z.HTMLDocument) !void {
    const root = z.documentRoot(doc).?;
    walkTree(root, 0);
}

// Tuple Tree ===================================================================

/// Represents different types of HTML nodes as tuples
///
/// - Elements are in the form `{tag_name, attributes, children}`
///
/// - Text nodes such are in the form `{text_content}`
///
/// - Comment nodes are in the form `{"comment", text_content}`
pub const TupleNode = union(enum) {
    /// Element: {tag_name, attributes, children}
    element: struct {
        tag: []const u8,
        attributes: []z.AttributePair,
        children: []TupleNode,
    },
    /// Text content: "text content"
    text: []const u8,
    /// Comment: {tag: "comment", text: "comment text"}
    comment: []const u8,
};

/// [tree] Convert DOM to []TupleNode
pub fn nodeTuple(allocator: std.mem.Allocator, node: *z.DomNode) !TupleNode {
    const node_type = z.nodeType(node);

    switch (node_type) {
        .element => {
            const element = z.nodeToElement(node).?;
            const tag_name = try z.nodeName(allocator, node);
            const elt_attrs = try z.getAttributes(allocator, element);

            // Convert child nodes recursively
            var children_list: std.ArrayList(TupleNode) = .empty;
            defer children_list.deinit(allocator);

            // Traverse child nodes

            var child = z.firstChild(node);
            while (child != null) {
                const child_tree = try nodeTuple(allocator, child.?);
                try children_list.append(allocator, child_tree);
                child = z.nextSibling(child.?);
            }

            return TupleNode{
                .element = .{
                    .tag = tag_name,
                    .attributes = elt_attrs,
                    .children = try children_list.toOwnedSlice(allocator),
                },
            };
        },

        .text => {
            const text_content = try z.textContent(
                allocator,
                node,
            );
            return TupleNode{ .text = text_content };
        },

        .comment => {
            const comment: *z.Comment = @ptrCast(node);
            const comment_content = try z.commentContent(allocator, comment);
            return TupleNode{ .comment = comment_content };
        },

        else => {
            // Skip other node types (return empty text)
            return TupleNode{ .text = try allocator.dupe(u8, "") };
        },
    }
}

/// [tree] Free memory allocated for HtmlTree
pub fn freeTupleTree(allocator: std.mem.Allocator, tree: []TupleNode) void {
    for (tree) |node| {
        freeTupleNode(allocator, node);
    }
    allocator.free(tree);
}

// Free memory allocated for a single TupleNode
pub fn freeTupleNode(allocator: std.mem.Allocator, node: TupleNode) void {
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
                freeTupleNode(allocator, child);
            }
            allocator.free(elem.children);
        },
        .text => |text| allocator.free(text),
        .comment => |comment| allocator.free(comment),
    }
}

/// [tree] Convert entire DOM document to tuple tree
///
/// Caller must free the returned HtmlTree slice
pub fn toTuple(allocator: std.mem.Allocator, node: *z.DomNode) ![]TupleNode {
    // const root = z.documentRoot(doc).?;

    var tree_list: std.ArrayList(TupleNode) = .empty;
    defer tree_list.deinit(allocator);

    var child = z.firstChild(node);
    while (child != null) {
        const child_tree = try nodeTuple(allocator, child.?);
        try tree_list.append(allocator, child_tree);
        child = z.nextSibling(child.?);
    }

    return try tree_list.toOwnedSlice(allocator);
}

/// Pretty print an TupleNode with proper formatting
pub fn printNode(node: TupleNode, indent: usize) void {
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
        .comment => |comment| print(
            "{{\"comment\", \"{s}\"}}",
            .{comment},
        ),
    }
    if (indent == 0) print("\n", .{});
}

test "HTML to tuple" {
    const allocator = testing.allocator;

    const html = "<html><head><title>Page</title></head><body id=\"main\" class=\"container\">Hello world<!-- Link --><div><button phx-click=\"increment\">{@counter}</button></div><!-- Link --><a href=\"https://elixir-lang.org\">Elixir</a></body></html>";

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const root = z.documentRoot(doc).?;

    // Get body since HTML element access isn't directly available
    const tree = try toTuple(allocator, root);
    defer freeTupleTree(allocator, tree);

    for (tree) |node| {
        printNode(node, 0);

        // expect to see:
        // {"HEAD", [], [{"TITLE", [], ["Page"]}]}
        // {"BODY", [{"id", "main"}, {"class", "container"}], ["Hello world", {"comment", " Link "}, {"DIV", [], [{"BUTTON", [{"phx-click", "increment"}], ["{@counter}"]}]}, {"comment", " Link "}, {"A", [{"href", "https://elixir-lang.org"}], ["Elixir"]}]}
    }
}

//=============================================================================
// REVERSE OPERATION: Tree → HTML
//=============================================================================

// /// [tree] Convert TupleNode back to HTML string
// pub fn nodeToHtml(allocator: std.mem.Allocator, node: TupleNode) ![]u8 {
//     var result: std.ArrayList(u8) = .empty;

//     nodeToHtmlWriter(node);
//     return try result.toOwnedSlice(allocator);
// }

// /// [tree] Convert HtmlTree (array of nodes) back to HTML string
// pub fn treeToHtml(allocator: std.mem.Allocator, tree: []TupleNode) ![]u8 {
//     var result: std.ArrayList(u8) = .empty;

//     for (tree) |node| {
//         nodeToHtmlWriter(node);
//     }

//     return try result.toOwnedSlice(allocator);
// }

// /// [tree] Internal writer function for converting nodes to HTML
// fn nodeToHtmlWriter(node: TupleNode) void {
//     switch (node) {
//         .element => |elem| {
//             print("<{s}", .{elem.tag});

//             for (elem.attributes) |attr| {
//                 print(" {s}=\"{s}\"", .{ attr.name, attr.value });
//             }

//             print(">", .{});

//             for (elem.children) |child| {
//                 nodeToHtmlWriter(child);
//             }
//         },

//         .text => |text| {
//             print("{s}", .{text});
//         },

//         .comment => |comment| {
//             print("<!--{s}-->", .{comment});
//         },
//     }
// }

// /// [json] Convert DOM node to JSON-friendly format
// pub fn domNodeToJson(allocator: std.mem.Allocator, node: *z.DomNode) !JsonNode {
//     const node_type = z.nodeType(node);

//     switch (node_type) {
//         .element => {
//             const element = z.nodeToElement(node).?;
//             const tag_name = try z.nodeName(allocator, node);

//             // Convert attributes to proper format for JSON
//             const elt_attrs = try z.getAttributes(allocator, element);
//             var attributes_list = std.ArrayList(JsonAttribute).init(allocator);
//             defer attributes_list.deinit();

//             for (elt_attrs) |attr| {
//                 try attributes_list.append(.{
//                     .name = try allocator.dupe(u8, attr.name),
//                     .value = try allocator.dupe(u8, attr.value),
//                 });
//             }

//             // Free the original attributes array
//             for (elt_attrs) |attr| {
//                 allocator.free(attr.name);
//                 allocator.free(attr.value);
//             }
//             allocator.free(elt_attrs);

//             // Convert child nodes recursively
//             var children_list = std.ArrayList(JsonNode).init(allocator);
//             defer children_list.deinit();

//             var child = z.firstChild(node);
//             while (child != null) {
//                 const child_json = try domNodeToJson(allocator, child.?);
//                 try children_list.append(child_json);
//                 child = z.nextSibling(child.?);
//             }

//             return JsonNode{
//                 .element = .{
//                     .nodeType = 1, // ELEMENT_NODE
//                     .tagName = tag_name,
//                     .attributes = try attributes_list.toOwnedSlice(),
//                     .children = try children_list.toOwnedSlice(),
//                 },
//             };
// }

// pub const JsonAttribute = struct {
//     name: []const u8,
//     value: []const u8,
// };

// /// JSON-friendly DOM node representation (W3C DOM standard format)
// ///
// /// Follows the actual DOM Node specification:
// /// - nodeType: 1 = ELEMENT_NODE, 3 = TEXT_NODE, 8 = COMMENT_NODE
// /// - Elements have: nodeType, tagName, attributes, children
// /// - Text nodes have: nodeType, data
// /// - Comment nodes have: nodeType, data
// pub const JsonNode = union(enum) {
//     /// Element: {"nodeType": 1, "tagName": "div", "attributes": [...], "children": [...]}
//     element: struct {
//         nodeType: u8, // Always 1 for ELEMENT_NODE
//         tagName: []const u8,
//         attributes: []JsonAttribute,
//         children: []JsonNode,
//     },

//     /// Text node: {"nodeType": 3, "data": "content"}
//     text: struct {
//         nodeType: u8, // Always 3 for TEXT_NODE
//         data: []const u8,
//     },

//     /// Comment node: {"nodeType": 8, "data": "comment text"}
//     comment: struct {
//         nodeType: u8, // Always 8 for COMMENT_NODE
//         data: []const u8,
//     },
// };

// /// Top-level JSON tree (array of JSON nodes)
// pub const JsonTree = []JsonNode;
// /// [json] Convert DOM node to JSON-friendly format
// pub fn domNodeToJson(allocator: std.mem.Allocator, node: *z.DomNode) !JsonNode {
//     const node_type = z.nodeType(node);

//     switch (node_type) {
//         .element => {
//             const element = z.nodeToElement(node).?;
//             const tag_name = try z.nodeName(allocator, node);

//             // Convert attributes to proper format for JSON
//             const elt_attrs = try z.getAttributes(allocator, element);
//             var attributes_list = std.ArrayList(JsonAttribute).init(allocator);
//             defer attributes_list.deinit();

//             for (elt_attrs) |attr| {
//                 try attributes_list.append(.{
//                     .name = try allocator.dupe(u8, attr.name),
//                     .value = try allocator.dupe(u8, attr.value),
//                 });
//             }

//             // Free the original attributes array
//             for (elt_attrs) |attr| {
//                 allocator.free(attr.name);
//                 allocator.free(attr.value);
//             }
//             allocator.free(elt_attrs);

//             // Convert child nodes recursively
//             var children_list = std.ArrayList(JsonNode).init(allocator);
//             defer children_list.deinit();

//             var child = z.firstChild(node);
//             while (child != null) {
//                 const child_json = try domNodeToJson(allocator, child.?);
//                 try children_list.append(child_json);
//                 child = z.nextSibling(child.?);
//             }

//             return JsonNode{
//                 .element = .{
//                     .nodeType = 1, // ELEMENT_NODE
//                     .tagName = tag_name,
//                     .attributes = try attributes_list.toOwnedSlice(),
//                     .children = try children_list.toOwnedSlice(),
//                 },
//             };
//         },

//         .text => {
//             const text_content = try z.textContent(
//                 allocator,
//                 node,
//             );
//             return JsonNode{
//                 .text = .{
//                     .nodeType = 3, // TEXT_NODE
//                     .data = text_content,
//                 },
//             };
//         },

//         .comment => {
//             const comment: *z.Comment = @ptrCast(node);
//             const comment_content = try z.commentContent(allocator, comment);
//             return JsonNode{
//                 .comment = .{
//                     .nodeType = 8, // COMMENT_NODE
//                     .data = comment_content,
//                 },
//             };
//         },

//         else => {
//             // Skip other node types (return empty text)
//             return JsonNode{
//                 .text = .{
//                     .nodeType = 3, // TEXT_NODE
//                     .data = try allocator.dupe(u8, ""),
//                 },
//             };
//         },
//     }
// }

// /// [json] Free memory allocated for JsonTree
// pub fn freeJsonTree(allocator: std.mem.Allocator, tree: JsonTree) void {
//     for (tree) |node| {
//         freeJsonNode(allocator, node);
//     }
//     allocator.free(tree);
// }

// /// [json] Free memory allocated for a single JsonNode
// pub fn freeJsonNode(allocator: std.mem.Allocator, node: JsonNode) void {
//     switch (node) {
//         .element => |*elem| {
//             allocator.free(elem.tagName);

//             // Free attributes array
//             for (elem.attributes) |attr| {
//                 allocator.free(attr.name);
//                 allocator.free(attr.value);
//             }
//             allocator.free(elem.attributes);

//             // Free children recursively
//             for (elem.children) |child| {
//                 freeJsonNode(allocator, child);
//             }
//             allocator.free(elem.children);
//         },
//         .text => |text_node| allocator.free(text_node.data),
//         .comment => |comment_node| allocator.free(comment_node.data),
//     }
// }

// /// [json] Serialize JsonNode to JSON string
// pub fn jsonNodeToString(allocator: std.mem.Allocator, node: JsonNode) ![]u8 {
//     var result: std.ArrayList(u8) = .empty;
//     defer result.deinit();

//     try jsonNodeToWriter(node, result.writer());
//     return try result.toOwnedSlice(allocator);
// }

// /// [json] Serialize JsonTree (array) to JSON string
// pub fn jsonTreeToString(allocator: std.mem.Allocator, tree: JsonTree) ![]u8 {
//     var result: std.ArrayList(u8) = .empty;
//     // defer result.deinit(allocator);

//     try result.append(allocator, '[');
//     for (tree, 0..) |node, i| {
//         if (i > 0) try result.appendSlice(allocator, ", ");
//         try jsonNodeToWriter(node, result.writer());
//     }
//     try result.append(allocator, ']');

//     return try result.toOwnedSlice(allocator);
// }

// /// [json] Internal writer function for JsonNode serialization
// fn jsonNodeToWriter(node: JsonNode, json_writer: anytype) !void {
//     switch (node) {
//         .element => |elem| {
//             try json_writer.writeAll("{");
//             try json_writer.print("\"nodeType\": {d}, ", .{elem.nodeType});
//             try json_writer.print("\"tagName\": \"{s}\", ", .{elem.tagName});

//             // Write attributes array
//             try json_writer.writeAll("\"attributes\": [");
//             for (elem.attributes, 0..) |attr, i| {
//                 if (i > 0) try json_writer.writeAll(", ");
//                 try json_writer.print("{{\"name\": \"{s}\", \"value\": \"{s}\"}}", .{ attr.name, attr.value });
//             }
//             try json_writer.writeAll("], ");

//             // Write children array
//             try json_writer.writeAll("\"children\": [");
//             for (elem.children, 0..) |child, i| {
//                 if (i > 0) try json_writer.writeAll(", ");
//                 try jsonNodeToWriter(child, json_writer);
//             }
//             try json_writer.writeAll("]}");
//         },

//         .text => |text_node| {
//             try json_writer.writeAll("{");
//             try json_writer.print("\"nodeType\": {d}, ", .{text_node.nodeType});
//             try json_writer.print("\"data\": \"{s}\"", .{text_node.data});
//             try json_writer.writeAll("}");
//         },

//         .comment => |comment_node| {
//             try json_writer.writeAll("{");
//             try json_writer.print("\"nodeType\": {d}, ", .{comment_node.nodeType});
//             try json_writer.print("\"data\": \"{s}\"", .{comment_node.data});
//             try json_writer.writeAll("}");
//         },
//     }
// }

// /// [json] Parse JSON string to JsonNode (using std.json)
// pub fn parseJsonString(allocator: std.mem.Allocator, json_string: []const u8) !JsonNode {
//     const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_string, .{});
//     defer parsed.deinit();

//     return try parseJsonValue(allocator, parsed.value);
// }

// /// [json] Parse JSON string to JsonTree array
// pub fn parseJsonTreeString(allocator: std.mem.Allocator, json_string: []const u8) !JsonTree {
//     const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_string, .{});
//     defer parsed.deinit();

//     if (parsed.value != .array) {
//         return error.ExpectedArray;
//     }

//     var tree_list: std.ArrayList(JsonNode) = .empty;
//     defer tree_list.deinit(allocator);

//     for (parsed.value.array.items) |item| {
//         const node = try parseJsonValue(allocator, item);
//         try tree_list.append(allocator, node);
//     }

//     return try tree_list.toOwnedSlice(allocator);
// }

// /// [json] Internal function to parse std.json.Value to JsonNode
// ///
// fn parseJsonValue(allocator: std.mem.Allocator, value: std.json.Value) !JsonNode {
//     if (value != .object) {
//         return error.ExpectedObject;
//     }

//     const obj = value.object;
//     const node_type_value = obj.get("nodeType") orelse return error.MissingNodeType;
//     if (node_type_value != .integer) return error.InvalidNodeType;

//     const node_type = @as(u8, @intCast(node_type_value.integer));

//     switch (node_type) {
//         1 => { // ELEMENT_NODE
//             const tag_name_value = obj.get("tagName") orelse return error.MissingTagName;
//             if (tag_name_value != .string) return error.InvalidTagName;

//             const attributes_value = obj.get("attributes") orelse return error.MissingAttributes;
//             if (attributes_value != .array) return error.InvalidAttributes;

//             const children_value = obj.get("children") orelse return error.MissingChildren;
//             if (children_value != .array) return error.InvalidChildren;

//             // Parse attributes
//             var attr_list: std.ArrayList(JsonAttribute) = .empty;
//             defer attr_list.deinit(allocator);

//             for (attributes_value.array.items) |attr_item| {
//                 if (attr_item != .object) continue;
//                 const attr_obj = attr_item.object;

//                 const name_value = attr_obj.get("name") orelse continue;
//                 const value_value = attr_obj.get("value") orelse continue;
//                 if (name_value != .string or value_value != .string) continue;

//                 try attr_list.append(
//                     allocator,
//                     .{ .name = try allocator.dupe(u8, name_value.string), .value = try allocator.dupe(u8, value_value.string) },
//                 );
//             }

//             // Parse children
//             var children_list: std.ArrayList(JsonNode) = .empty;
//             defer children_list.deinit(allocator);

//             for (children_value.array.items) |child_item| {
//                 const child_node = try parseJsonValue(allocator, child_item);
//                 try children_list.append(allocator, child_node);
//             }

//             return JsonNode{
//                 .element = .{
//                     .nodeType = node_type,
//                     .tagName = try allocator.dupe(u8, tag_name_value.string),
//                     .attributes = try attr_list.toOwnedSlice(allocator),
//                     .children = try children_list.toOwnedSlice(allocator),
//                 },
//             };
//         },

//         3, 8 => { // TEXT_NODE or COMMENT_NODE
//             const data_value = obj.get("data") orelse return error.MissingData;
//             if (data_value != .string) return error.InvalidData;

//             const data = try allocator.dupe(u8, data_value.string);

//             if (node_type == 3) {
//                 return JsonNode{ .text = .{ .nodeType = node_type, .data = data } };
//             } else {
//                 return JsonNode{ .comment = .{ .nodeType = node_type, .data = data } };
//             }
//         },

//         else => return error.UnsupportedNodeType,
//     }
// }

// /// [json] Convert entire DOM document to JsonTree
// pub fn documentToJsonTree(allocator: std.mem.Allocator, doc: *z.HTMLDocument) !JsonTree {
//     const body_node = try z.bodyNode(doc);

//     var tree_list = std.ArrayList(JsonNode){ .allocator = allocator };
//     defer tree_list.deinit();

//     var child = z.firstChild(body_node);
//     while (child != null) {
//         const child_json = try domNodeToJson(allocator, child.?);
//         try tree_list.append(child_json);
//         child = z.nextSibling(child.?);
//     }

//     return try tree_list.toOwnedSlice();
// }

// /// [json] Convert entire document including HTML element to JSON format
// pub fn fullDocumentToJsonTree(allocator: std.mem.Allocator, doc: *z.HTMLDocument) !JsonNode {
//     // Try to get HTML element if it exists
//     const html_element = z.bodyElement(doc) catch {
//         // Fallback to body if no HTML element found
//         const body_node = try z.bodyNode(doc);
//         return try domNodeToJson(allocator, body_node);
//     };

//     // Get parent of body (should be HTML element)
//     const body_node = z.elementToNode(html_element);
//     const html_node = z.parentNode(body_node) orelse body_node;

//     return try domNodeToJson(allocator, html_node);
// }

// /// [tree] Write text with HTML escaping
// fn writeEscapedText(text: []const u8) void {
//     for (text) |ch| {
//         switch (ch) {
//             '<' => print("&lt;", .{}),
//             '>' => print("&gt;", .{}),
//             '&' => print("&amp;", .{}),
//             '"' => print("&quot;", .{}),
//             '\'' => print("&#39;", .{}),
//             else => print("{d}", .{ch}),
//         }
//     }
// }

// /// [tree] Round-trip conversion: HTML → Tree → HTML
// pub fn roundTripConversion(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
//     // Parse HTML to document
//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     // Convert to tree
//     const tree = try documentToTupleTree(allocator, doc);
//     defer freeHtmlTree(allocator, tree);

//     // Convert back to HTML
//     return try treeToHtml(allocator, tree);
// }

// test "complex HTML structure" {
//     const html =
//         \\<!-- Top comment is ignored-->
//         \\<html><head>
//         \\     <meta charset="UTF-8"/>
//         \\    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
//         \\    <title>Page</title>
//         \\  </head>
//         \\  <body>
//         \\   <div id="root" class="layout">
//         \\      Hello world
//         \\     <!-- Inner comment -->
//         \\     <p>
//         \\       <span data-id="1">Hello</span>
//         \\       <span data-id="2">world</span>
//         \\     </p>
//         \\     <img src="/assets/image.jpeg" alt="image">
//         \\     <form>
//         \\       <input class="input" value="" name="name">
//         \\     </form>
//         \\     <script>
//         \\       console.log(1 && 2);
//         \\     </script>
//         \\     <style>
//         \\       .parent > .child {
//         \\         &:hover {
//         \\            display: none;
//         \\         }
//         \\        }
//         \\      </style>
//         \\      &amp; &lt; &gt; &quot; &#39; € 🔥 🐈
//         \\      <div class="&amp; &lt; &gt; &quot; &#39; € 🔥 🐈"></div>
//         \\     </div>
//         \\  </body></html>
//     ;

//     const allocator = testing.allocator;
//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     const full_tree = try doc_toTuple(
//         allocator,
//         doc,
//     );
//     defer freeTupleNode(allocator, full_tree);

//     const body_node = try z.bodyNode(doc);
//     // try z.printDocStruct(doc);
//     try z.cleanDomTree(
//         allocator,
//         z.documentRoot(doc).?,
//         .{
//             .remove_empty_elements = true,
//             .remove_comments = true,
//         },
//     );
//     const txt = try z.outerHTML(allocator, z.nodeToElement(body_node).?);
//     defer allocator.free(txt);

//     // print("\nActual: ----------\n{s}\n\n", .{html});
//     // try z.printDocumentStructure(doc);
//     // print("\n\n Serialized: \n {s}\n\n", .{txt});
//     // printNode(full_tree, 0);
// }
// test "exact target format" {
//     const allocator = testing.allocator;

//     const html = "<html><head><title>Page</title></head><body>Hello world<!-- Link --></body></html>";

//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     // Try to get the full document tree starting from HTML
//     const full_tree = try doc_toTuple(allocator, doc);
//     defer freeTupleNode(allocator, full_tree);

//     // printNode(full_tree, 0);

//     // Verify it's an HTML element with children
//     switch (full_tree) {
//         .element => |elem| {
//             try testing.expectEqualStrings("HTML", elem.tag);
//             try testing.expect(elem.children.len > 0);
//         },
//         else => try testing.expect(false),
//     }
// }

// test "reverse operation: tree to HTML" {
//     const allocator = testing.allocator;

//     const simple_html = "<div><p>Hello</p><span>World</span></div>";

//     const doc = try z.parseFromString(simple_html);
//     defer z.destroyDocument(doc);

//     const tree = try documentToTupleTree(allocator, doc);
//     defer freeHtmlTree(allocator, tree);

//     const reconstructed = try treeToHtml(allocator, tree);
//     defer allocator.free(reconstructed);

//     try testing.expect(
//         std.mem.indexOf(u8, reconstructed, "<DIV>") != null,
//     );
//     try testing.expect(
//         std.mem.indexOf(u8, reconstructed, "<P>Hello</P>") != null,
//     );
//     try testing.expect(
//         std.mem.indexOf(u8, reconstructed, "<SPAN>World</SPAN>") != null,
//     );
// }

// test "round trip conversion" {
//     const allocator = testing.allocator;

//     const original_html = "<div class=\"test\"><p>Hello &amp; world</p><!-- comment --><br></div>";

//     const result = try roundTripConversion(allocator, original_html);
//     defer allocator.free(result);

//     try testing.expect(
//         std.mem.indexOf(u8, result, "DIV") != null,
//     );
//     try testing.expect(
//         std.mem.indexOf(u8, result, "class=\"test\"") != null,
//     );
//     try testing.expect(
//         std.mem.indexOf(u8, result, "Hello &amp; world") != null,
//     );
//     try testing.expect(
//         std.mem.indexOf(u8, result, "<!-- comment -->") != null,
//     );
// }

// test "void elements handling" {
//     const allocator = testing.allocator;

//     const html_with_void = "<div><br><img src=\"test.jpg\" alt=\"test\"><p>Text</p></div>";

//     const doc = try z.parseFromString(html_with_void);
//     defer z.destroyDocument(doc);

//     const tree = try documentToTupleTree(allocator, doc);
//     defer freeHtmlTree(allocator, tree);

//     const result = try treeToHtml(allocator, tree);
//     defer allocator.free(result);

//     // Debug: Print the result to see what we're getting
//     // std.debug.print("DOM tree HTML result: {s}\n", .{result});

//     // Should not have closing tags for void elements (they should be self-closing)
//     try testing.expect(
//         std.mem.indexOf(u8, result, "<br>") == null,
//     );
//     try testing.expect(
//         std.mem.indexOf(u8, result, "<img>") == null,
//     );
//     // Should have self-closing syntax for void elements
//     // try testing.expect(
//     // std.mem.indexOf(u8, result, "<BR />") != null,
//     // );
//     try testing.expect(
//         std.mem.indexOf(u8, result, "<IMG src=\"test.jpg\" alt=\"test\" >") != null,
//     );
//     try testing.expect(
//         std.mem.indexOf(u8, result, "</P>") != null,
//     ); // P should have closing tag
// }

// test "HTML escaping in reverse operation" {
//     const allocator = testing.allocator;

//     const html_with_entities = "<div>&lt;script&gt;alert('test')&lt;/script&gt;</div>";

//     const doc = try z.parseFromString(html_with_entities);
//     defer z.destroyDocument(doc);

//     const tree = try documentToTupleTree(allocator, doc);
//     defer freeHtmlTree(allocator, tree);

//     const result = try treeToHtml(allocator, tree);
//     defer allocator.free(result);

//     // Should properly escape dangerous content
//     try testing.expect(
//         std.mem.indexOf(u8, result, "&lt;") != null,
//     );
//     try testing.expect(
//         std.mem.indexOf(u8, result, "&gt;") != null,
//     );
// }

// test "JSON format conversion" {
//     const allocator = testing.allocator;

//     const html = "<div class=\"container\" id=\"main\"><p>Hello</p><!-- comment --><span>World</span></div>";

//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     const json_tree = try documentToJsonTree(allocator, doc);
//     defer freeJsonTree(allocator, json_tree);

//     // print("\n=== JSON Format ===\n", .{});
//     try testing.expect(json_tree.len > 0);

//     // Check the structure matches expected JSON format
//     switch (json_tree[0]) {
//         .element => |elem| {
//             try testing.expect(elem.nodeType == 1); // ELEMENT_NODE
//             try testing.expectEqualStrings("DIV", elem.tagName);
//             try testing.expect(elem.attributes.len == 2);
//             try testing.expect(elem.children.len >= 2);

//             // Check attributes in the new array format
//             var found_class = false;
//             var found_id = false;
//             for (elem.attributes) |attr| {
//                 if (std.mem.eql(u8, attr.name, "class")) {
//                     try testing.expectEqualStrings("container", attr.value);
//                     found_class = true;
//                 } else if (std.mem.eql(u8, attr.name, "id")) {
//                     try testing.expectEqualStrings("main", attr.value);
//                     found_id = true;
//                 }
//             }
//             try testing.expect(found_class and found_id);

//             // Check that children have proper nodeType
//             for (elem.children) |child| {
//                 switch (child) {
//                     .element => |child_elem| try testing.expect(child_elem.nodeType == 1),
//                     .text => |text_node| try testing.expect(text_node.nodeType == 3),
//                     .comment => |comment_node| try testing.expect(comment_node.nodeType == 8),
//                 }
//             }
//         },
//         else => try testing.expect(false),
//     }
// }

// test "W3C DOM JSON format example" {
//     const allocator = testing.allocator;

//     const html = "<div class=\"container\"><p>Hello</p><!-- comment --></div>";
//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     const json_tree = try documentToJsonTree(allocator, doc);
//     defer freeJsonTree(allocator, json_tree);

//     // print("\n=== W3C DOM JSON Format Example ===\n", .{});

//     // Demonstrate the new format structure
//     switch (json_tree[0]) {
//         .element => |elem| {
//             _ = elem;
//             // print("Element: nodeType={d}, tagName=\"{s}\"\n", .{ elem.nodeType, elem.tagName });
//             // print("Attributes ({d}):\n", .{elem.attributes.len});
//             // for (elem.attributes) |attr| {
//             // print("  {{ \"name\": \"{s}\", \"value\": \"{s}\" }}\n", .{ attr.name, attr.value });
//             // }
//             // print("Children ({d}):\n", .{elem.children.len});
//             // for (elem.children, 0..) |child, i| {
//             //     switch (child) {
//             //         .element => |child_elem| print(
//             //             "  [{d}]: Element nodeType={d}, tagName=\"{s}\"\n",
//             //             .{ i, child_elem.nodeType, child_elem.tagName },
//             //         ),
//             //         .text => |text_node| print(
//             //             "  [{d}]: Text nodeType={d}, data=\"{s}\"\n",
//             //             .{ i, text_node.nodeType, text_node.data },
//             //         ),
//             //         .comment => |comment_node| print(
//             //             "  [{d}]: Comment nodeType={d}, data=\"{s}\"\n",
//             //             .{ i, comment_node.nodeType, comment_node.data },
//             //         ),
//             //     }
//             // }
//         },
//         else => {},
//     }

//     // print("W3C DOM JSON format example completed!\n", .{});
// }

// test "JSON serialization and parsing round-trip" {
//     const allocator = testing.allocator;

//     const html = "<div class=\"container\" id=\"main\"><p>Hello World</p><!-- A comment --></div>";
//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     // Convert DOM to JsonNode
//     const json_tree = try documentToJsonTree(allocator, doc);
//     defer freeJsonTree(allocator, json_tree);

//     // print("\n=== JSON Serialization and Parsing Test ===\n", .{});

//     // Serialize JsonNode to JSON string
//     const json_string = try jsonNodeToString(allocator, json_tree[0]);
//     defer allocator.free(json_string);

//     // print("Serialized JSON:\n{s}\n", .{json_string});

//     // Parse JSON string back to JsonNode
//     const parsed_node = try parseJsonString(allocator, json_string);
//     defer freeJsonNode(allocator, parsed_node);

//     // Verify the round-trip worked
//     switch (parsed_node) {
//         .element => |elem| {
//             try testing.expect(elem.nodeType == 1);
//             try testing.expectEqualStrings("DIV", elem.tagName);
//             try testing.expect(elem.attributes.len == 2);
//             try testing.expect(elem.children.len == 2); // p element + comment

//             // Check first child is P element
//             switch (elem.children[0]) {
//                 .element => |p_elem| {
//                     try testing.expect(p_elem.nodeType == 1);
//                     try testing.expectEqualStrings("P", p_elem.tagName);
//                 },
//                 else => try testing.expect(false),
//             }

//             // Check second child is comment
//             switch (elem.children[1]) {
//                 .comment => |comment| {
//                     try testing.expect(comment.nodeType == 8);
//                     try testing.expectEqualStrings(" A comment ", comment.data);
//                 },
//                 else => try testing.expect(false),
//             }
//         },
//         else => try testing.expect(false),
//     }

//     // print("JSON round-trip test passed!\n", .{});
// }

// test "JSON array serialization" {
//     const allocator = testing.allocator;

//     const html = "<div>Hello</div><p>World</p>";
//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     const json_tree = try documentToJsonTree(allocator, doc);
//     defer freeJsonTree(allocator, json_tree);

//     // Serialize entire tree array to JSON
//     const json_string = try jsonTreeToString(allocator, json_tree);
//     defer allocator.free(json_string);

//     // print("\n=== JSON Array Serialization ===\n", .{});
//     // print("JSON Array:\n{s}\n", .{json_string});

//     // Parse back to tree
//     const parsed_tree = try parseJsonTreeString(allocator, json_string);
//     defer freeJsonTree(allocator, parsed_tree);

//     try testing.expect(parsed_tree.len == 2);

//     // print("JSON array test passed!\n", .{});
// }

// test "usage example: DOM to JSON and back" {
//     const allocator = testing.allocator;

//     // print("\n=== Complete Usage Example ===\n", .{});

//     // 1. Parse HTML
//     const html = "<article class=\"post\"><h1>Title</h1><p>Content</p><!-- metadata --></article>";
//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     // 2. Convert DOM to JsonNode
//     const json_tree = try documentToJsonTree(allocator, doc);
//     defer freeJsonTree(allocator, json_tree);

//     // 3. Serialize to JSON string (for storage, transmission, etc.)
//     const json_string = try jsonNodeToString(allocator, json_tree[0]);
//     defer allocator.free(json_string);
//     // print("Step 1 - DOM to JSON string:\n{s}\n\n", .{json_string});

//     // 4. Parse JSON string back to JsonNode (from storage, API, etc.)
//     const parsed_node = try parseJsonString(allocator, json_string);
//     defer freeJsonNode(allocator, parsed_node);
//     // print("Step 2 - Parsed back to JsonNode\n", .{});

//     // 5. Access the structured data
//     switch (parsed_node) {
//         .element => |elem| {
//             _ = elem;
//             // print("Step 3 - Access structured data:\n", .{});
//             // print("  Element: {s} (nodeType: {d})\n", .{ elem.tagName, elem.nodeType });
//             // print("  Attributes: {d}\n", .{elem.attributes.len});
//             // for (elem.attributes) |attr| {
//             //     print("    {s}=\"{s}\"\n", .{ attr.name, attr.value });
//             // }
//             // print("  Children: {d}\n", .{elem.children.len});
//             // for (elem.children, 0..) |child, i| {
//             //     switch (child) {
//             //         .element => |child_elem|
//             //         print("    [{d}]: Element <{s}>\n", .{ i, child_elem.tagName }),
//             //         .text => |text|
//             //         print("    [{d}]: Text \"{s}\"\n", .{ i, text.data }),
//             //         .comment => |comment|
//             //         print("    [{d}]: Comment \"{s}\"\n", .{ i, comment.data }),
//             //     }
//             // }
//         },
//         else => {},
//     }

//     // print(" Complete usage example finished!\n", .{});
// }
