const std = @import("std");

const Err = @import("errors.zig").LexborError;
const zhtml = @import("zhtml.zig");
// const HtmlTag = @import("tags.zig").HtmlTag;

const testing = std.testing;
const print = std.debug.print;

//=============================================================================
// TYPES AND CONSTANTS
//=============================================================================

// Lexbor types
pub const lxb_char_t = u8;
pub const lxb_status_t = usize;
pub const LXB_STATUS_OK: usize = 0;

// Opaque types
pub const HtmlDocument = opaque {};
pub const DomNode = opaque {};
pub const DomElement = opaque {};
pub const DomCollection = opaque {};
pub const DomAttr = opaque {};
pub const HtmlParser = opaque {};
pub const Comment: type = opaque {};

pub const NodeType = enum(u8) {
    element = 1,
    text = 3,
    comment = 8,
    document = 9,
    unknown = 0,
    tag_template = 0x31,
    tag_style = 0x2d,
    tag_script = 0x29,
};

pub const LXB_DOM_NODE_TYPE_ELEMENT: u32 = 1;
pub const LXB_DOM_NODE_TYPE_TEXT: u32 = 3;
pub const LXB_DOM_NODE_TYPE_COMMENT: u32 = 8;

pub const LXB_TAG_TEMPLATE: u32 = 0x31; // From lexbor source
pub const LXB_TAG_STYLE: u32 = 0x2d;
pub const LXB_TAG_SCRIPT: u32 = 0x29;

//=============================================================================
// CORE DOCUMENT FUNCTIONS
//=============================================================================

extern "c" fn lxb_html_document_create() ?*HtmlDocument;
/// Create a new HTML document
pub fn createDocument() !*HtmlDocument {
    return lxb_html_document_create() orelse Err.DocCreateFailed;
}

extern "c" fn lxb_html_document_destroy(doc: *HtmlDocument) void;
pub fn destroyDocument(doc: *HtmlDocument) void {
    lxb_html_document_destroy(doc);
}

extern "c" fn lxb_html_document_parse(doc: *HtmlDocument, html: [*]const u8, len: usize) usize;
/// Parse HTML into document
pub fn parseDocHtml(doc: *HtmlDocument, html: []const u8) !void {
    const status = lxb_html_document_parse(doc, html.ptr, html.len);
    if (status != LXB_STATUS_OK) return Err.ParseFailed;
}

/// Parse HTML string into new document (convenience function)
pub fn parseHtml(html: []const u8) !*HtmlDocument {
    const doc = try createDocument();
    parseDocHtml(doc, html) catch |err| {
        destroyDocument(doc);
        return err;
    };
    return doc;
}

//=============================================================================
// FRAGMENT PARSING
//=============================================================================

extern "c" fn lexbor_parse_fragment_as_document(html: [*]const u8, html_len: usize) ?*HtmlDocument;
/// Parse HTML fragment as a standalone document
pub fn parseFragmentAsDocument(fragment: []const u8) !*HtmlDocument {
    return lexbor_parse_fragment_as_document(fragment.ptr, fragment.len) orelse Err.FragmentParseFailed;
}

// =============================================================================
// ELEMENT, COMMENT, TEXT CREATION
// =============================================================================

pub const ElementTag = union(enum) {
    tag: zhtml.HtmlTag,
    custom: []const u8,

    /// Helper to create from enum
    pub fn fromEnum(html_tag: zhtml.HtmlTag) ElementTag {
        return ElementTag{ .tag = html_tag };
    }

    /// Helper to create from string
    pub fn fromString(tag_name: []const u8) ElementTag {
        return ElementTag{ .custom = tag_name };
    }
};

extern "c" fn lexbor_create_dom_element(doc: *HtmlDocument, tag_name: [*]const u8, tag_len: usize) ?*DomElement;

// Create a DOM element in the document
/// tags are in an enum
pub fn createElement(
    doc: *HtmlDocument,
    tag: ElementTag,
) !*DomElement {
    const tag_name = switch (tag) {
        .tag => |enum_tag| enum_tag.toString(),
        .custom => |string_tag| string_tag,
    };
    return lexbor_create_dom_element(
        doc,
        tag_name.ptr,
        tag_name.len,
    ) orelse Err.CreateElementFailed;
}

/// Create element with attributes in one call
pub fn createElementWithAttrs(
    doc: *HtmlDocument,
    tag: zhtml.ElementTag,
    attrs: []const struct {
        name: []const u8,
        value: []const u8,
    },
) !*DomElement {
    const element = try createElement(doc, tag);

    for (attrs) |attr| {
        try zhtml.setAttribute(
            element,
            attr.name,
            attr.value,
        );
    }

    return element;
}

extern "c" fn lxb_dom_document_create_text_node(doc: *HtmlDocument, text: [*]const u8, text_len: usize) ?*DomNode;

pub fn createTextNode(doc: *HtmlDocument, text: []const u8) !*DomNode {
    return lxb_dom_document_create_text_node(
        doc,
        text.ptr,
        text.len,
    ) orelse Err.CreateTextNodeFailed;
}

// !!!!! TODO test these function

extern "c" fn lxb_dom_document_create_comment(lxb_dom_document_t: *HtmlDocument, data: [*]const u8, len: usize) ?*Comment;

/// Create a comment node in the document
pub fn createComment(
    doc: *HtmlDocument,
    data: []const u8,
) !*Comment {
    return lxb_dom_document_create_comment(
        doc,
        data.ptr,
        data.len,
    ) orelse Err.CreateCommentFailed;
}

// =============================================================================
extern "c" fn lxb_dom_comment_interface_destroy(lxb_dom_comment_t: *Comment) *Comment;

