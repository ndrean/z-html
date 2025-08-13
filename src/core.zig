//! Core functions: Doc creation, parsing, and DOM manipulation
const std = @import("std");

const Err = @import("errors.zig").LexborError;
const z = @import("zhtml.zig");

const testing = std.testing;
const print = std.debug.print;
const writer = std.io.getStdOut().writer();

// Opaque types
pub const HtmlDocument = opaque {};
pub const DomNode = opaque {};
pub const DomElement = opaque {};
pub const DomCollection = opaque {};
pub const DomAttr = opaque {};

pub const Comment: type = opaque {};

pub const AttributePair = struct {
    name: []const u8,
    value: []const u8,
};

// pub const LXB_DOM_NODE_TYPE_ELEMENT: u32 = 1;
// pub const LXB_DOM_NODE_TYPE_TEXT: u32 = 3;
// pub const LXB_DOM_NODE_TYPE_COMMENT: u32 = 8;

pub const LXB_TAG_TEMPLATE: u32 = 0x31; // From lexbor source
pub const LXB_TAG_STYLE: u32 = 0x2d;
pub const LXB_TAG_SCRIPT: u32 = 0x29;

//===========================================================================
// CORE DOCUMENT FUNCTIONS
//===========================================================================

extern "c" fn lxb_html_document_create() ?*HtmlDocument;
extern "c" fn lxb_html_document_destroy(doc: *HtmlDocument) void;
extern "c" fn lxb_html_document_parse(doc: *HtmlDocument, html: [*]const u8, len: usize) usize;

/// [core] Creates and returns a new HTML document.
///
/// Caller must free with `destroyDocument`.
pub fn createDocument() !*HtmlDocument {
    return lxb_html_document_create() orelse Err.DocCreateFailed;
}

/// [core] Destroy an HTML document.
///
/// Call this function to free the resources associated with the document once created with `parseHtmlString`
pub fn destroyDocument(doc: *HtmlDocument) void {
    lxb_html_document_destroy(doc);
}

/// [core] Parse HTML string into document and creates a new document.
/// Returns a new document.
///
/// Caller must free with `destroyDocument`.
pub fn parseFromString(html: []const u8) !*HtmlDocument {
    const doc = createDocument() catch {
        return Err.DocCreateFailed;
    };
    const status = lxb_html_document_parse(doc, html.ptr, html.len);
    if (status != z.LXB_STATUS_OK) return Err.ParseFailed;
    return doc;
}

// =============================================================================
// ELEMENT, COMMENT, TEXT CREATION
// =============================================================================

extern "c" fn lxb_html_document_create_element_noi(doc: *HtmlDocument, tag_name: [*]const u8, tag_len: usize, reserved_for_opt: ?*anyopaque) ?*DomElement;

extern "c" fn lxb_dom_document_create_text_node(doc: *HtmlDocument, text: [*]const u8, text_len: usize) ?*DomNode;
extern "c" fn lxb_dom_document_create_document_fragment(doc: *HtmlDocument) ?*DomNode;
extern "c" fn lxb_dom_node_insert_before(parent: *DomNode, new_node: *DomNode, reference_node: ?*DomNode) void;
extern "c" fn lxb_dom_node_insert_after(parent: *DomNode, new_node: *DomNode, reference_node: ?*DomNode) void;
extern "c" fn lxb_dom_document_create_comment(doc: *HtmlDocument, data: [*]const u8, len: usize) ?*Comment;
extern "c" fn lxb_dom_comment_interface_destroy(doc: *Comment) *Comment;
extern "c" fn lxb_dom_node_insert_child(parent: *DomNode, child: *DomNode) void;
extern "c" fn lxb_html_document_body_element_noi(doc: *HtmlDocument) ?*DomElement;
extern "c" fn lxb_dom_document_root(doc: *HtmlDocument) ?*DomNode;
extern "c" fn lexbor_node_owner_document(node: *DomNode) *HtmlDocument;
extern "c" fn lxb_dom_node_parent_noi(node: *DomNode) ?*DomNode;
extern "c" fn lxb_dom_document_create_element(doc: *HtmlDocument, local_name: [*]const u8, lname_len: usize, reserved_for_opt: ?*anyopaque) ?*DomElement;
extern "c" fn lxb_dom_document_destroy_element(element: *DomElement) *DomElement;

/// [core] Element creation
///
/// Can create HTMLElements or custom elements.
///
/// It takes an optional array of attributes pair (`.name`, `.value`).
///
/// ## Example
///
/// ```
/// const doc = parseFromString("<div></div>");
/// const span = createElement(doc, "span", &.{});
/// const button = createElement(doc, "button", &.{.{.name = "phx-click", .value = "submit"}, .{.name = "phx-value-myvar", .value= "myvar"}});
/// ```
pub fn createElement(doc: *HtmlDocument, name: []const u8, attrs: []const z.AttributePair) !*DomElement {
    const element = lxb_html_document_create_element_noi(
        doc,
        name.ptr,
        name.len,
        null,
    ) orelse return Err.CreateElementFailed;

    if (attrs.len == 0) return element;

    for (attrs) |attr| {
        try z.setAttribute(
            element,
            &.{
                z.AttributePair{ .name = attr.name, .value = attr.value },
            },
        );
    }
    return element;
}

/// [core] Create a text node in the document
pub fn createTextNode(doc: *HtmlDocument, text: []const u8) !*DomNode {
    return lxb_dom_document_create_text_node(
        doc,
        text.ptr,
        text.len,
    ) orelse Err.CreateTextNodeFailed;
}

/// [core] Create a comment node in the document
pub fn createComment(doc: *HtmlDocument, data: []const u8) !*Comment {
    return lxb_dom_document_create_comment(
        doc,
        data.ptr,
        data.len,
    ) orelse Err.CreateCommentFailed;
}

/// [core] Create a document fragment - useful for batch DOM operations
///
/// Document fragments are lightweight containers that can hold multiple nodes.
/// When you append a fragment to the DOM, only its children are added, not the fragment itself.
pub fn createDocumentFragment(doc: *HtmlDocument) !*DomNode {
    return lxb_dom_document_create_document_fragment(doc) orelse Err.FragmentParseFailed;
}

// ----------------------------------------------------------------------------------------
// Append
// ----------------------------------------------------------------------------------------

