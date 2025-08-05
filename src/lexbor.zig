const std = @import("std");

const LexborError = @import("errors.zig").LexborError;

const testing = std.testing;
const print = std.debug.print;

//=============================================================================
// TYPES AND CONSTANTS
//=============================================================================

// Lexbor types
pub const lxb_char_t = u8;
pub const lxb_status_t = usize;
pub const LXB_STATUS_OK: usize = 0;

pub const SliceU8 = []const u8;

// Opaque types
pub const HtmlDocument = opaque {};
pub const DomNode = opaque {};
pub const DomElement = opaque {};
pub const DomCollection = opaque {};
pub const DomAttr = opaque {};
pub const HtmlParser = opaque {};

// pub const HtmlDocument = lxb_html_document_t;
// pub const DomNode = lxb_dom_node_t;
// pub const DomElement = lxb_dom_element_t;
// pub const DomCollection = lxb_dom_collection_t;
// pub const DomAttr = lxb_dom_attr_t;
pub const NodeType = enum(u8) {
    element = 1,
    text = 3,
    comment = 8,
    document = 9,
    unknown = 0,
};

//=============================================================================
// CORE DOCUMENT FUNCTIONS
//=============================================================================

extern "c" fn lxb_html_document_create() ?*HtmlDocument;
extern "c" fn lxb_html_document_destroy(doc: *HtmlDocument) void;
extern "c" fn lxb_html_document_parse(doc: *HtmlDocument, html: [*]const u8, len: usize) usize;

/// Create a new HTML document
pub fn createDocument() !*HtmlDocument {
    return lxb_html_document_create() orelse LexborError.DocCreateFailed;
}

pub fn destroyDocument(doc: *HtmlDocument) void {
    lxb_html_document_destroy(doc);
}

/// Parse HTML into document
pub fn parseLxbDocument(doc: *HtmlDocument, html: SliceU8) !void {
    const status = lxb_html_document_parse(doc, html.ptr, html.len);
    if (status != LXB_STATUS_OK) return LexborError.ParseFailed;
}

/// Parse HTML string into new document (convenience function)
pub fn parseHtml(html: SliceU8) !*HtmlDocument {
    const doc = try createDocument();
    parseLxbDocument(doc, html) catch |err| {
        destroyDocument(doc);
        return err;
    };
    return doc;
}

//=============================================================================
// C WRAPPER FUNCTIONS (for macros/inline functions)
//=============================================================================

extern "c" fn lexbor_dom_interface_node_wrapper(obj: *anyopaque) *DomNode;
extern "c" fn lexbor_dom_interface_element_wrapper(node: *DomNode) ?*DomElement;
extern "c" fn lexbor_get_body_element_wrapper(doc: *HtmlDocument) ?*DomElement;
extern "c" fn lexbor_collection_make_wrapper(doc: *HtmlDocument, size: usize) ?*DomCollection;
extern "c" fn lexbor_create_dom_element(doc: *HtmlDocument, tag_name: [*]const u8, tag_len: usize) ?*DomElement;

//=============================================================================
// FRAGMENT PARSING
//=============================================================================

extern "c" fn lexbor_parse_fragment_as_document(html: [*]const u8, html_len: usize) ?*HtmlDocument;

/// Parse HTML fragment as a standalone document
pub fn parseFragmentAsDocument(fragment: SliceU8) !*HtmlDocument {
    return lexbor_parse_fragment_as_document(fragment.ptr, fragment.len) orelse LexborError.FragmentParseFailed;
}

//=============================================================================
// TYPE NODE/ELEMENT FUNCTIONS
//=============================================================================

/// Create a DOM element in the document
pub fn createElement(doc: *HtmlDocument, tag_name: SliceU8) !*DomElement {
    return lexbor_create_dom_element(doc, tag_name.ptr, tag_name.len) orelse LexborError.CreateElementFailed;
}

/// Get the document's body element
pub fn getBodyElement(doc: *HtmlDocument) ?*DomElement {
    return lexbor_get_body_element_wrapper(doc);
}

/// Convert any lexbor object to DOM node
pub fn objectToNode(obj: *anyopaque) *DomNode {
    return lexbor_dom_interface_node_wrapper(obj);
}

/// Convert DOM node to Element (if it is one)
pub fn nodeToElement(node: *DomNode) ?*DomElement {
    return lexbor_dom_interface_element_wrapper(node);
}

/// Convert DOM Element to Node
pub fn elementToNode(element: *DomElement) *DomNode {
    return objectToNode(element);
}

/// Get document as DOM node for navigation
pub fn getDocumentNode(doc: *HtmlDocument) *DomNode {
    return objectToNode(doc);
}

// Remove a DOM node
extern "c" fn lxb_dom_node_remove(node: *DomNode) void;
extern "c" fn lxb_dom_node_destroy(node: *DomNode) void;

/// Destroy a DOM node - wrapper for C function
pub fn destroyNode(node: *DomNode) void {
    lxb_dom_node_remove(node);
    lxb_dom_node_destroy(node);
}

/// Get node name - this one works directly
extern "c" fn lxb_dom_node_name(node: *DomNode, len: ?*usize) [*:0]const u8;