/// Destroy a comment node in the document
pub fn destroyComment(comment: *Comment) void {
    _ = lxb_dom_comment_interface_destroy(comment);
}
// =============================================================================

extern "c" fn lexbor_get_body_element_wrapper(doc: *HtmlDocument) ?*DomElement;

/// Get the document's body element
pub fn getBodyElement(doc: *HtmlDocument) ?*DomElement {
    return lexbor_get_body_element_wrapper(doc);
}

extern "c" fn lexbor_dom_interface_node_wrapper(obj: *anyopaque) *DomNode;

/// Convert any lexbor object to DOM node
pub fn objectToNode(obj: *anyopaque) *DomNode {
    return lexbor_dom_interface_node_wrapper(obj);
}

extern "c" fn lexbor_dom_interface_element_wrapper(node: *DomNode) ?*DomElement;

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

extern "c" fn lxb_dom_node_name(node: *DomNode, len: ?*usize) [*:0]const u8;

/// Get node's tag name as Zig string
pub fn getNodeName(node: *DomNode) []const u8 {
    const name_ptr = lxb_dom_node_name(node, null);
    return std.mem.span(name_ptr);
}

/// Get element's tag name as Zig string
pub fn getElementName(element: *DomElement) []const u8 {
    const node = elementToNode(element);
    return getNodeName(node);
}

// =============================================================================
extern "c" fn lxb_dom_node_remove(node: *DomNode) void;

/// Remove a node from its parent
pub fn removeNode(node: *DomNode) void {
    lxb_dom_node_remove(node);
}

extern "c" fn lxb_dom_node_destroy(node: *DomNode) void;

/// Destroy a DOM node
pub fn destroyNode(node: *DomNode) void {
    lxb_dom_node_destroy(node);
}
// =============================================================================

test "create element" {
    const doc = try createDocument();
    defer destroyDocument(doc);
    const element = try createElement(doc, .{ .tag = .div });
    defer destroyNode(elementToNode(element));
    const name = getElementName(element);
    try testing.expectEqualStrings("DIV", name);
}

test "check error get body of empty element" {
    const doc = try createDocument();
    defer destroyDocument(doc);
    const body_element = getBodyElement(doc) orelse
        Err.EmptyTextContent;

    const div = try createElement(doc, .{ .custom = "div" });
    defer destroyNode(elementToNode(div));

    try testing.expectError(Err.EmptyTextContent, body_element);
}

// ------------------------------------------------------------------------------------------

extern "c" fn lxb_html_node_is_void(node: *DomNode) bool;

/// Check if element is void (self-closing like <img>, <br>)
pub fn isVoidNode(node: *DomNode) bool {
    return lxb_html_node_is_void(node);
}

//=============================================================================
// DOM NAVIGATION
//=============================================================================

extern "c" fn lxb_dom_node_parent_noi(node: *DomNode) ?*DomNode;

/// Get the parent node of a given node
pub fn getNodeParentNode(node: *DomNode) ?*DomNode {
    return lxb_dom_node_parent_noi(node);
}

extern "c" fn lxb_dom_node_first_child_noi(node: *DomNode) ?*DomNode;

/// Get first child of node
pub fn getNodeFirstChildNode(node: *DomNode) ?*DomNode {
    return lxb_dom_node_first_child_noi(node);
}

extern "c" fn lxb_dom_node_next_noi(node: *DomNode) ?*DomNode;

/// Get next sibling of node
pub fn getNodeNextSiblingNode(node: *DomNode) ?*DomNode {
    return lxb_dom_node_next_noi(node);
}

extern "c" fn lxb_dom_node_insert_child(parent: *DomNode, child: *DomNode) void;

/// Insert child node into parent - no error handling needed since it returns void
pub fn insertNodeChildNode(parent: *DomNode, child: *DomNode) void {
    lxb_dom_node_insert_child(parent, child); // No status to check!
}

/// Get first element child (skip text nodes, comments, etc.)
pub fn getNodeFirstChildElement(node: *DomNode) ?*DomElement {
    var child = getNodeFirstChildNode(node);
    while (child != null) {
        if (nodeToElement(child.?)) |element| {
            return element;
        }
        child = getNodeNextSiblingNode(child.?);
    }
    return null;
}

/// Get next element sibling (skip text nodes)
pub fn getNodeNextSiblingElement(node: *DomNode) ?*DomElement {
    var sibling = getNodeNextSiblingNode(node);
    while (sibling != null) {
        if (nodeToElement(sibling.?)) |element| {
            return element;
        }
        sibling = getNodeNextSiblingNode(sibling.?);
    }
    return null;
}

// Helper: Collect only element children
// Returns a slice of optional elements (no text nodes) and need to be freed
pub fn getNodeChildrenElements(
    allocator: std.mem.Allocator,
    parent_node: *DomNode,
) ![]*DomElement {
    var elements = std.ArrayList(*DomElement).init(allocator);
    // defer elements.deinit(); <-- defer is not needed here since we return the slice

    var child = getNodeFirstChildNode(parent_node);
    while (child != null) {
        if (zhtml.isElementNode(child.?)) {
            if (nodeToElement(child.?)) |element| {
                try elements.append(element);
            }
        }
        child = getNodeNextSiblingNode(child.?);
    }

    return elements.toOwnedSlice();
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

    const first_child = getNodeFirstChildNode(body_node);
    try testing.expectEqualStrings(getNodeName(first_child.?), "DIV");

    const next_sibling = getNodeNextSiblingNode(first_child.?);
    try testing.expectEqualStrings(getNodeName(next_sibling.?), "P");
}