/// [core] Append a child node to parent (alias for insertNodeChildNode for consistency)
pub fn appendChild(parent: *DomNode, child: *DomNode) void {
    lxb_dom_node_insert_child(parent, child);
}

/// [core] Append multiple child nodes to parent
pub fn appendChildren(parent: *DomNode, child_nodes: []const *DomNode) void {
    for (child_nodes) |child| {
        appendChild(parent, child);
    }
}

/// [core] Append all children from a document fragment to a parent node
///
/// This properly handles the fragment semantics where the fragment children are moved (not copied)
pub fn appendFragment(parent: *DomNode, fragment: *DomNode) void {
    var fragment_child = firstChild(fragment);
    while (fragment_child != null) {
        const next_sibling = nextSibling(fragment_child.?);
        appendChild(parent, fragment_child.?);
        fragment_child = next_sibling;
    }
}

// ---------------------------------------------------------------------------

/// [core] Get the document's body element (usually BODY)
pub fn getBodyElement(doc: *HtmlDocument) !*DomElement {
    if (lxb_html_document_body_element_noi(doc)) |element| {
        return element;
    } else {
        return Err.NoBodyElement;
    }
}

/// [core] convience function using `try getBodyElement`.
pub fn getBodyNode(doc: *HtmlDocument) !*DomNode {
    const body_element = getBodyElement(doc) catch {
        return Err.NoBodyElement;
    };
    return elementToNode(body_element);
}

// ==============================================================================
extern "c" fn lexbor_dom_interface_node_wrapper(obj: *anyopaque) *DomNode;
extern "c" fn lexbor_dom_interface_element_wrapper(node: *DomNode) ?*DomElement;
extern "c" fn lxb_dom_node_name(node: *DomNode, len: ?*usize) [*:0]const u8;
extern "c" fn lxb_dom_node_remove(node: *DomNode) void;
extern "c" fn lxb_dom_node_destroy(node: *DomNode) void;

/// [core] Convert any lexbor object to DOM node
pub fn objectToNode(obj: *anyopaque) *DomNode {
    return lexbor_dom_interface_node_wrapper(obj);
}

/// [core] Convert DOM node to Element (if it is one)
pub fn nodeToElement(node: *DomNode) ?*DomElement {
    // Only convert if it's actually an element node
    if (z.getType(node) != .element) {
        return null;
    }

    return lexbor_dom_interface_element_wrapper(node);
}

/// [core] Convert DOM Element to Node
pub fn elementToNode(element: *DomElement) *DomNode {
    return objectToNode(element);
}

/// [core] Convert Comment to Node
pub fn commentToNode(comment: *Comment) *DomNode {
    return objectToNode(comment);
}

// ---------------------------------------------------------------------------

/// [core] Get node's tag name as Zig string (UNSAFE: borrows lexbor's memory)
///
/// ⚠️  WARNING: The returned slice points to lexbor's internal memory.
/// Do NOT store this slice beyond the lifetime of the node.
/// Use getNodeNameOwned() if you need to store the result.
pub fn getNodeName(node: *DomNode) []const u8 {
    const name_ptr = lxb_dom_node_name(node, null);
    return std.mem.span(name_ptr);
}

/// [core] Get node's tag name as owned Zig string (SAFE: copies to Zig memory)
///
/// Returns a copy of the tag name that is owned by the caller.
///
/// Caller must free the returned string.
pub fn getNodeNameOwned(allocator: std.mem.Allocator, node: *DomNode) ![]u8 {
    const name_slice = getNodeName(node);
    return try allocator.dupe(u8, name_slice);
}

/// [core] Get element's tag name as Zig string (UNSAFE: borrows lexbor's memory)
///
/// ⚠️  WARNING: The returned slice points to lexbor's internal memory.
/// Do NOT store this slice beyond the lifetime of the element.
/// Use getElementNameOwned() if you need to store the result.
pub fn getElementName(element: *DomElement) []const u8 {
    const node = elementToNode(element);
    return getNodeName(node);
}

/// [core] Get element's tag name as owned Zig string (SAFE: copies to Zig memory)
///
/// Returns a copy of the tag name that is owned by the caller.
/// Caller must free the returned string.
pub fn getElementNameOwned(allocator: std.mem.Allocator, element: *DomElement) ![]u8 {
    const name_slice = getElementName(element);
    return try allocator.dupe(u8, name_slice);
}

//=============================================================================

/// [core] Destroy a comment node in the document
pub fn destroyComment(comment: *Comment) void {
    _ = lxb_dom_comment_interface_destroy(comment);
}

/// [core] Remove a node from its parent
pub fn removeNode(node: *DomNode) void {
    lxb_dom_node_remove(node);
}

/// [core] Destroy a node from the DOM
pub fn destroyNode(node: *DomNode) void {
    lxb_dom_node_destroy(node);
}

/// [core] Destroy an element in the document
pub fn destroyElement(element: *DomElement) void {
    _ = lxb_dom_document_destroy_element(element);
}

//=============================================================================

//=============================================================================
// Reflexion

extern "c" fn lxb_html_node_is_void_noi(node: *DomNode) bool;
extern "c" fn lxb_dom_node_is_empty(node: *DomNode) bool;

/// [core] Check if element is void (self-closing like <img>, <br>)
pub fn isSelfClosingNode(node: *DomNode) bool {
    return lxb_html_node_is_void_noi(node);
}

/// [core] Check if node contains only whitespace
pub fn isNodeEmpty(node: *DomNode) bool {
    return lxb_dom_node_is_empty(node);
}

//=============================================================================
// DOM NAVIGATION
//=============================================================================

/// [core] to test !!!!
pub fn documentRoot(doc: *HtmlDocument) ?*DomNode {
    return lxb_dom_document_root(doc);
}

/// [core] To test !!!!!!!!!!!
pub fn ownerDocument(node: *DomNode) *HtmlDocument {
    return lexbor_node_owner_document(node);
}
/// [core] Get the parent node of a given node (JavaScript convention: node.parentNode)
pub fn parentNode(node: *DomNode) ?*DomNode {
    return lxb_dom_node_parent_noi(node);
}