/// Get node's tag name as Zig string
pub fn getNodeName(node: *DomNode) SliceU8 {
    const name_ptr = lxb_dom_node_name(node, null);
    return std.mem.span(name_ptr);
}

/// Get element's tag name as Zig string
pub fn getElementName(element: *DomElement) SliceU8 {
    const node = elementToNode(element);
    return getNodeName(node);
}

test "getElementName" {
    const doc = try createDocument();
    defer destroyDocument(doc);
    const element = try createElement(doc, "div");
    defer destroyNode(elementToNode(element));
    // printDocumentStructure(doc);
    const name = getElementName(element);
    try testing.expectEqualStrings("DIV", name);
}

// lxb_dom_document_create_comment(lxb_dom_document_t *document, const lxb_char_t *data, size_t len)

test "create element" {
    const doc = try createDocument();
    defer destroyDocument(doc);
    const element = try createElement(doc, "div");
    defer destroyNode(elementToNode(element));
    const name = getElementName(element);
    try testing.expectEqualStrings("DIV", name);
}

test "check error get body of empty element" {
    const doc = try createDocument();
    defer destroyDocument(doc);
    const body_element = getBodyElement(doc) orelse
        LexborError.EmptyTextContent;

    const div = try createElement(doc, "div");
    defer destroyNode(elementToNode(div));

    try testing.expectError(LexborError.EmptyTextContent, body_element);
}

/// Get node type by parsing the node name
pub fn getNodeType(node: *DomNode) NodeType {
    const node_name = getNodeName(node);

    // Switch on common node name patterns
    if (std.mem.eql(u8, node_name, "#text")) {
        return .text;
    } else if (std.mem.eql(u8, node_name, "#comment")) {
        return .comment;
    } else if (std.mem.eql(u8, node_name, "#document")) {
        return .document;
    } else if (node_name.len > 0 and node_name[0] != '#') {
        // Regular HTML tag names (div, p, span, strong, em...)
        return .element;
    } else {
        return .unknown;
    }
}

/// human-readable type name
pub fn getNodeTypeName(node: *DomNode) SliceU8 {
    return switch (getNodeType(node)) {
        .element => "element",
        .text => "text",
        .comment => "comment",
        .document => "document",
        .unknown => "unknown",
    };
}

pub fn isElementNode(node: *DomNode) bool {
    return getNodeType(node) == .element;
}

pub fn isTextNode(node: *DomNode) bool {
    return getNodeType(node) == .text;
}

pub fn isCommentNode(node: *DomNode) bool {
    return getNodeType(node) == .comment;
}

pub fn isDocumentNode(node: *DomNode) bool {
    return getNodeType(node) == .document;
}

pub fn walkTreeWithTypes(node: *DomNode, depth: u32) void {
    var child = getFirstChild(node);
    while (child != null) {
        const name = getNodeName(child.?);
        const node_type = getNodeType(child.?);
        const type_name = getNodeTypeName(child.?);

        // Create indentation
        var i: u32 = 0;
        while (i < @min(depth, 10)) : (i += 1) {
            std.debug.print("  ", .{});
        }

        std.debug.print("{s} ({s})\n", .{ name, type_name });

        // Only recurse into elements
        if (node_type == .element) {
            walkTreeWithTypes(child.?, depth + 1);
        }

        child = getNextSibling(child.?);
    }
}

// test "node type detection using getNodeName" {
//     const fragment =
//         \\<!-- This is a comment -->
//         \\<div>
//         \\  Some text content
//         \\  <span>nested element</span>
//         \\  More text
//         \\  <em>  </em>
//         \\</div>
//     ;

//     const doc = try parseFragmentAsDocument(fragment);
//     defer destroyDocument(doc);
//     printDocumentStructure(doc);

//     std.debug.print("\n--- NODE TYPE ANALYSIS ---\n", .{});

//     const body = getBodyElement(doc).?;
//     const body_node = elementToNode(body);

//     var child = getFirstChild(body_node);
//     while (child != null) {
//         const node_name = getNodeName(child.?);
//         const node_type = getNodeType(child.?);
//         const type_name = getNodeTypeName(child.?);

//         print("Node: '{s}' -> Type: {d} ({s})\n", .{ node_name, @intFromEnum(node_type), type_name });

//         // // Test helper functions
//         print("  isElement: {}, isText: {}, isComment: {}\n", .{ isElementNode(child.?), isTextNode(child.?), isCommentNode(child.?) });

//         child = getNextSibling(child.?);
//     }

//     print("\n-- TREE WITH TYPES --\n", .{});
//     walkTreeWithTypes(body_node, 0);
// }

//=============================================================================
// DOM NAVIGATION
//=============================================================================

/// Get first child - confirmed to exist
extern "c" fn lxb_dom_node_first_child_noi(node: *DomNode) ?*DomNode;

/// Get next sibling - confirmed to exist
extern "c" fn lxb_dom_node_next_noi(node: *DomNode) ?*DomNode;

/// Insert child - IMPORTANT: returns void, not status!
extern "c" fn lxb_dom_node_insert_child(parent: *DomNode, child: *DomNode) void;