test "insertChild" {
    const doc = try createDocument();
    defer destroyDocument(doc);
    const parent = try createElement(doc, .{ .tag = .div });
    defer destroyNode(elementToNode(parent));

    const child = try createElement(doc, .{ .tag = .span });
    defer destroyNode(elementToNode(child));
    insertNodeChildNode(elementToNode(parent), elementToNode(child));

    const first_child = getNodeFirstChildNode(elementToNode(parent)) orelse {
        return Err.EmptyTextContent;
    };
    const child_name = getElementName(nodeToElement(first_child).?);
    try testing.expectEqualStrings("SPAN", child_name);
}

//=============================================================================
// TEXT CONTENT FUNCTIONS -
//=============================================================================

extern "c" fn lxb_dom_node_text_content(node: *DomNode, len: ?*usize) ?[*:0]u8;

/// Get text content as Zig string (copies to Zig-managed memory)
/// Caller must free the returned string
fn getTextContentFromNode(
    allocator: std.mem.Allocator,
    node: *DomNode,
) ![]u8 {
    var len: usize = 0;
    const text_ptr = lxb_dom_node_text_content(node, &len) orelse return Err.EmptyTextContent;

    defer lexbor_destroy_text_wrapper(node, text_ptr);

    if (len == 0) return Err.EmptyTextContent;

    const result = try allocator.alloc(u8, len);
    @memcpy(result, text_ptr[0..len]);
    return result;
}

/// Get text content with option to escape (default behavior is `.escape = false`)
/// If you need escaping, use `getTextContent` with `escape: true`
/// Caller must free the returned string
pub fn getNodeTextContentOpts(
    allocator: std.mem.Allocator,
    node: *DomNode,
    opts: TextOptions,
) ![]u8 {
    const raw_text = try getTextContentFromNode(allocator, node);
    defer allocator.free(raw_text);

    if (opts.escape) {
        return escapeHtml(allocator, raw_text);
    } else {
        return allocator.dupe(u8, raw_text);
    }
}

/// Set text content of a node
extern "c" fn lxb_dom_node_text_content_set(node: *DomNode, content: [*]const u8, len: usize) u8;

/// Set text content from Zig string
pub fn setNodeTextContent(node: *DomNode, content: []const u8) !void {
    const status = lxb_dom_node_text_content_set(
        node,
        content.ptr,
        content.len,
    );
    if (status != LXB_STATUS_OK) return Err.SetTextContentFailed;
}

// /// Replace text node content by removing old and creating new
// pub fn replaceNodeTextContent(
//     allocator: std.mem.Allocator,
//     text_node: *DomNode,
//     new_text: []const u8,
// ) !void {
//     const parent = getNodeParentNode(text_node) orelse return Err.NoParentNode;
//     const prev_sibling = getNodePreviousSiblingNode(text_node);
//     const next_sibling = getNodeNextSiblingNode(text_node);
//     try removeNode(text_node);

//     const doc = getOwnerDocument(parent);
//     const new_text_node = lxb_dom_document_create_text_node(doc, new_text.ptr, new_text.len) orelse {
//         return Err.CreateTextNodeFailed;
//     };

//     // Insert the new text node in the right position
//     if (next_sibling) |next| {
//         try insertBefore(parent, new_text_node, next);
//     } else {
//         try appendChild(parent, new_text_node);
//     }
// }

extern "c" fn lxb_dom_node_is_empty(node: *DomNode) bool;

/// Check if node contains only whitespace
pub fn isNodeEmpty(node: *DomNode) bool {
    return lxb_dom_node_is_empty(node);
}

// extern "c" fn lxb_dom_document_destroy_text(doc: *anyopaque, text: [*]lxb_char_t) void;

/// Get owner document from node
extern "c" fn lexbor_node_owner_document(node: *DomNode) *HtmlDocument;

/// Destroy text with proper cleanup
extern "c" fn lexbor_destroy_text_wrapper(node: *DomNode, text: ?[*:0]u8) void; //<- ?????

/// Free lexbor-allocated memory
extern "c" fn lexbor_free(ptr: *anyopaque) void;

/// HTML escape text content for safe output
pub fn escapeHtml(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    for (text) |ch| {
        switch (ch) {
            '<' => try result.appendSlice("&lt;"),
            '>' => try result.appendSlice("&gt;"),
            '&' => try result.appendSlice("&amp;"),
            '"' => try result.appendSlice("&quot;"),
            '\'' => try result.appendSlice("&#39;"),
            else => try result.append(ch),
        }
    }

    return result.toOwnedSlice();
}

test "HTML escaping" {
    const allocator = testing.allocator;

    const dangerous_text = "<script>alert('xss')</script> & \"quotes\"";
    const escaped = try escapeHtml(allocator, dangerous_text);
    defer allocator.free(escaped);

    const expected = "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt; &amp; &quot;quotes&quot;";
    try testing.expectEqualStrings(expected, escaped);

    // print("Original: {s}\n", .{dangerous_text});
    // print("Escaped:  {s}\n", .{escaped});
}

pub const TextOptions = struct {
    escape: bool = false,
    skip_whitespace_nodes: bool = false,
    trim_whitespace: bool = false,
    preserve_newlines: bool = true,
    clean_empty_nodes: bool = false,
    clean_comments: bool = false,
};

test "getNodeTextContent empty node and whitespace only" {
    const allocator = std.testing.allocator;
    const doc = try createDocument();
    defer destroyDocument(doc);
    const element = try createElement(doc, .{ .custom = "div" });
    defer destroyNode(elementToNode(element));
    const node = elementToNode(element);

    try testing.expect(isNodeEmpty(node));

    // Should return error for empty node
    try testing.expectError(Err.EmptyTextContent, getNodeTextContentOpts(allocator, node, .{}));

    try setNodeTextContent(node, "   ");

    const text_content = try getNodeTextContentOpts(
        allocator,
        node,
        .{},
    );
    defer allocator.free(text_content);

    try testing.expect(isNodeEmpty(node));
    try testing.expect(text_content.len == 3);
    try testing.expectEqualStrings("   ", text_content);
}