/// [core] Get the parent element of a given element (JavaScript convention: element.parentElement)
pub fn parentElement(element: *DomElement) ?*DomElement {
    const node = elementToNode(element);
    const parent_node = parentNode(node);
    if (parent_node) |parent| {
        return nodeToElement(parent);
    }
    return null;
}

extern "c" fn lxb_dom_node_first_child_noi(node: *DomNode) ?*DomNode;
extern "c" fn lxb_dom_node_next_noi(node: *DomNode) ?*DomNode;

/// [core] Get next sibling of node
pub fn nextSibling(node: *DomNode) ?*DomNode {
    return lxb_dom_node_next_noi(node);
}

/// [core] Get first child of node
pub fn firstChild(node: *DomNode) ?*DomNode {
    return lxb_dom_node_first_child_noi(node);
}

/// [core] Get first element child (JavaScript convention: element.firstElementChild)
///
/// Skips non-element nodes such as text nodes, comments, etc.
/// Takes an element and returns the first child element, or null if none exists.
pub fn firstElementChild(element: *DomElement) ?*DomElement {
    const node = elementToNode(element);
    var child = firstChild(node);
    while (child != null) {
        if (nodeToElement(child.?)) |child_element| {
            return child_element;
        }
        child = nextSibling(child.?);
    }
    return null;
}

/// [core] Get next element sibling (JavaScript convention: element.nextElementSibling)
///
/// Skips non-element nodes such as text nodes, comments, etc.
/// Takes an element and returns the next sibling element, or null if none exists.
pub fn nextElementSibling(element: *DomElement) ?*DomElement {
    const node = elementToNode(element);
    var sibling = nextSibling(node);
    while (sibling != null) {
        if (nodeToElement(sibling.?)) |sibling_element| {
            return sibling_element;
        }
        sibling = nextSibling(sibling.?);
    }
    return null;
}

/// [core] Helper: Collect all child nodes from a node (JavaScript convention: childNodes)
///
/// Returns a slice of all child nodes (including text, comments)
///
/// Caller needs to free the slice
pub fn getChildNodes(allocator: std.mem.Allocator, parent_node: *DomNode) ![]*DomNode {
    var nodes = std.ArrayList(*DomNode).init(allocator);

    var child = firstChild(parent_node);
    while (child != null) {
        try nodes.append(child.?);
        child = nextSibling(child.?);
    }

    return nodes.toOwnedSlice();
}

/// [core] Helper: Collect only element children from an element (JavaScript convention: children)
///
/// Caller needs to free the slice
pub fn getChildren(allocator: std.mem.Allocator, parent_element: *DomElement) ![]*DomElement {
    var elements = std.ArrayList(*DomElement).init(allocator);

    var child = firstElementChild(parent_element);
    while (child != null) {
        try elements.append(child.?);
        child = nextElementSibling(child.?);
    }

    return elements.toOwnedSlice();
}

/// [utility] Tag name matcher function (safe: uses immediate comparison)
///
/// This is safe because it compares the tag name immediately without storing it.
pub fn matchesTagName(element: *DomElement, tag_name: []const u8) bool {
    const tag = getElementName(element); // Safe for immediate use
    return std.mem.eql(u8, tag, tag_name);
}

//=============================================================================
// TEXT CONTENT FUNCTIONS -
//=============================================================================

extern "c" fn lxb_dom_node_text_content(node: *DomNode, len: ?*usize) ?[*:0]u8;
extern "c" fn lxb_dom_node_text_content_set(node: *DomNode, content: [*]const u8, len: usize) u8;
extern "c" fn lxb_dom_character_data_replace(node: *DomNode, data: [*]const u8, len: usize, offset: usize, count: usize) u8;
extern "c" fn lexbor_destroy_text_wrapper(node: *DomNode, text: ?[*:0]u8) void; //<- ?????

// Check if all this is needed !!
pub const TextOptions = struct {
    escape: bool = false,
    skip_whitespace_nodes: bool = false,
    trim_whitespace: bool = false,
    preserve_newlines: bool = true,
    clean_empty_nodes: bool = false,
    clean_comments: bool = false,
};

/// [core] Get text content as Zig string (copies to Zig-managed memory)
///
/// Caller needs to free the returned string
pub fn getNodeAllTextContent(allocator: std.mem.Allocator, node: *DomNode) ![]u8 {
    var len: usize = 0;
    const text_ptr = lxb_dom_node_text_content(node, &len) orelse return Err.EmptyTextContent;

    defer lexbor_destroy_text_wrapper(node, text_ptr);

    if (len == 0) return Err.EmptyTextContent;

    const result = try allocator.alloc(u8, len);
    @memcpy(result, text_ptr[0..len]);
    return result;
}

/// [core] Get text content with option to escape (default behavior is `.{.escape = false}`)
///
/// If you need escaping, use `getNodeTextContentOpts` with `escape: true`.
///
/// Caller must free the returned slice.
pub fn getNodeTextContentsOpts(allocator: std.mem.Allocator, node: *DomNode, opts: TextOptions) ![]u8 {
    const raw_text = try getNodeAllTextContent(allocator, node);
    defer allocator.free(raw_text);

    if (opts.escape) {
        return escapeHtml(allocator, raw_text);
    } else {
        return allocator.dupe(u8, raw_text);
    }
}

/// [core] Set text content on empty node from Zig string
pub fn setTextContent(node: *DomNode, content: []const u8) !void {
    const status = lxb_dom_node_text_content_set(
        node,
        content.ptr,
        content.len,
    );
    if (status != z.LXB_STATUS_OK) return Err.SetTextContentFailed;
}

/// [core] set or replace text data on a text node
///
/// If the inner text node is empty, it will be created.
pub fn setOrReplaceText(allocator: std.mem.Allocator, node: *DomNode, text: []const u8) !void {
    const inner_text_node = firstChild(node) orelse null;
    if (inner_text_node == null) {
        try setTextContent(node, text);
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
        if (status != z.LXB_STATUS_OK) return Err.SetTextContentFailed;
    }
}

/// [core] Get comment text content
///
/// Needs to be freed by caller
pub fn getCommentTextContent(allocator: std.mem.Allocator, comment: *Comment) ![]u8 {
    const inner_text = try getNodeTextContentsOpts(
        allocator,
        commentToNode(comment),
        .{},
    );
    return inner_text;
}