/// Get first child of node
pub fn getFirstChild(node: *DomNode) ?*DomNode {
    return lxb_dom_node_first_child_noi(node);
}

/// Get next sibling of node
pub fn getNextSibling(node: *DomNode) ?*DomNode {
    return lxb_dom_node_next_noi(node);
}

/// Insert child node into parent - no error handling needed since it returns void
pub fn insertChild(parent: *DomNode, child: *DomNode) void {
    lxb_dom_node_insert_child(parent, child); // No status to check!
}

test "navigation & getNodeName" {
    const fragment = "<div></div><p></p>";
    const doc = try parseFragmentAsDocument(fragment);
    defer destroyDocument(doc);
    // printDocumentStructure(doc);

    const doc_node = getDocumentNode(doc);
    const body_element = getBodyElement(doc);

    try testing.expectEqualStrings(getNodeName(doc_node), "#document");
    try testing.expectEqualStrings("BODY", getElementName(body_element.?));

    const body_node = elementToNode(body_element.?);
    try testing.expectEqualStrings(getNodeName(body_node), "BODY");

    const first_child = getFirstChild(body_node);
    try testing.expectEqualStrings(getNodeName(first_child.?), "DIV");

    const next_sibling = getNextSibling(first_child.?);
    try testing.expectEqualStrings(getNodeName(next_sibling.?), "P");
}

test "insertChild" {
    const doc = try createDocument();
    defer destroyDocument(doc);
    const parent = try createElement(doc, "div");
    defer destroyNode(elementToNode(parent));

    const child = try createElement(doc, "span");
    defer destroyNode(elementToNode(child));
    insertChild(elementToNode(parent), elementToNode(child));

    const first_child = getFirstChild(elementToNode(parent)) orelse {
        return LexborError.EmptyTextContent;
    };
    const child_name = getElementName(nodeToElement(first_child).?);
    try testing.expectEqualStrings("SPAN", child_name);
}

//=============================================================================
// TEXT CONTENT FUNCTIONS -
//=============================================================================

/// Get text content of a node (returns allocated string)
/// WARNING: You must free the returned string with lexbor_free() <----- ?? check this!
extern "c" fn lxb_dom_node_text_content(node: *DomNode, len: ?*usize) ?[*:0]lxb_char_t;

/// Set text content of a node
extern "c" fn lxb_dom_node_text_content_set(node: *DomNode, content: [*]const lxb_char_t, len: usize) lxb_status_t;

/// Check if node is empty (only whitespace)
extern "c" fn lxb_dom_node_is_empty(node: *DomNode) bool;

/// Free lexbor-allocated memory
extern "c" fn lexbor_free(ptr: *anyopaque) void;

/// Get text content as Zig string (copies to Zig-managed memory)
/// Caller must free the returned string
pub fn getNodeTextContent(allocator: std.mem.Allocator, node: *DomNode) ![]u8 {
    var len: usize = 0;
    const text_ptr = lxb_dom_node_text_content(node, &len);

    if (len == 0) {
        // print("Text content length is 0 => returns error.EmptyTextContent\n", .{});
        return LexborError.EmptyTextContent;
    }

    const result = try allocator.alloc(u8, len);
    if (text_ptr) |t_ptr| {
        // Copy the text content to Zig-managed memory
        @memcpy(result, t_ptr[0..len]);
        return result;
    } else {
        return LexborError.EmptyTextContent;
    }
}

/// Set text content from Zig string
pub fn setNodeTextContent(node: *DomNode, content: SliceU8) !void {
    const status = lxb_dom_node_text_content_set(node, content.ptr, content.len);
    if (status != LXB_STATUS_OK) return LexborError.SetTextContentFailed;
}

test "getNodeTextContent empty node and whitespace only" {
    const allocator = std.testing.allocator;
    const doc = try createDocument();
    defer destroyDocument(doc);
    const element = try createElement(doc, "div");
    defer destroyNode(elementToNode(element));
    const node = elementToNode(element);

    try testing.expect(isNodeEmpty(node));

    // Should return error for empty node
    try testing.expectError(LexborError.EmptyTextContent, getNodeTextContent(allocator, node));

    try setNodeTextContent(node, "   ");

    const text_content = try getNodeTextContent(allocator, node);
    defer allocator.free(text_content);

    try testing.expect(isNodeEmpty(node));
    try testing.expect(text_content.len == 3);
    try testing.expectEqualStrings("   ", text_content);
}

test "get & set NodeTextContent" {
    const allocator = testing.allocator;
    const doc = try createDocument();
    const element = try createElement(doc, "div");
    defer destroyDocument(doc);
    const node = elementToNode(element);

    try setNodeTextContent(node, "Hello, world!");

    const text_content = try getNodeTextContent(allocator, node);
    defer allocator.free(text_content);

    try testing.expectEqualStrings("Hello, world!", text_content);
}

test "gets all text elements from Fragment" {
    const fragment = "<div><p>First<span>Second</span></p><p>Third</p></div><div><ul><li>Fourth</li><li>Fifth</li></ul></div>";

    const allocator = testing.allocator;
    const doc = try parseFragmentAsDocument(fragment);
    defer destroyDocument(doc);
    const body_element = getBodyElement(doc);
    const body_node = elementToNode(body_element.?);
    const text_content = try getNodeTextContent(allocator, body_node);
    defer allocator.free(text_content);
    try testing.expectEqualStrings("FirstSecondThirdFourthFifth", text_content);
}