test "get & set NodeTextContent" {
    const allocator = testing.allocator;
    const doc = try createDocument();
    const element = try createElement(
        doc,
        .{ .tag = .div },
    );
    defer destroyDocument(doc);
    const node = elementToNode(element);

    try setNodeTextContent(node, "Hello, world!");

    const text_content = try getNodeTextContentOpts(
        allocator,
        node,
        .{},
    );
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
    const text_content = try getNodeTextContentOpts(allocator, body_node, .{});
    defer allocator.free(text_content);
    try testing.expectEqualStrings("FirstSecondThirdFourthFifth", text_content);
}

test "text content" {
    const allocator = testing.allocator;

    const html = "<p>Hello <strong>World</strong>!</p>";
    const doc = try parseFragmentAsDocument(html);
    defer destroyDocument(doc);

    const body = getBodyElement(doc).?;
    const body_node = elementToNode(body);
    const p_node = getNodeFirstChildNode(body_node).?;
    const text = try getNodeTextContentOpts(
        allocator,
        p_node,
        .{},
    );
    defer allocator.free(text);
    // print("text: {s}\n", .{text});

    try testing.expectEqualStrings("Hello World!", text);
    const text_node = getNodeFirstChildNode(p_node);
    const strong_node = getNodeNextSiblingNode(text_node.?);
    const strong_text = try getNodeTextContentOpts(
        allocator,
        strong_node.?,
        .{},
    );
    defer allocator.free(strong_text);
    // print("Strong text: {s}\n", .{strong_text});
    try testing.expectEqualStrings("World", strong_text);
}

test "getNodeTextContent" {
    const frag = "<p>First<span>Second</span></p><p>Third</p>";
    const allocator = std.testing.allocator;
    const doc = try parseFragmentAsDocument(frag);
    defer destroyDocument(doc);

    const body_element = getBodyElement(doc);
    const body_node = elementToNode(body_element.?);

    const first_child = getNodeFirstChildNode(body_node);
    const second_child = getNodeNextSiblingNode(first_child.?);

    const all_text = try getNodeTextContentOpts(
        allocator,
        body_node,
        .{},
    );
    const first_text = try getNodeTextContentOpts(
        allocator,
        first_child.?,
        .{},
    );
    const second_text = try getNodeTextContentOpts(
        allocator,
        second_child.?,
        .{},
    );

    defer allocator.free(all_text);
    defer allocator.free(first_text);
    defer allocator.free(second_text);

    try testing.expectEqualStrings("FirstSecondThird", all_text);
    try testing.expectEqualStrings("FirstSecond", first_text);
    try testing.expectEqualStrings("Third", second_text);
}