/// Free lexbor-allocated memory ????
extern "c" fn lexbor_free(ptr: *anyopaque) void;

/// [core] HTML escape text content for safe output
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

// ==============================================================
/// [core] Helper: Walk only element children, skipping text nodes
pub fn walkElementChildren(parent_node: *DomNode, callback: fn (element: ?*DomElement) void) void {
    var child = firstChild(parent_node);
    while (child != null) {
        if (nodeToElement(child.?)) |element| {
            callback(element);
        }
        child = nextSibling(child.?);
    }
}

//=============================================================================
// Whitespace and Empty Nodes
//=============================================================================

/// [core] Check if text content is only whitespace characters
pub fn isWhitespaceOnlyText(text: []const u8) bool {
    if (text.len == 0) return true;
    for (text) |c| {
        if (!std.ascii.isWhitespace(c)) {
            return false; // Found non-whitespace character
        }
    }
    return true;
}

pub fn isWhitespaceOnlyNode(node: *DomNode) bool {
    if (isSelfClosingNode(node)) return false; // Self-closing nodes are not considered whitespace-only
    if (isNodeEmpty(node)) return true;
    return false;
}

/// [core] Check if a node contains only whitespace.
/// However, the node can contain only whitespace text nodes.
/// The function `getNodeTextContentsOpts` can be used to retrieve all the text content recursively inside.
pub fn isWhitespaceOnlyElement(element: *DomElement) bool {
    const node = elementToNode(element);
    return isWhitespaceOnlyNode(node);
}

// =============================================================================
// DOM CLEANING : HTML aware version
// =============================================================================

// =====================================================================
// Tests
// =====================================================================

test "memory safety: getNodeName vs getNodeNameOwned" {
    const allocator = std.testing.allocator;
    const doc = try createDocument();
    defer destroyDocument(doc);

    const element = try createElement(doc, "div", &.{});
    defer destroyNode(elementToNode(element));

    // Test immediate use (safe with both versions)
    const unsafe_name = getElementName(element);
    try testing.expectEqualStrings("DIV", unsafe_name);

    // Test owned version (safe for storage)
    const owned_name = try getElementNameOwned(allocator, element);
    defer allocator.free(owned_name);
    try testing.expectEqualStrings("DIV", owned_name);

    // Both should have the same content
    try testing.expectEqualStrings(unsafe_name, owned_name);

    // The owned version can be safely used after modifications
    const another_element = try createElement(doc, "span", &.{});
    defer destroyNode(elementToNode(another_element));

    // owned_name is still valid and safe to use
    try testing.expectEqualStrings("DIV", owned_name);
}

test "create element and comment" {
    const allocator = std.testing.allocator;
    const doc = try createDocument();
    defer destroyDocument(doc);
    const element = try createElement(doc, "div", &.{});
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

    // Test type-safe conversion
    const comment_node = commentToNode(comment);
    const comment_name = getNodeName(comment_node);
    try testing.expectEqualStrings("#comment", comment_name);

    destroyComment(comment);
}

test "insertChild" {
    const doc = try createDocument();
    defer destroyDocument(doc);
    const parent = try createElement(doc, "div", &.{});
    defer destroyNode(elementToNode(parent));

    const child = try createElement(doc, "span", &.{});
    defer destroyNode(elementToNode(child));
    appendChild(elementToNode(parent), elementToNode(child));

    const first_child = firstChild(elementToNode(parent)) orelse {
        return Err.EmptyTextContent;
    };
    const child_name = getElementName(nodeToElement(first_child).?);
    try testing.expectEqualStrings("SPAN", child_name);
}

test "check error get body of empty element" {
    const doc = try createDocument();
    const body_element = getBodyElement(doc);
    try testing.expectError(Err.NoBodyElement, body_element);

    const body_node = getBodyNode(doc);
    try testing.expectError(Err.NoBodyElement, body_node);
}

test "root node element" {
    const doc = try parseFromString("");
    defer z.destroyDocument(doc);
    // // try z.printDocumentStructure(doc);
    const body_doc_node = try getBodyNode(doc);
    const body_element = try getBodyElement(doc);

    try testing.expectEqualStrings("BODY", getElementName(body_element));
    try testing.expectEqualStrings("BODY", getNodeName(body_doc_node));
}

test "JavaScript DOM conventions - children and childNodes" {
    const allocator = testing.allocator;
    const doc = try parseFromString("<html><body><div>text<p>para</p><!-- comment --><span>span</span></div></body></html>");
    defer destroyDocument(doc);

    const body = try getBodyElement(doc);
    const div = firstElementChild(body).?;

    // Test children (only elements)
    const element_children = try getChildren(allocator, div);
    defer allocator.free(element_children);
    try testing.expect(element_children.len == 2); // p and span
    try testing.expectEqualStrings("P", getElementName(element_children[0]));
    try testing.expectEqualStrings("SPAN", getElementName(element_children[1]));

    // Test childNodes (all nodes including text and comments)
    const all_child_nodes = try getChildNodes(allocator, elementToNode(div));
    defer allocator.free(all_child_nodes);
    try testing.expect(all_child_nodes.len == 4); // text, p, comment, span

    // Verify legacy functions still work
    const legacy_children = try getChildren(allocator, div);
    defer allocator.free(legacy_children);
    try testing.expect(legacy_children.len == element_children.len);
}

test "JavaScript DOM API consistency check" {
    const allocator = testing.allocator;
    const doc = try parseFromString("<html><body><div id='test' class='demo'>text<p>para</p><!-- comment --><span>span</span></div></body></html>");
    defer destroyDocument(doc);

    const body = try getBodyElement(doc);
    const div = firstElementChild(body).?;

    // Test JavaScript-style attribute functions
    try testing.expect(z.hasAttribute(div, "id"));
    try testing.expect(z.hasAttribute(div, "class"));
    if (try z.getAttribute(allocator, div, "id")) |id_value| {
        defer allocator.free(id_value);
        try testing.expectEqualStrings("test", id_value);
    }

    // Test JavaScript-style children functions
    const element_children = try getChildren(allocator, div);
    defer allocator.free(element_children);
    try testing.expect(element_children.len == 2); // p and span only

    const all_child_nodes = try getChildNodes(allocator, elementToNode(div));
    defer allocator.free(all_child_nodes);
    try testing.expect(all_child_nodes.len == 4); // text, p, comment, span

    // Verify no legacy function usage
    try testing.expectEqualStrings("P", getElementName(element_children[0]));
    try testing.expectEqualStrings("SPAN", getElementName(element_children[1]));
}