test "getNodeTextContent" {
    const frag = "<p>First<span>Second</span></p><p>Third</p>";
    const allocator = std.testing.allocator;
    const doc = try parseFragmentAsDocument(frag);
    defer destroyDocument(doc);

    const body_element = getBodyElement(doc);
    const body_node = elementToNode(body_element.?);

    const first_child = getFirstChild(body_node);
    const second_child = getNextSibling(first_child.?);

    const all_text = try getNodeTextContent(allocator, body_node);
    const first_text = try getNodeTextContent(allocator, first_child.?);
    const second_text = try getNodeTextContent(allocator, second_child.?);

    defer allocator.free(all_text);
    defer allocator.free(first_text);
    defer allocator.free(second_text);

    try testing.expectEqualStrings("FirstSecondThird", all_text);
    try testing.expectEqualStrings("FirstSecond", first_text);
    try testing.expectEqualStrings("Third", second_text);
}

/// Helper: Collect only element children
/// Returns a slice of optional elements and need to be freed
pub fn getElementChildren(allocator: std.mem.Allocator, parent_node: *DomNode) ![]?*DomElement {
    var elements = std.ArrayList(?*DomElement).init(allocator);
    defer elements.deinit();

    var child = getFirstChild(parent_node);
    while (child != null) {
        if (nodeToElement(child.?)) |element| {
            try elements.append(element);
        }
        child = getNextSibling(child.?);
    }

    return elements.toOwnedSlice();
}

test "getElementChildren from createElement" {
    const allocator = std.testing.allocator;
    const doc = try createDocument();
    defer destroyDocument(doc);

    const parent = try createElement(doc, "div");
    defer destroyNode(elementToNode(parent));

    // Create some child elements
    const child1 = try createElement(doc, "span");
    defer destroyNode(elementToNode(child1));
    const child2 = try createElement(doc, "p");
    defer destroyNode(elementToNode(child2));

    insertChild(elementToNode(parent), elementToNode(child1));
    insertChild(elementToNode(parent), elementToNode(child2));

    // Get children
    const children = try getElementChildren(allocator, elementToNode(parent));
    defer allocator.free(children);

    try testing.expect(children.len == 2);
    try testing.expect(children[0] != null);
    try testing.expect(children[1] != null);
    for (children) |child| {
        // print("{s}\n", .{getElementName(child.?)});
        try testing.expect(isNodeEmpty(elementToNode(child.?)));
    }
}

test "getElementChildren from fragment" {
    const frag = "<div><span></span><p></p></div>";
    const allocator = std.testing.allocator;
    const doc = try parseFragmentAsDocument(frag);
    defer destroyDocument(doc);

    const body_element = getBodyElement(doc);
    const body_node = elementToNode(body_element.?);
    try testing.expectEqualStrings("BODY", getNodeName(body_node));

    const children1 = try getElementChildren(allocator, body_node);
    defer allocator.free(children1);
    try testing.expect(children1.len == 1); // Only one child <div>
    try testing.expect(!isNodeEmpty(body_node)); // DIV contains SPAN and P elements

    const div_node = children1[0] orelse return LexborError.EmptyTextContent;
    const children2 = try getElementChildren(allocator, elementToNode(div_node));
    defer allocator.free(children2);
    try testing.expect(children2[0] != null);
    try testing.expectEqualStrings(getElementName(children2[0].?), "SPAN");

    try testing.expect(children2[1] != null);
    try testing.expectEqualStrings(getElementName(children2[1].?), "P");

    for (children2) |child| {
        // print("{s}\n", .{getElementName(child.?)});
        try testing.expect(isNodeEmpty(elementToNode(child.?)));
    }
    // printDocumentStructure(doc);
}

/// Helper: Walk only element children, skipping text nodes
pub fn walkElementChildren(parent_node: *DomNode, callback: fn (element: ?*DomElement) void) void {
    var child = getFirstChild(parent_node);
    while (child != null) {
        if (nodeToElement(child.?)) |element| {
            callback(element);
        }
        child = getNextSibling(child.?);
    }
}

// test "what node types do we have?" {
//     const fragment =
//         \\<div>
//         \\  <p>Text</p>
//         \\</div>
//     ;
//     print("\nChecking what are nodes & elements: \n{s}\n", .{fragment});

//     const doc = try parseFragmentAsDocument(fragment);
//     defer destroyDocument(doc);

//     const body = getBodyElement(doc).?;
//     const body_node = elementToNode(body);
//     walkTree(body_node, 0);
//     const div_node = getFirstChild(body_node).?;

//     var child = getFirstChild(div_node);
//     var count: u32 = 0;

//     while (child != null) {
//         const name = getNodeName(child.?);
//         const is_element = nodeToElement(child.?) != null;

//         print("Child {}: name='{s}', is_element={}\n", .{ count, name, is_element });

//         child = getNextSibling(child.?);
//         count += 1;
//     }
// }