test "getElementChildren from createElement" {
    const allocator = std.testing.allocator;
    const doc = try createDocument();
    defer destroyDocument(doc);

    const parent = try createElement(doc, .{ .tag = .div });
    defer destroyNode(elementToNode(parent));

    // Create some child elements
    const child1 = try createElement(doc, .{ .tag = .span });
    defer destroyNode(elementToNode(child1));
    const child2 = try createElement(doc, .{ .tag = .p });
    defer destroyNode(elementToNode(child2));

    insertNodeChildNode(elementToNode(parent), elementToNode(child1));
    insertNodeChildNode(elementToNode(parent), elementToNode(child2));

    // Get children
    const children = try getNodeChildrenElements(allocator, elementToNode(parent));
    defer allocator.free(children);
    // print("len: {d}\n", .{children.len});

    try testing.expect(children.len == 2);
    for (children) |child| {
        // print("{s}\n", .{getElementName(child.?)});
        try testing.expect(isNodeEmpty(elementToNode(child)));
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

    const children1 = try getNodeChildrenElements(allocator, body_node);
    defer allocator.free(children1);
    try testing.expect(children1.len == 1); // Only one child <div>
    try testing.expect(!isNodeEmpty(body_node)); // DIV contains SPAN and P elements

    const div_node = children1[0];
    const children2 = try getNodeChildrenElements(allocator, elementToNode(div_node));
    defer allocator.free(children2);
    try testing.expectEqualStrings(getElementName(children2[0]), "SPAN");

    try testing.expectEqualStrings(getElementName(children2[1]), "P");

    for (children2) |child| {
        // print("{s}\n", .{getElementName(child.?)});
        try testing.expect(isNodeEmpty(elementToNode(child)));
    }
    // printDocumentStructure(doc);
}

/// Helper: Walk only element children, skipping text nodes
pub fn walkElementChildren(parent_node: *DomNode, callback: fn (element: ?*DomElement) void) void {
    var child = getNodeFirstChildNode(parent_node);
    while (child != null) {
        if (nodeToElement(child.?)) |element| {
            callback(element);
        }
        child = getNodeNextSiblingNode(child.?);
    }
}

//=============================================================================
// Whitespace and Empty Nodes
//=============================================================================

test "simple empty node" {
    const doc = try parseFragmentAsDocument("<p></p>");
    defer destroyDocument(doc);
    const body = getBodyElement(doc);
    const body_node = elementToNode(body.?);
    const p = getNodeFirstChildNode(body_node);
    try testing.expect(isNodeEmpty(p.?));
}

test "node with whitespace is empty" {

    // this is "lxb_empty" too
    const new_doc = try parseFragmentAsDocument("<p>  \n</p>");
    defer destroyDocument(new_doc);
    const new_body = getBodyElement(new_doc);
    const new_body_node = elementToNode(new_body.?);
    const new_p = getNodeFirstChildNode(new_body_node);
    try testing.expect(isNodeEmpty(new_p.?));
}

test "node with ascii text or any child node is not empty" {
    const doc = try parseFragmentAsDocument("<p>Text</p>");
    defer destroyDocument(doc);
    const body = getBodyElement(doc);
    const body_node = elementToNode(body.?);
    const p = getNodeFirstChildNode(body_node);
    try testing.expect(!isNodeEmpty(p.?));

    // Check with (empty) child node
    const doc2 = try parseFragmentAsDocument("<p><span></span></p>");
    defer destroyDocument(doc2);
    const body2 = getBodyElement(doc2);
    const body_node2 = elementToNode(body2.?);
    const p2 = getNodeFirstChildNode(body_node2);
    try testing.expect(!isNodeEmpty(p2.?));
}

pub fn isWhitepaceOnlyText(text: []const u8) bool {
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
    if (!zhtml.isTextNode(node)) {
        return false;
    }

    const text = getNodeTextContentOpts(
        allocator,
        node,
        .{},
    ) catch return false;
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
    const p = getNodeFirstChildNode(body_node);
    // print("test p: {}\n", .{isNodeEmpty(p.?)});
    const inner_text_node = getNodeFirstChildNode(p.?) orelse {
        try testing.expect(false); // Should have inner text node
        return;
    };
    // Should be true for whitespace-only text node
    try testing.expect(isWhitespaceOnlyTextNode(allocator, inner_text_node));

    destroyNode(p.?);
    const div = try createElement(doc, .{ .tag = .div });
    defer destroyNode(elementToNode(div));
    const node_div = elementToNode(div);
    try setNodeTextContent(node_div, "  ");
    try testing.expect(isWhitespaceOnlyTextNode(allocator, getNodeFirstChildNode(node_div).?));
}

pub fn isWhitespaceOnlyElement(element: *DomElement) bool {
    const node = elementToNode(element);
    if (!zhtml.isElementNode(node)) {
        return false;
    }
    return isNodeEmpty(node);
}

test "isWhitespaceOnlyElement" {
    const doc = try parseFragmentAsDocument("<div>   </div>");
    defer destroyDocument(doc);
    const body = getBodyElement(doc);
    const body_node = elementToNode(body.?);
    const div = getNodeFirstChildNode(body_node) orelse {
        try testing.expect(false);
        return;
    };

    try testing.expect(isWhitespaceOnlyElement(nodeToElement(div).?));
}

// =============================================================================
// DOM CLEANING : HTML aware version
// =============================================================================

pub const DomCleanOptions = struct {
    remove_comments: bool = false,
    remove_empty_elements: bool = false, // Remove elements with no content (not just text nodes)
};

/// Clean DOM tree according to HTML standards + optional extras
pub fn cleanDomTree(allocator: std.mem.Allocator, root: *DomNode, options: DomCleanOptions) !void {
    try cleanNodeRecursive(allocator, root, options);
}

fn cleanNodeRecursive(
    allocator: std.mem.Allocator,
    node: *DomNode,
    options: DomCleanOptions,
) !void {
    const node_type = zhtml.getNodeType(node);
    var node_was_removed = false;

    switch (node_type) {
        zhtml.NodeType.text => if (!shouldPreserveWhitespace(node)) {
            const text_content = try getNodeTextContentOpts(
                allocator,
                node,
                .{},
            );
            defer allocator.free(text_content);

            if (isWhitepaceOnlyText(text_content)) {
                // Remove entirely whitespace-only text nodes
                removeNode(node);
                node_was_removed = true;
            } else {
                // Clean existing text in-place
                try cleanTextNode(allocator, node);
            }
        },

        zhtml.NodeType.element => {
            const elt = nodeToElement(node);
            try cleanElementAttributes(allocator, elt.?);

            // Optional: remove empty elements
            if (options.remove_empty_elements and isNodeEmpty(node)) {
                removeNode(node);
                node_was_removed = true;
            }
        },
        zhtml.NodeType.comment => {
            if (options.remove_comments) {
                removeNode(node);
                node_was_removed = true;
            }
        },
        else => {},
    }

    // Recursively clean children (if node still exists)
    if (!node_was_removed) {
        var child = getNodeFirstChildNode(node);
        while (child != null) {
            const next_child = getNodeNextSiblingNode(child.?);
            try cleanNodeRecursive(allocator, child.?, options);
            child = next_child;
        }
    }
}

fn cleanElementNode(
    allocator: std.mem.Allocator,
    node: *DomNode,
    options: DomCleanOptions,
) !void {
    const element = nodeToElement(node) orelse return;
    // Always clean attributes (not optional)
    try cleanElementAttributes(allocator, element);

    // Optional: remove empty elements
    if (options.remove_empty_elements) {
        if (try isNodeEmpty(node)) {
            try destroyNode(node);
        }
    }
}

const AttributePair = struct {
    name: []u8,
    value: []u8,
};

fn cleanElementAttributes(
    allocator: std.mem.Allocator,
    element: *DomElement,
) !void {
    // Get all current attributes
    var attr_list = std.ArrayList(AttributePair).init(allocator);
    defer {
        for (attr_list.items) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        attr_list.deinit();
    }

    try collectElementAttributes(allocator, element, &attr_list);

    // Remove all existing attributes
    for (attr_list.items) |attr| {
        try zhtml.removeNamedAttributeFromElement(element, attr.name);
    }

    // Re-add with normalized whitespace
    for (attr_list.items) |attr| {
        const clean_name = std.mem.trim(u8, attr.name, &std.ascii.whitespace);
        const clean_value = std.mem.trim(u8, attr.value, &std.ascii.whitespace);

        // Skip empty attribute names (malformed HTML)
        if (clean_name.len > 0) {
            try zhtml.setNamedAttributeValueToElement(element, clean_name, clean_value);
        }
    }
}

/// Collect all attributes from an element
fn collectElementAttributes(
    allocator: std.mem.Allocator,
    element: *zhtml.DomElement,
    attr_list: *std.ArrayList(AttributePair),
) !void {
    var attr = zhtml.getElementFirstAttribute(element);

    while (attr != null) {
        const name_copy = try zhtml.getAttributeName(allocator, attr.?);
        const value_copy = try zhtml.getAttributeValue(allocator, attr.?);

        try attr_list.append(.{ .name = name_copy, .value = value_copy });

        attr = zhtml.getElementNextAttribute(attr.?);
    }
}

fn cleanTextNode(allocator: std.mem.Allocator, node: *DomNode) !void {
    // Skip cleaning in whitespace-significant contexts
    if (shouldPreserveWhitespace(node)) return;

    const text_content = try getNodeTextContentOpts(
        allocator,
        node,
        .{},
    );
    defer allocator.free(text_content);

    // Remove entirely whitespace-only text nodes (mandatory per HTML spec)
    if (isWhitepaceOnlyText(text_content)) {
        destroyNode(node);
        return;
    }

    // Trim and collapse whitespace (mandatory normalization)
    const cleaned = try normalizeTextWhitespace(allocator, text_content);
    defer allocator.free(cleaned);

    // Only update if content actually changed
    if (!std.mem.eql(u8, text_content, cleaned)) {
        // try setNodeTextContent(node, cleaned);
        try setTextNodeData(allocator, node, cleaned);
    }
}

extern "c" fn lxb_dom_character_data_replace(node: *DomNode, data: [*]const u8, len: usize, text_len: usize, count: usize) u8;

/// Set text data directly on a text node (simpler than setNodeTextContent)
pub fn setTextNodeData(
    allocator: std.mem.Allocator,
    node: *DomNode,
    text: []const u8,
) !void {
    const current_text = try getNodeTextContentOpts(
        allocator,
        node,
        .{},
    );
    defer allocator.free(current_text);
    // This should be simpler than the full DOM replace operation
    const status = lxb_dom_character_data_replace(
        node,
        text.ptr,
        text.len,
        0, // Start at beginning
        current_text.len,
    );
    if (status != LXB_STATUS_OK) return Err.SetTextContentFailed;
}

fn shouldPreserveWhitespace(node: *DomNode) bool {
    const parent = getNodeParentNode(node) orelse return false;
    if (nodeToElement(parent)) |parent_element| {
        const tag_name = getElementName(parent_element);
        // getNodeName(elementToNode(parent_element));

        // Per HTML spec: preserve whitespace in these elements
        return std.mem.eql(u8, tag_name, "PRE") or
            std.mem.eql(u8, tag_name, "CODE") or
            std.mem.eql(u8, tag_name, "SCRIPT") or
            std.mem.eql(u8, tag_name, "STYLE") or
            std.mem.eql(u8, tag_name, "TEXTAREA") or
            std.mem.eql(u8, tag_name, "XMP"); // Rare but part of spec
    }
    return false;
}

fn normalizeTextWhitespace(
    allocator: std.mem.Allocator,
    text: []const u8,
) ![]u8 {
    // Trim leading and trailing whitespace
    const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);

    // Collapse internal whitespace sequences to single spaces
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var prev_was_whitespace = false;
    for (trimmed) |ch| {
        if (std.ascii.isWhitespace(ch)) {
            if (!prev_was_whitespace) {
                try result.append(' '); // Normalize all whitespace to spaces
                prev_was_whitespace = true;
            }
        } else {
            try result.append(ch);
            prev_was_whitespace = false;
        }
    }

    return result.toOwnedSlice();
}