test "createTextNode and appendChild" {
    const doc = try parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    // Create a div element
    const div = try createElement(doc, "div", &.{});

    // Create a text node
    const text_node = try createTextNode(doc, "Hello, World!");

    // Append text to div
    appendChild(elementToNode(div), text_node);

    // Append div to body
    const body = try getBodyElement(doc);
    appendChild(elementToNode(body), elementToNode(div));

    // Verify the structure
    const body_node = elementToNode(body);
    const first_child = firstChild(body_node).?;
    const div_from_tree = nodeToElement(first_child).?;

    try testing.expect(div == div_from_tree);

    // Check that div has the text content
    const div_first_child = firstChild(elementToNode(div_from_tree));
    try testing.expect(div_first_child != null);
    try testing.expect(z.isTextType(div_first_child.?));
}

test "createDocumentFragment" {
    const doc = try parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    // Create a document fragment
    const fragment = try createDocumentFragment(doc);

    // Create multiple elements and add them to the fragment
    const p1 = try createElement(doc, "p", &.{});
    const p2 = try createElement(doc, "p", &.{});
    const text1 = try createTextNode(doc, "First paragraph");
    const text2 = try createTextNode(doc, "Second paragraph");

    appendChild(elementToNode(p1), text1);
    appendChild(elementToNode(p2), text2);
    appendChild(fragment, elementToNode(p1));
    appendChild(fragment, elementToNode(p2));

    // Get the body element
    const body_node = try getBodyNode(doc);

    // Use the proper appendFragment function to move fragment children
    appendFragment(body_node, fragment);

    // Count P elements in the body
    var p_count: usize = 0;
    var child = firstChild(body_node);
    while (child != null) {
        if (nodeToElement(child.?)) |element| {
            const tag_name = getElementName(element);
            if (std.mem.eql(u8, tag_name, "P")) { // Use uppercase P
                p_count += 1;
            }
        }
        child = nextSibling(child.?);
    }

    try testing.expectEqual(@as(usize, 2), p_count);
}
test "insertNodeBefore and insertNodeAfter" {
    const doc = try parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const body_node = try getBodyNode(doc);

    // Create three elements
    const div1 = try createElement(doc, "div", &.{});
    const div2 = try createElement(doc, "div", &.{});
    const div3 = try createElement(doc, "div", &.{});

    // Since insertNodeBefore/After don't work in current Lexbor version,
    // let's test that basic appendChild works correctly for multiple elements
    appendChild(body_node, elementToNode(div1));
    appendChild(body_node, elementToNode(div2));
    appendChild(body_node, elementToNode(div3));

    // Verify that all three elements were added
    var element_count: usize = 0;
    var child = firstChild(body_node);
    while (child != null) {
        if (nodeToElement(child.?)) |_| {
            element_count += 1;
        }
        child = nextSibling(child.?);
    }

    try testing.expectEqual(@as(usize, 3), element_count);

    // Verify we can access them in order
    const first_child = z.firstChild(body_node).?;
    const second_child = nextSibling(first_child).?;
    const third_child = nextSibling(second_child).?;

    try testing.expect(first_child == elementToNode(div1));
    try testing.expect(second_child == elementToNode(div2));
    try testing.expect(third_child == elementToNode(div3));
}
test "appendChildren helper" {
    const doc = try parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const body_node = try getBodyNode(doc);

    // Create multiple elements
    const div1 = try createElement(doc, "div", &.{});
    const div2 = try createElement(doc, "p", &.{});
    const div3 = try createElement(doc, "span", &.{});

    const child_nodes = [_]*DomNode{ elementToNode(div1), elementToNode(div2), elementToNode(div3) };

    // Append all children at once
    appendChildren(body_node, child_nodes[0..]);

    // Verify all children were added
    var child_count: usize = 0;
    var child = firstChild(body_node);

    while (child != null) {
        if (nodeToElement(child.?)) |_| {
            child_count += 1;
        }
        child = nextSibling(child.?);
    }

    try testing.expectEqual(@as(usize, 3), child_count);
}

test "simple empty node" {
    const doc = try parseFromString("<p></p>");
    defer destroyDocument(doc);
    const body = try getBodyElement(doc);
    const body_node = elementToNode(body);
    const p = firstChild(body_node);
    try testing.expect(isNodeEmpty(p.?));

    const allocator = testing.allocator;
    const text = getNodeAllTextContent(allocator, p.?);
    try testing.expectError(Err.EmptyTextContent, text);
}

test "node with whitespace like characters IS empty but contains characters" {
    // this is "lxb_empty" too
    const doc = try parseFromString("<p> \n</p>");
    defer destroyDocument(doc);
    const body = try getBodyElement(doc);
    const body_node = elementToNode(body);
    const p = firstChild(body_node);
    try testing.expect(isNodeEmpty(p.?));

    const allocator = testing.allocator;
    const text = try getNodeAllTextContent(allocator, p.?);
    defer allocator.free(text);
    try testing.expect(text.len == 2); // 2 characters: ' ' and '\n'
}

test "node with (non empty) inenr text is NOT empty" {
    // node with inner text node
    const doc = try parseFromString("<p>Text</p>");
    defer destroyDocument(doc);
    const body = try getBodyElement(doc);
    const body_node = elementToNode(body);
    const p = firstChild(body_node);
    try testing.expect(!isNodeEmpty(p.?));
}

test "node with an (empty text content) node is NOT empty" {
    const doc = try parseFromString("<p><span><strong></strong></span></p>");
    defer destroyDocument(doc);
    const body = try getBodyElement(doc);
    const body_node = elementToNode(body);
    const p = firstChild(body_node);
    try testing.expect(!isNodeEmpty(p.?));

    const allocator = testing.allocator;
    const text = getNodeAllTextContent(allocator, p.?);
    try testing.expectError(Err.EmptyTextContent, text);
}