// =============================================================================
// Serialization Nodes and Elements
// =============================================================================
pub const lxbString = extern struct {
    data: ?[*]u8, // Pointer to string data
    length: usize, // String length
    size: usize, // Allocated size
};

/// Serialize DOM node to lexbor string structure
extern "c" fn lxb_html_serialize_str(node: *DomNode, str: *lxbString) usize;

/// Serialize node tree to lexbor string structure
extern "c" fn lxb_html_serialize_tree_str(node: *DomNode, str: *lxbString) usize;

/// Serialize node tree (most common use case)
/// Returns Zig-managed string that needs to be freed
pub fn serializeTree(allocator: std.mem.Allocator, node: *DomNode) ![]u8 {
    var str: lxbString = .{
        .data = null,
        .length = 0,
        .size = 0,
    };

    const status = lxb_html_serialize_tree_str(node, &str);
    if (status != LXB_STATUS_OK) {
        return LexborError.SerializeFailed;
    }

    if (str.data == null or str.length == 0) {
        return LexborError.NoBodyElement;
    }

    // Copy to Zig-managed memory
    const result = try allocator.alloc(u8, str.length);
    @memcpy(result, str.data.?[0..str.length]);

    // Note: We don't free str.data - lexbor manages it internally
    return result;
}

/// Serialize DOM node
/// Returns Zig-managed string that needs to be freed
pub fn serializeNode(allocator: std.mem.Allocator, node: *DomNode) !SliceU8 {
    var str: lxbString = .{
        .data = null,
        .length = 0,
        .size = 0,
    };

    const status = lxb_html_serialize_str(node, &str);
    if (status != LXB_STATUS_OK) {
        return LexborError.SerializeFailed;
    }

    if (str.data == null or str.length == 0) {
        return LexborError.NoBodyElement;
    }

    const result = try allocator.alloc(u8, str.length);
    @memcpy(result, str.data.?[0..str.length]);

    return result;
}

/// Serialize DOM element
pub fn serializeElement(allocator: std.mem.Allocator, element: *DomElement) !SliceU8 {
    const node = elementToNode(element);
    return try serializeTree(allocator, node);
}

test "direct serialization" {
    const allocator = testing.allocator;
    const fragment = "<div><p>Hi <strong>there</strong></p></div>";
    const doc = try parseFragmentAsDocument(fragment);
    defer destroyDocument(doc);

    if (getBodyElement(doc)) |body| {
        const body_node = elementToNode(body);

        if (getFirstChild(body_node)) |div_node| {
            const serialized = try serializeTree(allocator, div_node);
            defer allocator.free(serialized);

            try testing.expect(std.mem.indexOf(u8, serialized, "<div>") != null);
            try testing.expect(std.mem.indexOf(u8, serialized, "there") != null);
        }
    }
}

test "serialize Node vs tree functionality" {
    const allocator = testing.allocator;
    const fragment = "<div id=\"my-div\"><p class=\"bold\">Hello <strong>World</strong></p>   </div>";
    const doc = try parseFragmentAsDocument(fragment);
    defer destroyDocument(doc);

    const body = getBodyElement(doc) orelse {
        try testing.expect(false); // Should have body
        return;
    };
    const body_node = elementToNode(body);

    // Get the div element
    const div_node = getFirstChild(body_node) orelse {
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
    // print("{s}\n", .{node_html});
    // print("{s}\n", .{tree_html});

    // Both should contain the div tag
    try testing.expect(std.mem.indexOf(u8, node_html, "div") != null);
    try testing.expect(std.mem.indexOf(u8, tree_html, "div") != null);

    // Node_html contains only "<div id='my-div'>"
    try testing.expect(std.mem.indexOf(u8, node_html, "<p>") == null);
    try testing.expectEqualStrings("<div id=\"my-div\">", node_html);
    // Tree should definitely contain all content
    try testing.expect(std.mem.indexOf(u8, tree_html, "Hello") != null);
    try testing.expect(std.mem.indexOf(u8, tree_html, "<strong>World</strong>") != null);
    try testing.expect(std.mem.indexOf(u8, tree_html, "class=\"bold\"") != null);
}

//=============================================================================
// TO CHECK
// test "serializeNode on elements only" {
//     const allocator = testing.allocator;

//     const fragment =
//         \\<div id="container">
//         \\  <h1 class="title">Heading</h1>
//         \\  <p class="content">Paragraph text</p>
//         \\  <ul id="list">
//         \\    <li>Item 1</li>
//         \\    <li class="special">Item 2</li>
//         \\  </ul>
//         \\</div>
//     ;

//     const doc = try parseFragmentAsDocument(fragment);
//     defer destroyDocument(doc);

//     const body = getBodyElement(doc).?;
//     const body_node = elementToNode(body);
//     const container_node = getFirstChild(body_node).?;

//     // Walk children and only process ELEMENT nodes
//     var current_child = getFirstChild(container_node);
//     var element_count: u32 = 0;

//     while (current_child != null) {
//         const element_name = getNodeName(current_child.?);

//         print("Found node: '{s}'\n", .{element_name});

//         // Only process if it's an actual element (not #text)
//         if (nodeToElement(current_child.?)) |element| {
//             print("Processing element: '{s}'\n", .{element});

//             const serialized = serializeNode(allocator, current_child.?) catch |err| {
//                 print("Failed to serialize element '{s}': {}\n", .{ element, err });
//                 current_child = getNextSibling(current_child.?);
//                 continue;
//             };
//             defer allocator.free(serialized);

//             const trimmed = std.mem.trim(u8, serialized, " \t\n\r");
//             print("Element '{s}' serialized: '{s}'\n", .{ element, trimmed });

//             // Should contain the tag name
//             try testing.expect(std.mem.indexOf(u8, trimmed, element_name) != null);

//             element_count += 1;
//         } else {
//             print("Skipping text node: '{s}'\n", .{element_name});
//         }

//         current_child = getNextSibling(current_child.?);
//     }

//     print("Found {} element nodes\n", .{element_count});
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
        .{ .html = "<br/>", .serialized_node = "<br>", .serialized_tree = "<br>" },
        .{ .html = "<img src=\"my-image\"/>", .serialized_node = "<img src=\"my-image\">", .serialized_tree = "<img src=\"my-image\">" },
        .{ .html = "<p><span></span></p>", .serialized_node = "<p>", .serialized_tree = "<p><span></span></p>" },
        .{ .html = "<p></p>", .serialized_node = "<p>", .serialized_tree = "<p></p>" },
        .{ .html = "<div data-id=\"myid\" class=\"test\">Simple text</div>", .serialized_node = "<div data-id=\"myid\" class=\"test\">", .serialized_tree = "<div data-id=\"myid\" class=\"test\">Simple text</div>" },
    };

    for (test_cases) |case| {
        const doc = try parseFragmentAsDocument(case.html);
        defer destroyDocument(doc);

        const body = getBodyElement(doc).?;
        const body_node = elementToNode(body);
        const element_node = getFirstChild(body_node).?;

        const serial_node = try serializeNode(allocator, element_node);
        defer allocator.free(serial_node);

        const serialized_tree = try serializeTree(allocator, element_node);
        defer allocator.free(serialized_tree);

        try testing.expectEqualStrings(serial_node, case.serialized_node);
        try testing.expectEqualStrings(serialized_tree, case.serialized_tree);
    }
}