test "complete DOM cleaning with proper node removal" {
    const allocator = testing.allocator;

    const messy_html =
        \\<div   class  =  " container test "   id  = "main"  >
        \\    
        \\    <p>   Hello     World   </p>
        \\    
        \\    <!-- Remove this comment -->
        \\    <span></span>
        \\    <pre>    preserve    this    </pre>
        \\    
        \\    <p>  </p>
        \\    
        \\</div>
    ;

    const doc = try parseFragmentAsDocument(messy_html);
    defer destroyDocument(doc);

    const body = getBodyElement(doc).?;
    const body_node = elementToNode(body);

    print("\n=== Complete DOM Cleaning Test ===\n", .{});

    const before = try zhtml.serializeTree(allocator, body_node);
    defer allocator.free(before);
    print("Before cleaning:\n{s}\n\n", .{before});

    // Apply comprehensive cleaning
    try cleanDomTree(allocator, body_node, .{
        .remove_comments = true,
        .remove_empty_elements = true,
    });

    const after = try zhtml.serializeTree(allocator, body_node);
    defer allocator.free(after);
    print("After cleaning:\n{s}\n\n", .{after});

    // Verify results
    try testing.expect(std.mem.indexOf(u8, after, "<!--") == null); // Comments removed
    try testing.expect(std.mem.indexOf(u8, after, "Hello World") != null); // Text normalized
    try testing.expect(std.mem.indexOf(u8, after, "<span></span>") == null); // Empty elements removed
    try testing.expect(std.mem.indexOf(u8, after, "class=\"container test\"") != null); // Attributes cleaned
    try testing.expect(std.mem.indexOf(u8, after, "    preserve    ") != null); // <pre> preserved

    print("✅ Complete DOM cleaning works perfectly!\n", .{});
}