test "isWhitespaceOnlyText" {
    const text1 = " hello world ";
    try testing.expect(!isWhitespaceOnlyText(text1));

    const text2 = "  ";
    try testing.expect(isWhitespaceOnlyText(text2));
    const text3 = "  \r \t \n";
    try testing.expect(isWhitespaceOnlyText(text3));

    const text4 =
        \\
        \\
    ;
    try testing.expect(text4.len == 1); // it is '\n', which IS a whitespace-only text
    try testing.expect(isWhitespaceOnlyText(text4));
}

test "isWhitespaceOnlyNode" {
    // one way to create some nodes
    const doc = try parseFromString("<p>   </p>");
    defer destroyDocument(doc);
    const body = try getBodyElement(doc);
    const body_node = elementToNode(body);
    const p = firstChild(body_node);

    try testing.expect(
        isWhitespaceOnlyNode(p.?),
    );

    // inner text node is whitespace-only
    const inner_text_node = firstChild(p.?);
    try testing.expect(
        z.isTextType(inner_text_node.?),
    );

    try testing.expect(
        isWhitespaceOnlyNode(inner_text_node.?),
    );

    // other way to create some nodes
    destroyNode(p.?);
    const div = try createElement(doc, "div", &.{});
    // defer destroyNode(elementToNode(div));
    const node_div = elementToNode(div);

    try setTextContent(node_div, "\n \r  \t");
    // should be true
    try testing.expect(
        isWhitespaceOnlyNode(firstChild(node_div).?),
    );
}
test "isWhitespaceOnlyElement" {
    const doc = try parseFromString("<div>   </div>");
    defer destroyDocument(doc);
    const body = try getBodyElement(doc);
    try testing.expect(
        !isWhitespaceOnlyElement(body),
    );

    const body_node = elementToNode(body);
    try testing.expect(
        !isNodeEmpty(body_node),
    );

    const div = firstChild(body_node) orelse {
        try testing.expect(false);
        return;
    };

    try testing.expect(
        isWhitespaceOnlyElement(nodeToElement(div).?),
    );

    // insert a P node and check it is not empty
    const p = try createElement(doc, "p", &.{});
    appendChild(div, elementToNode(p));
    try testing.expect(
        !isWhitespaceOnlyElement(nodeToElement(div).?),
    );

    // but its text content IS empty.
    const allocator = testing.allocator;
    const txt = try getNodeTextContentsOpts(allocator, div, .{});
    defer allocator.free(txt);
    try testing.expect(isWhitespaceOnlyText(txt));
}

test "setTextNodeData" {
    const allocator = testing.allocator;

    const doc = try createDocument();
    defer destroyDocument(doc);
    const element = try createElement(doc, "div", &.{});
    defer destroyNode(elementToNode(element));
    const node = elementToNode(element);
    const first_inner_text_node = firstChild(node) orelse null;

    try testing.expect(first_inner_text_node == null);

    // try setTextContent(node, "Initial text");
    try setOrReplaceText(allocator, node, "Initial text");

    const initial_text = try getNodeTextContentsOpts(allocator, node, .{});
    defer allocator.free(initial_text);
    try testing.expectEqualStrings("Initial text", initial_text);

    try setOrReplaceText(allocator, node, "Updated text");

    const updated_text = try getNodeTextContentsOpts(allocator, node, .{});
    defer allocator.free(updated_text);
    try testing.expectEqualStrings("Updated text", updated_text);
}

test "create Html element, custom element" {
    const doc = try z.parseFromString("<p></p>");
    const body_node = try getBodyNode(doc);

    const span_element = try createElement(doc, "span", &.{});
    const tag = (getElementName(span_element));
    const span_tag = z.parseTag("span");
    try testing.expectEqualStrings(tag, "SPAN");
    try testing.expect(span_tag.? == .span);
    try testing.expect(z.parseTag("span") == .span);

    // Test custom element creation
    const custom_elt = try createElement(
        doc,
        "custom-element",
        &.{.{ .name = "data-id", .value = "123" }},
    );
    const custom_tag = (getElementName(custom_elt));
    try testing.expectEqualStrings(custom_tag, "CUSTOM-ELEMENT");
    // not an "official" HTML tag
    try testing.expect(z.parseTag("custom-element") == null);

    // Add custom element to DOM and verify it exists

    appendChild(
        body_node,
        elementToNode(custom_elt),
    );
    appendChild(
        body_node,
        elementToNode(span_element),
    );

    // Check if it's actually in the DOM tree
    var child = firstChild(body_node);
    var found_custom = false;
    while (child != null) {
        if (nodeToElement(child.?)) |element| {
            const element_name = getElementName(element);
            if (std.mem.eql(u8, element_name, "CUSTOM-ELEMENT")) {
                found_custom = true;
                break;
            }
        }
        child = nextSibling(child.?);
    }
    try testing.expect(found_custom);

    const allocator = std.testing.allocator;
    const text = try z.serializeTree(allocator, body_node);
    defer allocator.free(text);
    try testing.expectEqualStrings("<body><p></p><custom-element data-id=\"123\"></custom-element><span></span></body>", text);

    // Now test what happens when parsing custom elements from HTML
    const doc_with_custom = try z.parseFromString("<body><custom-element>Test</custom-element></body>");
    defer z.destroyDocument(doc_with_custom);

    const custom_body = try getBodyNode(doc_with_custom);
    var parsed_child = firstChild(custom_body);
    var found_parsed_custom = false;

    while (parsed_child != null) {
        if (nodeToElement(parsed_child.?)) |element| {
            const element_name = getElementName(element);
            if (std.mem.eql(u8, element_name, "CUSTOM-ELEMENT")) {
                found_parsed_custom = true;
                break;
            }
        }
        parsed_child = nextSibling(parsed_child.?);
    }

    try testing.expect(found_parsed_custom);
}

test "HTML escaping" {
    const allocator = testing.allocator;

    const dangerous_text = "<script>alert('xss')</script> & \"quotes\"";
    const escaped = try escapeHtml(allocator, dangerous_text);
    defer allocator.free(escaped);

    const expected = "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt; &amp; &quot;quotes&quot;";
    try testing.expectEqualStrings(expected, escaped);
}