test "serialize Node & Tree error handling" {
    const allocator = testing.allocator;

    // Test with minimal document that might not have expected structure
    const minimal_doc = try createDocument();
    defer destroyDocument(minimal_doc);

    const doc_node = getDocumentNode(minimal_doc);

    // This might fail or return empty
    const serialized = try serializeNode(allocator, doc_node);

    defer allocator.free(serialized);
    // print("Document serialization: '{s}'\n", .{serialized});
    try testing.expectEqualStrings(serialized, "<#document>");
    const result = serializeTree(allocator, doc_node);
    try testing.expectError(LexborError.NoBodyElement, result);
}

test "serializeNode vs serializeTree comparison" {
    const allocator = testing.allocator;

    const fragment = "<article><header>Title</header><section>Content <span>inside</span></section></article>";

    const doc = try parseFragmentAsDocument(fragment);
    defer destroyDocument(doc);

    const body = getBodyElement(doc).?;
    const body_node = elementToNode(body);
    const article_node = getFirstChild(body_node).?;

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

//=============================================================================
// Whitespace and Empty Nodes
//=============================================================================

/// Check if node contains only whitespace
pub fn isNodeEmpty(node: *DomNode) bool {
    return lxb_dom_node_is_empty(node);
}

test "simple empty node" {
    const doc = try parseFragmentAsDocument("<p></p>");
    defer destroyDocument(doc);
    const body = getBodyElement(doc);
    const body_node = elementToNode(body.?);
    const p = getFirstChild(body_node);
    try testing.expect(isNodeEmpty(p.?));
}

test "node with whitespace is empty" {

    // this is "lxb_empty" too
    const new_doc = try parseFragmentAsDocument("<p>  </p>");
    defer destroyDocument(new_doc);
    const new_body = getBodyElement(new_doc);
    const new_body_node = elementToNode(new_body.?);
    const new_p = getFirstChild(new_body_node);
    try testing.expect(isNodeEmpty(new_p.?));
}

test "node with ascii text or any child node is not empty" {
    const doc = try parseFragmentAsDocument("<p>Text</p>");
    defer destroyDocument(doc);
    const body = getBodyElement(doc);
    const body_node = elementToNode(body.?);
    const p = getFirstChild(body_node);
    try testing.expect(!isNodeEmpty(p.?));

    // Check with (empty) child node
    const doc2 = try parseFragmentAsDocument("<p><span></span></p>");
    defer destroyDocument(doc2);
    const body2 = getBodyElement(doc2);
    const body_node2 = elementToNode(body2.?);
    const p2 = getFirstChild(body_node2);
    try testing.expect(!isNodeEmpty(p2.?));
}

pub fn isWhitepaceOnlyText(text: SliceU8) bool {
    if (text.len == 0) return true;
    for (text) |c| {
        if (!std.ascii.isWhitespace(c)) {
            return false; // Found non-whitespace character
        }
    }
    return true;
}

test "isWhitespaceOnlyText" {
    const text1 = " hello world ";
    try testing.expect(!isWhitepaceOnlyText(text1));
    const text2 = "  ";
    try testing.expect(isWhitepaceOnlyText(text2));
}

/// Check only whitespace only TEXT nodes.
/// If the node is not a text node, it returns false.
/// If the node is a text node, it checks if its content is only whitespace.
pub fn isWhitespaceOnlyTextNode(
    allocator: std.mem.Allocator,
    node: *DomNode,
) bool {
    if (!isTextNode(node)) {
        return false;
    }

    const text = getNodeTextContent(allocator, node) catch return false;
    defer allocator.free(text);
    if (text.len == 0) return true;

    return isWhitepaceOnlyText(text);
}

test "isWhitespaceOnlyTextNode" {
    const allocator = testing.allocator;

    const doc = try parseFragmentAsDocument("<p>   </p>");
    defer destroyDocument(doc);
    const body = getBodyElement(doc);
    const body_node = elementToNode(body.?);
    const p = getFirstChild(body_node);
    // print("test p: {}\n", .{isNodeEmpty(p.?)});
    const inner_text_node = getFirstChild(p.?) orelse {
        try testing.expect(false); // Should have inner text node
        return;
    };
    // Should be true for whitespace-only text node
    try testing.expect(isWhitespaceOnlyTextNode(allocator, inner_text_node));

    destroyNode(p.?);
    const div = try createElement(doc, "div");
    defer destroyNode(elementToNode(div));
    const node_div = elementToNode(div);
    try setNodeTextContent(node_div, "  ");
    try testing.expect(isWhitespaceOnlyTextNode(allocator, getFirstChild(node_div).?));
}

pub fn isWhitespaceOnlyElement(element: *DomElement) bool {
    const node = elementToNode(element);
    if (!isElementNode(node)) {
        return false;
    }
    return isNodeEmpty(node);
}

test "isWhitespaceOnlyElement" {
    const doc = try parseFragmentAsDocument("<div>   </div>");
    defer destroyDocument(doc);
    const body = getBodyElement(doc);
    const body_node = elementToNode(body.?);
    const div = getFirstChild(body_node) orelse {
        try testing.expect(false);
        return;
    };

    try testing.expect(isWhitespaceOnlyElement(nodeToElement(div).?));
}

pub fn removeWhitespaceOnlyTextNodes(
    allocator: std.mem.Allocator,
    parent_node: *DomNode,
) !void {
    var nodes_to_remove = std.ArrayList(*DomNode).init(allocator);
    defer nodes_to_remove.deinit();

    var child = getFirstChild(parent_node);
    while (child != null) {
        const node_type = getNodeType(child.?);

        switch (node_type) {
            .text => {
                // For text nodes, manually check if they contain only whitespace
                if (isWhitespaceOnlyTextNode(allocator, child.?)) {
                    // print("Removing whitespace-only text node\n", .{});
                    try nodes_to_remove.append(child.?);
                }
            },
            .element => {
                // For elements, first recurse into children
                try removeWhitespaceOnlyTextNodes(allocator, child.?);

                // Then check if the element itself is empty after cleanup
                if (isWhitespaceOnlyElement(nodeToElement(child.?).?)) {
                    // const element_name = getNodeName(child.?);
                    // print("Removing empty element: {s}\n", .{element_name});
                    try nodes_to_remove.append(child.?);
                }
            },
            .comment => {
                // Optionally remove comments
                // try nodes_to_remove.append(child.?);
            },
            else => {
                // Leave other node types alone
            },
        }

        child = getNextSibling(child.?);
    }

    // Remove collected nodes
    for (nodes_to_remove.items) |node| {
        destroyNode(node);
    }
}
test "debug whitespace removal" {
    const fragment =
        \\<div>
        \\  <p>   </p>
        \\  <span></span>
        \\  First text
        \\  <strong>Bold text</strong>
        \\  <em>  </em>
        \\</div>
    ;

    // const allocator = testing.allocator;
    const doc = try parseFragmentAsDocument(fragment);
    defer destroyDocument(doc);
    // printDocumentStructure(doc);
    // print("{s}\n", .{fragment});

    const body_element = getBodyElement(doc);
    const body_node = elementToNode(body_element.?);
    const div_node = getFirstChild(body_node).?;

    // print("\n=== ANALYZING EACH CHILD ===\n", .{});

    var child = getFirstChild(div_node);
    var index: u32 = 0;
    while (child != null) {
        // const node_name = getNodeName(child.?);
        // const is_empty = isNodeEmpty(child.?);

        // print("Child {}: '{s}' ({s}), isEmpty: {}\n", .{ index, node_name, getNodeTypeName(child.?), is_empty });

        // For text nodes, show the actual content
        // if (isTextNode(child.?)) {
        //     const text = getNodeTextContent(allocator, child.?) catch "ERROR";
        //     defer if (!std.mem.eql(u8, text, "ERROR")) allocator.free(text);
        // print("  Text content: '{s}'\n", .{text});
        // print("  Is whitespace only: {}\n", .{isWhitepaceOnlyText(text)});
        // }

        child = getNextSibling(child.?);
        index += 1;
    }
}

test "remove empty nodes" {
    const fragment =
        \\<div>
        \\  <p>   </p>
        \\  <span></span>
        \\  First text
        \\  <strong>Bold text</strong>
        \\  <em>  </em>
        \\</div>
    ;

    const allocator = testing.allocator;
    const doc = try parseFragmentAsDocument(fragment);
    defer destroyDocument(doc);

    // printDocumentStructure(doc);
    const body_element = getBodyElement(doc);
    const body_node = elementToNode(body_element.?);
    const html = try serializeTree(allocator, body_node);
    defer allocator.free(html);
    // print("HTML: {s}\n", .{html});

    try removeWhitespaceOnlyTextNodes(allocator, body_node);
    // printDocumentStructure(doc);

    const div = getFirstChild(body_node);
    const p = getFirstChild(div.?);
    try testing.expect(isNodeEmpty(p.?));

    const cleaned_html = try serializeTree(allocator, body_node);
    defer allocator.free(cleaned_html);
    // print("Cleaned HTML: {s}\n", .{cleaned_html});

    try testing.expect(std.mem.indexOf(u8, cleaned_html, "First text") != null);
    try testing.expect(std.mem.indexOf(u8, cleaned_html, "Bold text") != null);
    try testing.expect(std.mem.indexOf(u8, cleaned_html, "<p>") == null); // Should be removed
    try testing.expect(std.mem.indexOf(u8, cleaned_html, "<span></span>") == null); // Should be removed
}

/// Get only element children (filter out text/comment nodes)
pub fn getElementChildrenWithTypes(allocator: std.mem.Allocator, parent_node: *DomNode) ![]*DomElement {
    var elements = std.ArrayList(*DomElement).init(allocator);
    defer elements.deinit();

    var child = getFirstChild(parent_node);
    while (child != null) {
        if (isElementNode(child.?)) {
            if (nodeToElement(child.?)) |element| {
                try elements.append(element);
            }
        }
        child = getNextSibling(child.?);
    }

    return elements.toOwnedSlice();
}

test "debug element children filtering 1" {
    const allocator = testing.allocator;

    const fragment =
        \\<div>
        \\  <h1>Title</h1>
        \\  Some text
        \\  <p>Paragraph</p>
        \\  <!-- comment -->
        \\  <span>Span</span>
        \\</div>
    ;

    const doc = try parseFragmentAsDocument(fragment);
    defer destroyDocument(doc);

    const body = getBodyElement(doc).?;
    const body_node = elementToNode(body);
    const div_node = getFirstChild(body_node).?;

    const elements = try getElementChildrenWithTypes(allocator, div_node);
    defer allocator.free(elements);

    // print("Found {d} element children\n", .{elements.len});

    // for (elements, 0..) |element, i| {

    // const element_node = elementToNode(element);
    // const element_name = getNodeName(element_node);
    // std.debug.print("Element {}: {s}\n", .{ i + 1, element_name });
    // }

    // Should find h1, p, span (3 elements)
    try testing.expect(elements.len == 3);
}

// test "debug element children filtering 2" {
//     const allocator = testing.allocator;

//     const fragment =
//         \\<div>
//         \\  <h1>Title</h1>
//         \\  Some text
//         \\  <p>Paragraph</p>
//         \\  <!-- comment -->
//         \\  <span>Span</span>
//         \\</div>
//     ;

//     const doc = try parseFragmentAsDocument(fragment);
//     defer destroyDocument(doc);

//     const body = getBodyElement(doc).?;
//     const body_node = elementToNode(body);
//     const div_node = getFirstChild(body_node).?;

//     const elements = try getElementChildrenWithTypes(allocator, div_node);
//     defer allocator.free(elements);

//     // print("Found {d} element children\n", .{elements.len});

//     for (elements, 0..) |element, i| {
//         const element_node = elementToNode(element);
//         const element_name = getNodeName(element_node);
//         // print("Element {d}: {s}\n", .{ i + 1, element_name });
//     }

//     // Should find h1, p, span (3 elements)
//     try testing.expect(elements.len == 3);
// }

//=============================================================================
// UTILITY FUNCTIONS
//=============================================================================

/// Walk and print DOM tree (for debugging)
pub fn walkTree(node: *DomNode, depth: u32) void {
    var child = getFirstChild(node);
    while (child != null) {
        const name = getNodeName(child.?);
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
        child = getNextSibling(child.?);
    }
}

/// print document structure (for debugging)
pub fn printDocumentStructure(doc: *HtmlDocument) void {
    print("\n--- DOCUMENT STRUCTURE ----\n", .{});
    const root = getDocumentNode(doc);
    walkTree(root, 0);
}

/// Parse and display fragment (for testing)
pub fn demonstrateFragmentParsing(fragment: SliceU8) !void {
    std.debug.print("\nParsing fragment: {s}\n", .{fragment});

    const frag_doc = try parseFragmentAsDocument(fragment);
    defer destroyDocument(frag_doc);

    std.debug.print("Fragment parsed successfully!\n", .{});

    if (getBodyElement(frag_doc)) |body| {
        const body_node = elementToNode(body);
        walkTree(body_node, 0);
    }
}