//=============================================================================
// Serialize DOM tree to HTML with cleaning options: string manipulation version
//=============================================================================
pub const StringOptions = struct {
    collapse_whitespace: bool = false, // Multiple spaces → single space
    normalize_newlines: bool = false, // \r\n → \n,
    remove_comments: bool = false, // Remove comments from the HTML
};

/// Serialize the DOM tree to HTML and clean it based on options
/// Returns a new owned slice of cleaned HTML.
/// The original HTML is trimmed of leading/trailing whitespace before cleaning.
/// If no options are set, it returns the original HTML as a new slice.
/// This function transfers ownership of the returned slice to the caller.
/// The options allow for:
/// - collapsing whitespace (multiple spaces → single space)
/// - normalizing newlines (\r\n → \n)
/// - removing comments (<!-- comment -->)
pub fn serializeTreeString(
    allocator: std.mem.Allocator,
    node: *DomNode,
    options: StringOptions,
) ![]u8 {
    const raw_html = try zhtml.serializeTree(
        allocator,
        node,
    );
    defer allocator.free(raw_html);

    const trimmed_html = std.mem.trim(
        u8,
        raw_html,
        &std.ascii.whitespace,
    );

    return try cleanSerializedHtmlString(
        allocator,
        trimmed_html,
        options,
    );
}

fn cleanSerializedHtmlString(
    allocator: std.mem.Allocator,
    html: []const u8,
    options: StringOptions,
) ![]u8 {
    // no options set, just return the original HTML
    if (!options.collapse_whitespace and !options.normalize_newlines and !options.remove_comments) {
        return allocator.dupe(u8, html);
    }

    var current_result = try allocator.dupe(u8, html);
    var current_memory: ?[]u8 = current_result;

    if (options.remove_comments) {
        const new_result = try removeStringComments(allocator, current_result);
        if (current_memory) |old| allocator.free(old);
        current_result = new_result;
        current_memory = new_result;
    }

    if (options.normalize_newlines) {
        const new_result = try normalizeStringNewlines(allocator, current_result);
        if (current_memory) |old| allocator.free(old);
        current_result = new_result;
        current_memory = new_result;
    }

    if (options.collapse_whitespace) {
        const new_result = try collapseStringWhitespace(allocator, current_result);
        if (current_memory) |old| allocator.free(old);
        return new_result;
    }
    return current_result; // No further processing needed
}

