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

// Opaque types
pub const HtmlDocument = opaque {};
pub const DomNode = opaque {};
pub const DomElement = opaque {};
pub const DomCollection = opaque {};
pub const DomAttr = opaque {};

pub const Comment: type = opaque {};

// pub const LXB_DOM_NODE_TYPE_ELEMENT: u32 = 1;
// pub const LXB_DOM_NODE_TYPE_TEXT: u32 = 3;
// pub const LXB_DOM_NODE_TYPE_COMMENT: u32 = 8;

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
    if (status != zhtml.LXB_STATUS_OK) return Err.ParseFailed;
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

// extern "c" fn lxb_dom_document_create_text_node(doc: *HtmlDocument, text: [*]const u8, text_len: usize) ?*DomNode;

// pub fn createTextNode(doc: *HtmlDocument, text: []const u8) !*DomNode {
//     return lxb_dom_document_create_text_node(
//         doc,
//         text.ptr,
//         text.len,
//     ) orelse Err.CreateTextNodeFailed;
// }

//============================================================================
// Comments
//============================================================================

extern "c" fn lxb_dom_document_create_comment(lxb_dom_document_t: *HtmlDocument, data: [*]const u8, len: usize) ?*Comment;

/// [lexbor] Create a comment node in the document
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

extern "c" fn lxb_dom_comment_interface_destroy(lxb_dom_comment_t: *Comment) *Comment;

/// [lexbor] Destroy a comment node in the document
pub fn destroyComment(comment: *Comment) void {
    _ = lxb_dom_comment_interface_destroy(comment);
}

/// [lexbor] Get comment text content
/// Needs to be freed by caller
pub fn getCommentTextContent(
    allocator: std.mem.Allocator,
    comment: *Comment,
) ![]u8 {
    const inner_text = try getNodeTextContentsOpts(
        allocator,
        objectToNode(comment),
        .{},
    );
    return inner_text;
}

//=============================================================================

extern "c" fn lexbor_get_body_element_wrapper(doc: *HtmlDocument) ?*DomElement;

/// [lexbor] Get the document's body element
pub fn getBodyElement(doc: *HtmlDocument) ?*DomElement {
    return lexbor_get_body_element_wrapper(doc);
}

extern "c" fn lexbor_dom_interface_node_wrapper(obj: *anyopaque) *DomNode;

/// [lexbor] Convert any lexbor object to DOM node
pub fn objectToNode(obj: *anyopaque) *DomNode {
    return lexbor_dom_interface_node_wrapper(obj);
}

extern "c" fn lexbor_dom_interface_element_wrapper(node: *DomNode) ?*DomElement;

/// [lexbor] Convert DOM node to Element (if it is one)
pub fn nodeToElement(node: *DomNode) ?*DomElement {
    return lexbor_dom_interface_element_wrapper(node);
}

/// [lexbor] Convert DOM Element to Node
pub fn elementToNode(element: *DomElement) *DomNode {
    return objectToNode(element);
}

/// [lexbor] Get document as DOM node for navigation
pub fn getDocumentNode(doc: *HtmlDocument) *DomNode {
    return objectToNode(doc);
}

extern "c" fn lxb_dom_node_name(node: *DomNode, len: ?*usize) [*:0]const u8;

/// [lexbor] Get node's tag name as Zig string
pub fn getNodeName(node: *DomNode) []const u8 {
    const name_ptr = lxb_dom_node_name(node, null);
    return std.mem.span(name_ptr);
}

/// [lexbor] Get element's tag name as Zig string
pub fn getElementName(element: *DomElement) []const u8 {
    const node = elementToNode(element);
    return getNodeName(node);
}

//=============================================================================
extern "c" fn lxb_dom_node_remove(node: *DomNode) void;

/// [lexbor] Remove a node from its parent
pub fn removeNode(node: *DomNode) void {
    lxb_dom_node_remove(node);
}

extern "c" fn lxb_dom_node_destroy(node: *DomNode) void;

/// [lexbor] Destroy a DOM node
pub fn destroyNode(node: *DomNode) void {
    lxb_dom_node_destroy(node);
}

//=============================================================================