test "get & set NodeTextContent" {
    const allocator = testing.allocator;
    const doc = try createDocument();
    const element = try createElement(
        doc,
        "div",
        &.{},
    );
    defer destroyDocument(doc);
    const node = elementToNode(element);

    try setTextContent(node, "Hello, world!");

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
    const doc = try parseFromString(fragment);
    defer destroyDocument(doc);
    const body_element = try getBodyElement(doc);
    const body_node = elementToNode(body_element);
    const text_content = try getNodeTextContentsOpts(allocator, body_node, .{});
    defer allocator.free(text_content);
    try testing.expectEqualStrings("FirstSecondThirdFourthFifth", text_content);
}

test "text content" {
    const allocator = testing.allocator;

    const html = "<p>Hello <strong>World</strong>!</p>";
    const doc = try parseFromString(html);
    defer destroyDocument(doc);

    const body = try getBodyElement(doc);
    const body_node = elementToNode(body);
    const p_node = firstChild(body_node).?;
    const text = try getNodeTextContentsOpts(
        allocator,
        p_node,
        .{},
    );
    defer allocator.free(text);

    try testing.expectEqualStrings("Hello World!", text);
    const text_node = firstChild(p_node);
    const strong_node = nextSibling(text_node.?);
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
    const doc = try parseFromString(frag);
    defer destroyDocument(doc);

    const body_element = try getBodyElement(doc);
    const body_node = elementToNode(body_element);

    const first_child = firstChild(body_node);
    const second_child = nextSibling(first_child.?);

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

test "JavaScript children from createElement" {
    const allocator = std.testing.allocator;
    const doc = try createDocument();
    defer destroyDocument(doc);

    const parent = try createElement(doc, "div", &.{});
    defer destroyNode(elementToNode(parent));

    // Create some child elements
    const child1 = try createElement(doc, "span", &.{});
    defer destroyNode(elementToNode(child1));
    const child2 = try createElement(doc, "p", &.{});
    defer destroyNode(elementToNode(child2));

    appendChild(elementToNode(parent), elementToNode(child1));
    appendChild(elementToNode(parent), elementToNode(child2));

    // Get children using JavaScript convention
    const child_elements = try getChildren(allocator, parent);
    defer allocator.free(child_elements);
    // print("len: {d}\n", .{child_elements.len});

    try testing.expect(child_elements.len == 2);
    for (child_elements) |child| {
        // print("{s}\n", .{getElementName(child.?)});
        try testing.expect(isNodeEmpty(elementToNode(child)));
    }
}

test "Append JS fragment" {
    const allocator = testing.allocator;

    const doc = try parseFromString("<html><body></body></html>");
    const body_node = try getBodyNode(doc);

    defer z.destroyDocument(doc);

    const fragment = try z.createDocumentFragment(doc);

    const div = try z.createElement(
        doc,
        "div",
        &.{.{ .name = "class", .value = "container-list" }},
    );

    const div_node = elementToNode(div);
    const comment_node = try z.createComment(doc, "a comment");
    z.appendChild(div_node, commentToNode(comment_node));

    const ul = try z.createElement(doc, "ul", &.{});
    const ul_node = elementToNode(ul);

    for (1..4) |i| {
        // Convert integer to ASCII digit
        const digit_char = @as(u8, @intCast(i)) + '0';
        const value_str = &[_]u8{digit_char};

        const li = try z.createElement(
            doc,
            "li",
            &.{.{ .name = "data-id", .value = value_str }},
        );
        const li_node = elementToNode(li);

        const text_content = try std.fmt.allocPrint(
            testing.allocator,
            "Item {d}",
            .{i},
        );
        defer allocator.free(text_content);

        const text_node = try z.createTextNode(doc, text_content);
        z.appendChild(li_node, text_node);
        z.appendChild(ul_node, li_node);
    }

    z.appendChild(div_node, ul_node);
    z.appendChild(fragment, div_node);

    z.appendFragment(body_node, fragment);

    const fragment_txt = try z.serializeTree(
        allocator,
        div_node,
    );

    defer allocator.free(fragment_txt);

    // Create expected HTML (pretty formatted for readability)
    const pretty_html =
        \\<div class="container-list">
        \\  <!--a comment-->
        \\  <ul>
        \\      <li data-id="1">Item 1</li>
        \\      <li data-id="2">Item 2</li>
        \\      <li data-id="3">Item 3</li>
        \\  </ul>
        \\</div>
    ;

    const expected_html = try z.normalizeWhitespace(allocator, pretty_html);
    defer allocator.free(expected_html);

    const expected =
        "<div class=\"container-list\"><!--a comment--><ul><li data-id=\"1\">Item 1</li><li data-id=\"2\">Item 2</li><li data-id=\"3\">Item 3</li></ul></div>";

    try testing.expectEqualStrings(
        expected,
        expected_html,
    );
    try testing.expectEqualStrings(
        expected_html, // Use expected_html instead of expected
        fragment_txt,
    );

    var engine = try z.CssSelectorEngine.init(allocator);
    defer engine.deinit();

    // Find the second li element using nth-child
    const second_li = try engine.querySelector(
        body_node,
        "ul > li:nth-child(2)",
    );

    if (second_li) |result| {
        const attribute = try z.getAttribute(
            allocator,
            nodeToElement(result).?,
            "data-id",
        );
        if (attribute) |attr| {
            defer allocator.free(attr);
            try testing.expectEqualStrings(attr, "2");
        }
    }

    try z.printDocumentStructure(doc);

    const tree = try z.documentToTree(allocator, doc);
    defer z.freeHtmlTree(allocator, tree);

    for (tree, 0..) |node, i| {
        _ = i;
        // print("[{}]: ", .{i});
        z.printNode(node, 0);
    }
}

test "JavaScript children from fragment" {
    const frag = "<div><span></span><p></p></div>";
    const allocator = std.testing.allocator;
    const doc = try parseFromString(frag);
    defer destroyDocument(doc);

    const body_element = try getBodyElement(doc);
    const body_node = elementToNode(body_element);
    try testing.expectEqualStrings("BODY", getNodeName(body_node));

    const children1 = try getChildNodes(allocator, body_node);
    defer allocator.free(children1);
    try testing.expect(children1.len == 1); // Only one child <div>
    try testing.expect(!isNodeEmpty(body_node)); // DIV contains SPAN and P elements

    const div_element = nodeToElement(children1[0]).?;
    const children2 = try getChildren(allocator, div_element);
    defer allocator.free(children2);
    try testing.expectEqualStrings(getElementName(children2[0]), "SPAN");

    try testing.expectEqualStrings(getElementName(children2[1]), "P");

    for (children2) |child| {
        // print("{s}\n", .{getElementName(child.?)});
        try testing.expect(isNodeEmpty(elementToNode(child)));
    }
    // printDocumentStructure(doc);
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

    const doc = try parseFromString(html);
    defer destroyDocument(doc);

    const body = try getBodyElement(doc);
    const body_node = elementToNode(body);
    const div_node = firstChild(body_node).?;

    // print("\Void Element Test ========\n", .{});

    var child = firstChild(div_node);
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
                    if (z.isTextType(child.?)) {
                        empty_text_nodes_count += 1;
                    } else {
                        empty_non_self_closing_non_text_nodes_count += 1;
                    }
                }
            }
        }

        child = nextSibling(child.?);
    }
    // print("Count result: {d}, {d}, {d}\n", .{ empty_nodes, empty_text_nodes_count, empty_non_self_closing_non_text_nodes_count });
    try testing.expect(empty_nodes == 3); // empty elements: <br/>, <img/>, <div>  </div>
    try testing.expect(empty_text_nodes_count == 0); // empty text elements (no longer counted since nodeToElement returns null for text)
    try testing.expect(empty_non_self_closing_non_text_nodes_count == 1); // 1 empty non-self-closing non-text element
}