fn removeStringComments(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < html.len) {
        // Check for comment start: <!--
        if (i + 4 <= html.len and std.mem.eql(u8, html[i .. i + 4], "<!--")) {
            // Find comment end: -->
            var end_pos = i + 4;
            while (end_pos + 3 <= html.len) {
                if (std.mem.eql(u8, html[end_pos .. end_pos + 3], "-->")) {
                    // Skip the entire comment (including -->)
                    i = end_pos + 3;
                    break;
                }
                end_pos += 1;
            } else {
                // Comment not properly closed - treat as regular text
                try result.append(html[i]);
                i += 1;
            }
        } else {
            // Regular character
            try result.append(html[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

fn collapseStringWhitespace(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    var in_tag = false;
    var prev_was_whitespace = false;

    while (i < html.len) {
        const ch = html[i];

        if (ch == '<') {
            in_tag = true;
        } else if (ch == '>') {
            in_tag = false;
        }

        if (std.ascii.isWhitespace(ch)) {
            if (in_tag) {
                try result.append(ch);
            } else if (!prev_was_whitespace) {
                try result.append(' ');
                prev_was_whitespace = true;
            }
        } else {
            try result.append(ch);
            prev_was_whitespace = false;
        }

        i += 1;
    }

    return result.toOwnedSlice();
}

fn normalizeStringNewlines(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < text.len) {
        if (i + 1 < text.len and text[i] == '\r' and text[i + 1] == '\n') {
            try result.append('\n'); // \r\n → \n
            i += 2;
        } else if (text[i] == '\r') {
            try result.append('\n'); // \r → \n
            i += 1;
        } else {
            try result.append(text[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

test "HTML cleaning: string manipulation" {
    const allocator = testing.allocator;

    const messy_html =
        \\<div>
        \\    
        \\  <!-- This is a comment -->
        \\    <p>  Hello   World  </p>
        \\    
        \\    
        \\    <span>Test</span>
        \\    
        \\    <p>  </p>
        \\ <!-- Another comment
        \\         spanning multiple lines -->
        \\    
        \\</div>
    ;

    const doc = try parseFragmentAsDocument(messy_html);
    defer destroyDocument(doc);

    const body = getBodyElement(doc).?;
    const body_node = elementToNode(body);
    const div_node = getNodeFirstChildNode(body_node).?;

    const with_comments = try serializeTreeString(
        allocator,
        div_node,
        .{ .collapse_whitespace = true },
    );
    defer allocator.free(with_comments);
    // print("With comments:\n'{s}'\n\n", .{with_comments});

    // Test 2: Remove comments, keep whitespace structure
    const no_comments = try serializeTreeString(
        allocator,
        div_node,
        .{
            .remove_comments = true,
        },
    );
    defer allocator.free(no_comments);
    // print("No comments, preserve whitespace:\n'{s}'\n\n", .{no_comments});

    // Test 3: Remove comments AND collapse whitespace
    const clean_no_comments = try serializeTreeString(
        allocator,
        div_node,
        .{
            .remove_comments = true,
            .collapse_whitespace = true,
        },
    );
    defer allocator.free(clean_no_comments);
    // print("No comments, collapsed:\n'{s}'\n\n", .{clean_no_comments});

    // Verify comments are removed
    try testing.expect(std.mem.indexOf(u8, with_comments, "<!--") != null);
    try testing.expect(std.mem.indexOf(u8, no_comments, "<!--") == null);
    try testing.expect(std.mem.indexOf(u8, clean_no_comments, "<!--") == null);

    // Expected result for clean_no_comments:
    const expected = "<div> <p> Hello World </p> <span>Test</span> <p> </p> </div>";
    try testing.expectEqualStrings(expected, clean_no_comments);

    // print("✅ Comment removal working correctly!\n", .{});
}

test "edge cases for HTML cleaning: string manipulation" {
    const allocator = testing.allocator;

    // Test with attributes and mixed whitespace
    const html_with_attrs = "<div class=\"test\"   id=\"demo\">\n    <img src=\"test.jpg\"  alt=\"image\" />\n</div>";
    const doc = try parseFragmentAsDocument(html_with_attrs);
    defer destroyDocument(doc);

    const body = getBodyElement(doc).?;
    const body_node = elementToNode(body);
    const div_node = getNodeFirstChildNode(body_node).?;

    const cleaned = try serializeTreeString(
        allocator,
        div_node,
        .{ .collapse_whitespace = true },
    );
    defer allocator.free(cleaned);

    // print("Attributes preserved:\n'{s}'\n", .{cleaned});

    // Ensure attributes are preserved correctly
    try testing.expect(std.mem.indexOf(u8, cleaned, "class=\"test\"") != null);
    try testing.expect(std.mem.indexOf(u8, cleaned, "id=\"demo\"") != null);
    try testing.expect(std.mem.indexOf(u8, cleaned, "src=\"test.jpg\"") != null);
}

pub fn removeWhitespaceOnlyTextNodes(
    allocator: std.mem.Allocator,
    parent_node: *DomNode,
    opts: StringOptions,
) !void {
    var nodes_to_remove = std.ArrayList(*DomNode).init(allocator);
    defer nodes_to_remove.deinit();

    var child = getNodeFirstChildNode(parent_node);
    while (child != null) {
        const node_type = zhtml.getNodeType(child.?);

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
                try removeWhitespaceOnlyTextNodes(allocator, child.?, opts);

                // Then check if the element itself is empty after cleanup
                if (isWhitespaceOnlyElement(nodeToElement(child.?).?)) {
                    // const element_name = getNodeName(child.?);
                    // print("Removing empty element: {s}\n", .{element_name});
                    try nodes_to_remove.append(child.?);
                }
            },
            .comment => {
                // Optionally remove comments
                if (opts.remove_comments)
                    try nodes_to_remove.append(child.?);
            },
            else => {
                // Leave other node types alone
            },
        }

        child = getNodeNextSiblingNode(child.?);
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
    const div_node = getNodeFirstChildNode(body_node).?;

    // print("\n=== ANALYZING EACH CHILD ===\n", .{});

    var child = getNodeFirstChildNode(div_node);
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

        child = getNodeNextSiblingNode(child.?);
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
    const html = try zhtml.serializeTree(allocator, body_node);
    defer allocator.free(html);
    // print("HTML: {s}\n", .{html});

    try removeWhitespaceOnlyTextNodes(allocator, body_node, .{});
    // printDocumentStructure(doc);

    const div = getNodeFirstChildNode(body_node);
    const p = getNodeFirstChildNode(div.?);
    try testing.expect(isNodeEmpty(p.?));

    const cleaned_html = try zhtml.serializeTree(allocator, body_node);
    defer allocator.free(cleaned_html);
    // print("Cleaned HTML: {s}\n", .{cleaned_html});

    try testing.expect(std.mem.indexOf(u8, cleaned_html, "First text") != null);
    try testing.expect(std.mem.indexOf(u8, cleaned_html, "Bold text") != null);
    try testing.expect(std.mem.indexOf(u8, cleaned_html, "<p>") == null); // Should be removed
    try testing.expect(std.mem.indexOf(u8, cleaned_html, "<span></span>") == null); // Should be removed
}
// =============================================================================

/// Get only element children (filter out text/comment nodes)
pub fn getElementChildrenWithTypes(
    allocator: std.mem.Allocator,
    parent_node: *DomNode,
) ![]*DomElement {
    var elements = std.ArrayList(*DomElement).init(allocator);
    defer elements.deinit();

    var child = getNodeFirstChildNode(parent_node);
    while (child != null) {
        if (zhtml.isElementNode(child.?)) {
            if (nodeToElement(child.?)) |element| {
                try elements.append(element);
            }
        }
        child = getNodeNextSiblingNode(child.?);
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
    const div_node = getNodeFirstChildNode(body_node).?;

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
    var child = getNodeFirstChildNode(node);
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
        child = getNodeNextSiblingNode(child.?);
    }
}

/// print document structure (for debugging)
pub fn printDocumentStructure(doc: *HtmlDocument) void {
    print("\n--- DOCUMENT STRUCTURE ----\n", .{});
    const root = getDocumentNode(doc);
    walkTree(root, 0);
}

/// Parse and display fragment (for testing)
pub fn demonstrateFragmentParsing(fragment: []const u8) !void {
    std.debug.print("\nParsing fragment: {s}\n", .{fragment});

    const frag_doc = try parseFragmentAsDocument(fragment);
    defer destroyDocument(frag_doc);

    std.debug.print("Fragment parsed successfully!\n", .{});

    if (getBodyElement(frag_doc)) |body| {
        const body_node = elementToNode(body);
        walkTree(body_node, 0);
    }
}