test "create element and comment" {
    const allocator = std.testing.allocator;
    const doc = try createDocument();
    defer destroyDocument(doc);
    const element = try createElement(doc, .{ .tag = .div });
    defer destroyNode(elementToNode(element));
    const name = getElementName(element);
    try testing.expectEqualStrings("DIV", name);
    const comment = try createComment(doc, "This is a comment");
    const comment_text = try getCommentTextContent(
        allocator,
        comment,
    );
    defer allocator.free(comment_text);

    try testing.expectEqualStrings("This is a comment", comment_text);
    destroyComment(comment);
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

//=============================================================================

extern "c" fn lxb_html_node_is_void_noi(node: *DomNode) bool;

/// [lexbor] Check if element is void (self-closing like <img>, <br>)
pub fn isSelfClosingNode(node: *DomNode) bool {
    return lxb_html_node_is_void_noi(node);
}

extern "c" fn lxb_dom_node_is_empty(node: *DomNode) bool;

/// [lexbor] Check if node contains only whitespace
pub fn isNodeEmpty(node: *DomNode) bool {
    return lxb_dom_node_is_empty(node);
}

test "void vs empty element detection" {
    const html =
        \\<div>
        \\  <br/>
        \\  <img src="test.jpg"/>
        \\  <p>Not void</p>
        \\  <div>  </div>
        \\  <p><span></span></>
        \\</div>
    ;

    const doc = try parseFragmentAsDocument(html);
    defer destroyDocument(doc);

    const body = getBodyElement(doc).?;
    const body_node = elementToNode(body);
    const div_node = getNodeFirstChildNode(body_node).?;

    // print("\Void Element Test ========\n", .{});

    var child = getNodeFirstChildNode(div_node);
    const void_elements = [_][]const u8{ "BR", "HR", "IMG", "INPUT", "META", "LINK", "AREA" };

    var empty_non_self_closing_non_text_nodes_count: usize = 0;
    var empty_text_nodes_count: usize = 0;
    var empty_nodes: usize = 0;

    while (child != null) {
        if (nodeToElement(child.?)) |_| {
            const tag_name = getNodeName(child.?);
            const is_void = isSelfClosingNode(child.?);
            const is_empty = isNodeEmpty(child.?);

            // print("Element: {s} - is void?: {}, is empty?: {}, is non-text empty?: {}\n", .{ tag_name, is_void, is_empty, is_non_text_empty });

            // Expected void elements
            const should_be_void =
                for (void_elements) |void_elem| {
                    if (std.mem.eql(u8, tag_name, void_elem)) break true;
                } else false;

            if (should_be_void) {
                empty_nodes += 1;
                // void elements are considered empty
                try testing.expect(is_empty and is_void);
            } else {
                try testing.expect(!is_void);
                // a non-void can be empty or not
                if (is_empty) {
                    empty_nodes += 1;
                    if (zhtml.isNodeTextType(child.?)) {
                        empty_text_nodes_count += 1;
                    } else {
                        empty_non_self_closing_non_text_nodes_count += 1;
                    }
                }
            }
        }

        child = getNodeNextSiblingNode(child.?);
    }
    // print("Count result: {d}, {d}, {d}\n", .{ empty_nodes, empty_text_nodes_count, empty_non_self_closing_non_text_nodes_count });
    try testing.expect(empty_nodes == 8); // empty elements
    try testing.expect(empty_text_nodes_count == 5); // empty text elements
    try testing.expect(empty_non_self_closing_non_text_nodes_count == 1); // 1 empty non-self-closing non-text element
}

//=============================================================================
// DOM NAVIGATION
//=============================================================================

extern "c" fn lxb_dom_node_parent_noi(node: *DomNode) ?*DomNode;

/// [lexbor] Get the parent node of a given node
pub fn getNodeParentNode(node: *DomNode) ?*DomNode {
    return lxb_dom_node_parent_noi(node);
}

extern "c" fn lxb_dom_node_first_child_noi(node: *DomNode) ?*DomNode;

/// [lexbor] Get first child of node
pub fn getNodeFirstChildNode(node: *DomNode) ?*DomNode {
    return lxb_dom_node_first_child_noi(node);
}

extern "c" fn lxb_dom_node_next_noi(node: *DomNode) ?*DomNode;

/// [lexbor] Get next sibling of node
pub fn getNodeNextSiblingNode(node: *DomNode) ?*DomNode {
    return lxb_dom_node_next_noi(node);
}

extern "c" fn lxb_dom_node_insert_child(parent: *DomNode, child: *DomNode) void;

/// [lexbor] Insert child node into parent - no error handling needed since it returns void
pub fn insertNodeChildNode(parent: *DomNode, child: *DomNode) void {
    lxb_dom_node_insert_child(parent, child); // No status to check!
}

/// [lexbor] Get first element child (skip text nodes, comments, etc.)
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

/// [lexbor] Get next element sibling (skip text nodes)
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

/// [lexbor]  Helper: Collect only element children
/// Returns a slice of optional elements (no text nodes) and need to be freed
pub fn getNodeChildrenElements(
    allocator: std.mem.Allocator,
    parent_node: *DomNode,
) ![]*DomElement {
    var elements = std.ArrayList(*DomElement).init(allocator);
    // defer elements.deinit(); <-- defer is not needed here since we return the slice

    var child = getNodeFirstChildNode(parent_node);
    while (child != null) {
        if (zhtml.isNodeElementType(child.?)) {
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

pub const TextOptions = struct {
    escape: bool = false,
    skip_whitespace_nodes: bool = false,
    trim_whitespace: bool = false,
    preserve_newlines: bool = true,
    clean_empty_nodes: bool = false,
    clean_comments: bool = false,
};

extern "c" fn lxb_dom_node_text_content(node: *DomNode, len: ?*usize) ?[*:0]u8;

/// [lexbor] Get text content as Zig string (copies to Zig-managed memory)
/// Caller must free the returned string
pub fn getNodeAllTextContent(
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

/// [lexbor] Get text content with option to escape (default behavior is `.escape = false`)
/// If you need escaping, use `getNodeTextContentOpts` with `escape: true`
/// Caller must free the returned string
pub fn getNodeTextContentsOpts(
    allocator: std.mem.Allocator,
    node: *DomNode,
    opts: TextOptions,
) ![]u8 {
    const raw_text = try getNodeAllTextContent(allocator, node);
    defer allocator.free(raw_text);

    if (opts.escape) {
        return escapeHtml(allocator, raw_text);
    } else {
        return allocator.dupe(u8, raw_text);
    }
}

/// Set text content of a node
extern "c" fn lxb_dom_node_text_content_set(node: *DomNode, content: [*]const u8, len: usize) u8;

/// [lexbor] Set text content on empty node from Zig string
pub fn setNodeTextContent(node: *DomNode, content: []const u8) !void {
    const status = lxb_dom_node_text_content_set(
        node,
        content.ptr,
        content.len,
    );
    if (status != zhtml.LXB_STATUS_OK) return Err.SetTextContentFailed;
}

// extern "c" fn lxb_dom_document_destroy_text(doc: *anyopaque, text: [*]lxb_char_t) void;

/// Get owner document from node
extern "c" fn lexbor_node_owner_document(node: *DomNode) *HtmlDocument;

/// [lexbor] To test !!!!!!!!!!!
pub fn getNodeOwnerDocument(node: *DomNode) *HtmlDocument {
    return lexbor_node_owner_document(node);
}

/// Destroy text with proper cleanup
extern "c" fn lexbor_destroy_text_wrapper(node: *DomNode, text: ?[*:0]u8) void; //<- ?????

/// Free lexbor-allocated memory ????
extern "c" fn lexbor_free(ptr: *anyopaque) void;

/// [lexbor] HTML escape text content for safe output
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

    const text_content = try getNodeTextContentsOpts(
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
    const text_content = try getNodeTextContentsOpts(allocator, body_node, .{});
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
    const text = try getNodeTextContentsOpts(
        allocator,
        p_node,
        .{},
    );
    defer allocator.free(text);

    try testing.expectEqualStrings("Hello World!", text);
    const text_node = getNodeFirstChildNode(p_node);
    const strong_node = getNodeNextSiblingNode(text_node.?);
    const strong_text = try getNodeTextContentsOpts(
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

    const all_text = try getNodeTextContentsOpts(
        allocator,
        body_node,
        .{},
    );
    const first_text = try getNodeTextContentsOpts(
        allocator,
        first_child.?,
        .{},
    );
    const second_text = try getNodeTextContentsOpts(
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

/// [lexbor] Helper: Walk only element children, skipping text nodes
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

    const allocator = testing.allocator;
    const text = getNodeAllTextContent(allocator, p.?);
    try testing.expectError(Err.EmptyTextContent, text);
}

test "node with whitespace like characters IS empty but contains characters" {
    // this is "lxb_empty" too
    const doc = try parseFragmentAsDocument("<p> \n</p>");
    defer destroyDocument(doc);
    const body = getBodyElement(doc);
    const body_node = elementToNode(body.?);
    const p = getNodeFirstChildNode(body_node);
    try testing.expect(isNodeEmpty(p.?));

    const allocator = testing.allocator;
    const text = try getNodeAllTextContent(allocator, p.?);
    defer allocator.free(text);
    try testing.expect(text.len == 2); // 2 characters: ' ' and '\n'
}

test "node with (non empty) inenr text is NOT empty" {
    // node with inner text node
    const doc = try parseFragmentAsDocument("<p>Text</p>");
    defer destroyDocument(doc);
    const body = getBodyElement(doc);
    const body_node = elementToNode(body.?);
    const p = getNodeFirstChildNode(body_node);
    try testing.expect(!isNodeEmpty(p.?));
}

test "node with an (empty text content) node is NOT empty" {
    const doc2 = try parseFragmentAsDocument("<p><span><strong></strong></span></p>");
    defer destroyDocument(doc2);
    const body2 = getBodyElement(doc2);
    const body_node2 = elementToNode(body2.?);
    const p2 = getNodeFirstChildNode(body_node2);
    try testing.expect(!isNodeEmpty(p2.?));

    const allocator = testing.allocator;
    const text = getNodeAllTextContent(allocator, p2.?);
    try testing.expectError(Err.EmptyTextContent, text);
}

/// [lexbor] Check if text content is only whitespace characters
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
    const text3 = "  \r \t \n";
    try testing.expect(isWhitepaceOnlyText(text3));

    const text4 =
        \\
        \\
    ;
    try testing.expect(text4.len == 1); // it is '\n', which IS a whitespace-only text
    try testing.expect(isWhitepaceOnlyText(text4));
}

// / [lexbor] Check only whitespace only TEXT nodes.
// / If the node is not a text node, it returns false.
// / If the node is a text node, it checks if its content is only whitespace.
// pub fn isWhitespaceOnlyTextNode(
//     // allocator: std.mem.Allocator,
//     node: *DomNode,
// ) !bool {
//     if (!zhtml.isNodeTextType(node)) return Err.NotTextNode;

//     if (isNodeEmpty(node)) return true;
//     return false;

//     // const text = try getNodeTextContentsOpts(allocator, node, .{});
//     // defer allocator.free(text);
//     // if (text.len == 0) return true;

//     // return isWhitepaceOnlyText(text);
// }

pub fn isWhitespaceOnlyNode(node: *DomNode) bool {
    if (isSelfClosingNode(node)) return false; // Self-closing nodes are not considered whitespace-only
    if (isNodeEmpty(node)) return true;
    return false;
}

test "isWhitespaceOnlyNode" {
    // one way to create some nodes
    const doc = try parseFragmentAsDocument("<p>   </p>");
    defer destroyDocument(doc);
    const body = getBodyElement(doc);
    const body_node = elementToNode(body.?);
    const p = getNodeFirstChildNode(body_node);

    try testing.expect(
        isWhitespaceOnlyNode(p.?),
    );

    // inner text node is whitespace-only
    const inner_text_node = getNodeFirstChildNode(p.?);
    try testing.expect(
        zhtml.isNodeTextType(inner_text_node.?),
    );

    try testing.expect(
        isWhitespaceOnlyNode(inner_text_node.?),
    );

    // other way to create some nodes
    destroyNode(p.?);
    const div = try createElement(doc, .{ .tag = .div });
    // defer destroyNode(elementToNode(div));
    const node_div = elementToNode(div);

    try setNodeTextContent(node_div, "\n \r  \t");
    // should be true
    try testing.expect(
        isWhitespaceOnlyNode(getNodeFirstChildNode(node_div).?),
    );
}

/// [lexbor] Check if a node contains only whitespace.
/// However, the node can contain only whitespace text nodes.
/// The function `getNodeTextContentsOpts` can be used to retrieve all the text content recursively inside.
pub fn isWhitespaceOnlyElement(element: *DomElement) bool {
    const node = elementToNode(element);
    return isWhitespaceOnlyNode(node);
}

test "isWhitespaceOnlyElement" {
    const doc = try parseFragmentAsDocument("<div>   </div>");
    defer destroyDocument(doc);
    const body = getBodyElement(doc);
    try testing.expect(
        !isWhitespaceOnlyElement(body.?),
    );

    const body_node = elementToNode(body.?);
    try testing.expect(
        !isNodeEmpty(body_node),
    );

    const div = getNodeFirstChildNode(body_node) orelse {
        try testing.expect(false);
        return;
    };

    try testing.expect(
        isWhitespaceOnlyElement(nodeToElement(div).?),
    );

    // insert a P node and check it is not empty
    const p = try createElement(doc, .{ .tag = .p });
    insertNodeChildNode(div, elementToNode(p));
    try testing.expect(
        !isWhitespaceOnlyElement(nodeToElement(div).?),
    );

    // but its text content IS empty.
    const allocator = testing.allocator;
    const txt = try getNodeTextContentsOpts(allocator, div, .{});
    defer allocator.free(txt);
    try testing.expect(isWhitepaceOnlyText(txt));
}

// =============================================================================
// DOM CLEANING : HTML aware version
// =============================================================================

pub const DomCleanOptions = struct {
    remove_comments: bool = false,
    remove_empty_elements: bool = false, // Remove elements with no content (not just text nodes)
};

/// [lexbor] Clean DOM tree according to HTML standards + optional extras
pub fn cleanDomTree(
    allocator: std.mem.Allocator,
    root: *DomNode,
    options: DomCleanOptions,
) !void {
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
        .text => {
            if (!shouldPreserveWhitespace(node)) {
                node_was_removed = try maybeCleanOrRemoveTextNode(allocator, node);
            }
        },

        .element => {
            node_was_removed = try cleanElementNode(
                allocator,
                node,
                options,
            );
            // if (node_was_removed) print("was removed: {s}\n", .{getNodeName(node)});
        },
        .comment => {
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
) !bool {
    const element = nodeToElement(node) orelse return false;

    const size = try cleanElementAttributes(allocator, element);

    // Optional: remove empty elements with no attributes
    if (options.remove_empty_elements) {
        if (isWhitespaceOnlyNode(node) and size == 0) {
            destroyNode(node);
            return true;
        }
    }
    return false;
}

const AttributePair = struct {
    name: []u8,
    value: []u8,
};

fn cleanElementAttributes(
    allocator: std.mem.Allocator,
    element: *DomElement,
) !usize {
    var attr_list = std.ArrayList(AttributePair).init(allocator);
    defer {
        for (attr_list.items) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        attr_list.deinit();
    }

    const size = try collectElementAttributes(allocator, element, &attr_list);
    if (size == 0) return 0;

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
    return attr_list.items.len;
}

/// Collect all attributes from an element
fn collectElementAttributes(
    allocator: std.mem.Allocator,
    element: *zhtml.DomElement,
    attr_list: *std.ArrayList(AttributePair),
) !usize {
    var attr = zhtml.getElementFirstAttribute(element);
    if (attr == null) return 0; // No attributes to collect

    while (attr != null) {
        const name_copy = try zhtml.getAttributeName(allocator, attr.?);
        const value_copy = try zhtml.getAttributeValue(allocator, attr.?);

        try attr_list.append(.{ .name = name_copy, .value = value_copy });

        attr = zhtml.getElementNextAttribute(attr.?);
    }
    return attr_list.items.len;
}

fn maybeCleanOrRemoveTextNode(allocator: std.mem.Allocator, node: *DomNode) !bool {
    const text = try getNodeAllTextContent(allocator, node);
    defer allocator.free(text);
    if (isWhitepaceOnlyText(text)) {
        removeNode(node);
        return true;
    }

    // Trim and collapse whitespace (mandatory normalization)
    const cleaned = try normalizeTextWhitespace(allocator, text);
    defer allocator.free(cleaned);

    // Only update if content actually changed
    if (!std.mem.eql(u8, text, cleaned)) {
        // try setNodeTextContent(node, cleaned);
        try setOrReplaceNodeTextData(allocator, node, cleaned);
    }
    return false;
}

extern "c" fn lxb_dom_character_data_replace(node: *DomNode, data: [*]const u8, len: usize, offset: usize, count: usize) u8;

/// [lexbor] set or replace text data on a text node
/// If the inner text node is empty, it will be created.
pub fn setOrReplaceNodeTextData(
    allocator: std.mem.Allocator,
    node: *DomNode,
    text: []const u8,
) !void {
    const inner_text_node = getNodeFirstChildNode(node) orelse null;
    if (inner_text_node == null) {
        try setNodeTextContent(node, text);
    } else {
        const current_text = try getNodeTextContentsOpts(
            allocator,
            node,
            .{},
        );
        defer allocator.free(current_text);
        const status = lxb_dom_character_data_replace(
            inner_text_node.?,
            text.ptr,
            text.len,
            0, // Start at beginning
            current_text.len,
        );
        if (status != zhtml.LXB_STATUS_OK) return Err.SetTextContentFailed;
    }
}

test "setTextNodeData" {
    const allocator = testing.allocator;

    const doc = try createDocument();
    defer destroyDocument(doc);
    const element = try createElement(doc, .{ .tag = .div });
    defer destroyNode(elementToNode(element));
    const node = elementToNode(element);
    const first_inner_text_node = getNodeFirstChildNode(node) orelse null;

    try testing.expect(first_inner_text_node == null);

    // try setNodeTextContent(node, "Initial text");
    try setOrReplaceNodeTextData(allocator, node, "Initial text");

    const initial_text = try getNodeTextContentsOpts(allocator, node, .{});
    defer allocator.free(initial_text);
    try testing.expectEqualStrings("Initial text", initial_text);

    try setOrReplaceNodeTextData(allocator, node, "Updated text");

    const updated_text = try getNodeTextContentsOpts(allocator, node, .{});
    defer allocator.free(updated_text);
    try testing.expectEqualStrings("Updated text", updated_text);
}

fn shouldPreserveWhitespace(node: *DomNode) bool {
    // // debug -->
    // const allocator = testing.allocator;
    // const text = getNodeAllTextContent(allocator, node) catch return false;
    // defer allocator.free(text);
    // print("maybe preserving {s}, {s}\n", .{ getNodeName(node), text });
    // //  <-- debug

    const parent = getNodeParentNode(node) orelse return false;
    if (nodeToElement(parent)) |parent_element| {
        const tag_name = getElementName(parent_element);

        // leave these elements unchanged
        return std.mem.eql(u8, tag_name, "PRE") or
            std.mem.eql(u8, tag_name, "CODE") or
            std.mem.eql(u8, tag_name, "SCRIPT") or
            std.mem.eql(u8, tag_name, "STYLE") or
            std.mem.eql(u8, tag_name, "TEXTAREA");
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

test "normalizeTextWhitespace" {
    const allocator = testing.allocator;

    const messy_text = "  Hello   \t  World!  \n\n  ";
    const normalized = try normalizeTextWhitespace(allocator, messy_text);
    defer allocator.free(normalized);

    try testing.expectEqualStrings("Hello World!", normalized);
    // print("Normalized: {s}\n", .{normalized});
}

test "complete DOM cleaning with proper node removal" {
    const allocator = testing.allocator;

    const messy_html =
        \\<div   class  =  " container test "   id  = "main"  >
        \\    
        \\    <p>   Hello     World   </p>
        \\    
        \\    <!-- Remove this comment -->
        \\    <span data-id = "123"></span>
        \\    <pre>    preserve    this    </pre>
        \\    
        \\    <p>  </p>
        \\
        \\   <br/> <!-- This should be removed -->
        \\
        \\    <img src = 'http://google.com' alt = 'my-image' data-value=''/> 
        \\
        \\     <script> const div  = document.querySelector('div'); </script>
        \\</div>
    ;

    const doc = try parseFragmentAsDocument(messy_html);
    defer destroyDocument(doc);

    const body = getBodyElement(doc).?;
    const body_node = elementToNode(body);

    print("\n=== Complete DOM Cleaning Test ===\n", .{});

    const before = try zhtml.serializeTree(allocator, body_node);
    defer allocator.free(before);

    try cleanDomTree(
        allocator,
        body_node,
        .{
            .remove_comments = true,
            .remove_empty_elements = true,
        },
    );

    const after = try zhtml.serializeTree(allocator, body_node);
    defer allocator.free(after);
    print("\n\nAfter cleaning:=============\n{s}\n\n", .{after});

    // Verify results
    try testing.expect(std.mem.indexOf(u8, after, "<!--") == null); // Comments removed
    try testing.expect(std.mem.indexOf(u8, after, "Hello World") != null); // Text normalized
    try testing.expect(std.mem.indexOf(u8, after, "<span></span>") == null); // Empty elements removed
    try testing.expect(std.mem.indexOf(u8, after, "class=\"container test\"") != null); // Attributes cleaned
    try testing.expect(std.mem.indexOf(u8, after, "    preserve    ") != null); // <pre> preserved

    // printDocumentStructure(doc);

    print("✅ Complete DOM cleaning works perfectly!\n", .{});
}