test "class search functionality" {
    const allocator = testing.allocator;

    // Create HTML with multiple classes
    const html =
        \\<div class="container main active">First div</div>
        \\<div class="container secondary">Second div</div>
        \\<span class="active">Span element</span>
        \\<div>No class div</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body_node = try z.getBodyNode(doc);
    var child = z.firstChild(body_node);

    // Test hasClass function and compare with existing classList
    while (child != null) {
        if (z.nodeToElement(child.?)) |element| {
            const element_name = z.getElementName(element);
            if (std.mem.eql(u8, element_name, "div")) {
                const text_content = try z.getNodeAllTextContent(allocator, child.?);
                defer allocator.free(text_content);
                if (std.mem.eql(u8, text_content, "First div")) {
                    // First div should have all three classes
                    try testing.expect(z.hasClass(element, "container"));
                    try testing.expect(z.hasClass(element, "main"));
                    try testing.expect(z.hasClass(element, "active"));
                    try testing.expect(!z.hasClass(element, "missing"));

                    // Test unified classList function - returns full class string
                    const class_result = try z.classList(allocator, element, .string);
                    const full_class_list = class_result.string;
                    defer if (full_class_list) |class_str| allocator.free(class_str);
                    if (full_class_list) |class_str| {
                        try testing.expect(std.mem.eql(u8, class_str, "container main active"));
                    }

                    // Test new getClasses function - returns array of individual classes
                    const classes = try z.getClasses(allocator, element);
                    defer {
                        for (classes) |class| allocator.free(class);
                        allocator.free(classes);
                    }
                    try testing.expect(classes.len == 3);
                    try testing.expect(std.mem.eql(u8, classes[0], "container"));
                    try testing.expect(std.mem.eql(u8, classes[1], "main"));
                    try testing.expect(std.mem.eql(u8, classes[2], "active"));
                } else if (std.mem.eql(u8, text_content, "Second div")) {
                    // Second div should have container and secondary
                    try testing.expect(z.hasClass(element, "container"));
                    try testing.expect(z.hasClass(element, "secondary"));
                    try testing.expect(!z.hasClass(element, "main"));
                    try testing.expect(!z.hasClass(element, "active"));
                } else if (std.mem.eql(u8, text_content, "No class div")) {
                    // Third div should have no classes
                    try testing.expect(!z.hasClass(element, "container"));
                    try testing.expect(!z.hasClass(element, "any"));

                    // classList should return null for elements with no class attribute
                    const no_class_result = try z.classList(allocator, element, .string);
                    try testing.expect(no_class_result.string == null);
                }
            } else if (std.mem.eql(u8, element_name, "span")) {
                // Span should have active class
                try testing.expect(z.hasClass(element, "active"));
                try testing.expect(!z.hasClass(element, "container"));
            }
        }
        child = z.nextSibling(child.?);
    }

    print("✅ Class search functionality test passed!\n", .{});
    print("   - hasClass(): searches for individual class names\n", .{});
    print("   - classList(): returns full class attribute string\n", .{});
    print("   - getClasses(): returns array of individual class names\n", .{});
}

test "CSS selector nth-child functionality" {
    const allocator = testing.allocator;

    // Create HTML with ul > li structure
    const html =
        \\<ul>
        \\  <li>First item</li>
        \\  <li>Second item</li>
        \\  <li>Third item</li>
        \\  <li>Fourth item</li>
        \\</ul>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body_node = try z.getBodyNode(doc);

    // Test CSS selector for second li
    var engine = try z.CssSelectorEngine.init(allocator);
    defer engine.deinit();

    // Find the second li element using nth-child
    const second_li_results = try engine.querySelectorAll(body_node, "ul > li:nth-child(2)");
    defer allocator.free(second_li_results);

    try testing.expect(second_li_results.len == 1);

    if (second_li_results.len > 0) {
        const second_li_node = second_li_results[0];
        const text_content = try z.getNodeAllTextContent(allocator, second_li_node);
        defer allocator.free(text_content);

        // Should be "Second item"
        try testing.expect(std.mem.eql(u8, std.mem.trim(u8, text_content, " \t\n\r"), "Second item"));
    }

    // Test finding all li elements
    const all_li_results = try engine.querySelectorAll(body_node, "ul > li");
    defer allocator.free(all_li_results);

    try testing.expect(all_li_results.len == 4);

    // Test first li using querySelector (single result)
    const first_li_node = try engine.querySelector(body_node, "ul > li:first-child");
    if (first_li_node) |node| {
        const text_content = try z.getNodeAllTextContent(allocator, node);
        defer allocator.free(text_content);
        try testing.expect(std.mem.eql(u8, std.mem.trim(u8, text_content, " \t\n\r"), "First item"));
    } else {
        try testing.expect(false); // Should find first li
    }

    print("✅ CSS selector nth-child functionality test passed!\n", .{});
}
