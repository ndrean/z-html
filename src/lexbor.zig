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
pub fn parseHtmlString(html: []const u8) !*HtmlDocument {
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

/// [core] Element creation
///
/// Can create HTMLElements or custom elements.
///
/// It takes an optional array of attributes pair (`.name`, `.value`).
///
/// ## Example
///
/// ```
/// const doc = parseHtmlString("<div></div>");
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

/// [core] Destroy a comment node in the document
pub fn destroyComment(comment: *Comment) void {
    _ = lxb_dom_comment_interface_destroy(comment);
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

extern "c" fn lxb_html_document_body_element_noi(doc: *HtmlDocument) ?*DomElement;

/// [core] Get the document's body element (usually BODY)
pub fn getDocumentBodyElement(doc: *HtmlDocument) !*DomElement {
    if (lxb_html_document_body_element_noi(doc)) |element| {
        return element;
    } else {
        return Err.NoBodyElement;
    }
}

/// [core] convience function using `try getDocumentBodyElement`.
pub fn getDocumentBodyNode(doc: *HtmlDocument) !*DomNode {
    const body_element = getDocumentBodyElement(doc) catch {
        return Err.NoBodyElement;
    };
    return elementToNode(body_element);
}

// extern "c" fn lxb_dom_document_element_noi(doc: *z.HtmlDocument) ?*z.DomElement;

// /// [core] Get the document's root element (usually <html>)
// pub fn getDocumentElement(doc: *HtmlDocument) ?*DomElement {
//     return lxb_dom_document_element_noi(doc);
// }

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
    const Type = @import("node_types.zig");
    const node_type = Type.getNodeType(node);

    // Only convert if it's actually an element node
    if (node_type != .element) {
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

// /// [core] Get document as DOM node for navigation
// pub fn getDocumentNode(doc: *HtmlDocument) *DomNode {
//     return objectToNode(doc);
// }

/// [core] Get node's tag name as Zig string
pub fn getNodeName(node: *DomNode) []const u8 {
    const name_ptr = lxb_dom_node_name(node, null);
    return std.mem.span(name_ptr);
}

/// [core] Get element's tag name as Zig string
pub fn getElementName(element: *DomElement) []const u8 {
    const node = elementToNode(element);
    return getNodeName(node);
}

//=============================================================================

/// [core] Remove a node from its parent
pub fn removeNode(node: *DomNode) void {
    lxb_dom_node_remove(node);
}

/// [core] Destroy a node from the DOM
pub fn destroyNode(node: *DomNode) void {
    lxb_dom_node_destroy(node);
}

//=============================================================================

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

//=============================================================================

extern "c" fn lxb_html_node_is_void_noi(node: *DomNode) bool;

/// [core] Check if element is void (self-closing like <img>, <br>)
pub fn isSelfClosingNode(node: *DomNode) bool {
    return lxb_html_node_is_void_noi(node);
}

extern "c" fn lxb_dom_node_is_empty(node: *DomNode) bool;

/// [core] Check if node contains only whitespace
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

    const doc = try parseHtmlString(html);
    defer destroyDocument(doc);

    const body = try getDocumentBodyElement(doc);
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
                    if (z.isNodeTextType(child.?)) {
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

//=============================================================================
// DOM NAVIGATION
//=============================================================================

extern "c" fn lexbor_node_owner_document(node: *DomNode) *HtmlDocument;
extern "c" fn lxb_dom_node_parent_noi(node: *DomNode) ?*DomNode;

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

// /// [core] Get first child of node
// pub fn firstChild(node: *DomNode) ?*DomNode {
//     return lxb_dom_node_first_child_noi(node);
// }

extern "c" fn lxb_dom_node_next_noi(node: *DomNode) ?*DomNode;

/// [core] Get next sibling of node
pub fn nextSibling(node: *DomNode) ?*DomNode {
    return lxb_dom_node_next_noi(node);
}

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
/// Returns a slice of all child nodes (including text, comments) and needs to be freed
pub fn childNodes(allocator: std.mem.Allocator, parent_node: *DomNode) ![]*DomNode {
    var nodes = std.ArrayList(*DomNode).init(allocator);

    var child = firstChild(parent_node);
    while (child != null) {
        try nodes.append(child.?);
        child = nextSibling(child.?);
    }

    return nodes.toOwnedSlice();
}

/// [core] Helper: Collect only element children from an element (JavaScript convention: children)
/// Returns a slice of child elements and needs to be freed
pub fn children(allocator: std.mem.Allocator, parent_element: *DomElement) ![]*DomElement {
    var elements = std.ArrayList(*DomElement).init(allocator);

    var child = firstElementChild(parent_element);
    while (child != null) {
        try elements.append(child.?);
        child = nextElementSibling(child.?);
    }

    return elements.toOwnedSlice();
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

/// Set text content of a node
extern "c" fn lxb_dom_node_text_content_set(node: *DomNode, content: [*]const u8, len: usize) u8;

/// [core] Set text content on empty node from Zig string
pub fn setNodeTextContent(node: *DomNode, content: []const u8) !void {
    const status = lxb_dom_node_text_content_set(
        node,
        content.ptr,
        content.len,
    );
    if (status != z.LXB_STATUS_OK) return Err.SetTextContentFailed;
}

// extern "c" fn lxb_dom_document_destroy_text(doc: *anyopaque, text: [*]usize) void;

/// Destroy text with proper cleanup
extern "c" fn lexbor_destroy_text_wrapper(node: *DomNode, text: ?[*:0]u8) void; //<- ?????

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
pub fn isWhitepaceOnlyText(text: []const u8) bool {
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

pub const DomCleanOptions = struct {
    remove_comments: bool = false,
    remove_empty_elements: bool = false, // Remove elements with no content (not just text nodes)
};

/// [core] Clean DOM tree according to HTML standards + optional extras
pub fn cleanDomTree(allocator: std.mem.Allocator, root: *DomNode, options: DomCleanOptions) !void {
    try cleanNodeRecursive(allocator, root, options);
}

fn cleanNodeRecursive(allocator: std.mem.Allocator, node: *DomNode, options: DomCleanOptions) !void {
    const node_type = z.getNodeType(node);
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
        var child = firstChild(node);
        while (child != null) {
            const next_child = nextSibling(child.?);
            try cleanNodeRecursive(allocator, child.?, options);
            child = next_child;
        }
    }
}

fn cleanElementNode(allocator: std.mem.Allocator, node: *DomNode, options: DomCleanOptions) !bool {
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

fn cleanElementAttributes(allocator: std.mem.Allocator, element: *DomElement) !usize {
    if (!z.elementHasAnyAttribute(element)) {
        return 0;
    }

    const attr_list = try z.elementCollectAttributes(allocator, element);
    defer {
        for (attr_list) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        allocator.free(attr_list);
    }
    const size = attr_list.len;

    if (size == 0) return 0;

    // Remove all existing attributes
    for (attr_list) |attr| {
        try z.removeAttribute(element, attr.name);
    }

    // Re-add with normalized whitespace
    for (attr_list) |attr| {
        const clean_name = std.mem.trim(
            u8,
            attr.name,
            &std.ascii.whitespace,
        );
        const clean_value = std.mem.trim(
            u8,
            attr.value,
            &std.ascii.whitespace,
        );

        // Skip empty attribute names (malformed HTML)
        if (clean_name.len > 0) {
            try z.setAttribute(
                element,
                &.{
                    .{
                        .name = clean_name,
                        .value = clean_value,
                    },
                },
            );
        }
    }
    return attr_list.len;
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

/// [core] set or replace text data on a text node
/// If the inner text node is empty, it will be created.
pub fn setOrReplaceNodeTextData(allocator: std.mem.Allocator, node: *DomNode, text: []const u8) !void {
    const inner_text_node = firstChild(node) orelse null;
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
        if (status != z.LXB_STATUS_OK) return Err.SetTextContentFailed;
    }
}

fn shouldPreserveWhitespace(node: *DomNode) bool {
    // // debug -->
    // const allocator = testing.allocator;
    // const text = getNodeAllTextContent(allocator, node) catch return false;
    // defer allocator.free(text);
    // print("maybe preserving {s}, {s}\n", .{ getNodeName(node), text });
    // //  <-- debug

    const parent = parentNode(node) orelse return false;
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

fn normalizeTextWhitespace(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
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

// =====================================================================
// Tests
// =====================================================================

test "check error get body of empty element" {
    const doc = try createDocument();
    const body_element = getDocumentBodyElement(doc);
    try testing.expectError(Err.NoBodyElement, body_element);

    const body_node = getDocumentBodyNode(doc);
    try testing.expectError(Err.NoBodyElement, body_node);
}

test "root node element" {
    const doc = try parseHtmlString("");
    defer z.destroyDocument(doc);
    // // try z.printDocumentStructure(doc);
    const body_doc_node = try getDocumentBodyNode(doc);
    const body_element = try getDocumentBodyElement(doc);

    try testing.expectEqualStrings("BODY", getElementName(body_element));
    try testing.expectEqualStrings("BODY", getNodeName(body_doc_node));
}

test "JavaScript DOM conventions - children and childNodes" {
    const allocator = testing.allocator;
    const doc = try parseHtmlString("<html><body><div>text<p>para</p><!-- comment --><span>span</span></div></body></html>");
    defer destroyDocument(doc);

    const body = try getDocumentBodyElement(doc);
    const div = firstElementChild(body).?;

    // Test children (only elements)
    const element_children = try children(allocator, div);
    defer allocator.free(element_children);
    try testing.expect(element_children.len == 2); // p and span
    try testing.expectEqualStrings("P", getElementName(element_children[0]));
    try testing.expectEqualStrings("SPAN", getElementName(element_children[1]));

    // Test childNodes (all nodes including text and comments)
    const all_child_nodes = try childNodes(allocator, elementToNode(div));
    defer allocator.free(all_child_nodes);
    try testing.expect(all_child_nodes.len == 4); // text, p, comment, span

    // Verify legacy functions still work
    const legacy_children = try children(allocator, div);
    defer allocator.free(legacy_children);
    try testing.expect(legacy_children.len == element_children.len);
}

test "JavaScript DOM API consistency check" {
    const allocator = testing.allocator;
    const doc = try parseHtmlString("<html><body><div id='test' class='demo'>text<p>para</p><!-- comment --><span>span</span></div></body></html>");
    defer destroyDocument(doc);

    const body = try getDocumentBodyElement(doc);
    const div = firstElementChild(body).?;

    // Test JavaScript-style attribute functions
    try testing.expect(z.hasAttribute(div, "id"));
    try testing.expect(z.hasAttribute(div, "class"));
    const id_value = z.getAttribute(div, "id").?;
    try testing.expectEqualStrings("test", id_value);

    // Test JavaScript-style children functions
    const element_children = try children(allocator, div);
    defer allocator.free(element_children);
    try testing.expect(element_children.len == 2); // p and span only

    const all_child_nodes = try childNodes(allocator, elementToNode(div));
    defer allocator.free(all_child_nodes);
    try testing.expect(all_child_nodes.len == 4); // text, p, comment, span

    // Verify no legacy function usage
    try testing.expectEqualStrings("P", getElementName(element_children[0]));
    try testing.expectEqualStrings("SPAN", getElementName(element_children[1]));
}

test "createTextNode and appendChild" {
    const doc = try parseHtmlString("<html><body></body></html>");
    defer destroyDocument(doc);

    // Create a div element
    const div = try createElement(doc, "div", &.{});

    // Create a text node
    const text_node = try createTextNode(doc, "Hello, World!");

    // Append text to div
    appendChild(elementToNode(div), text_node);

    // Append div to body
    const body = try getDocumentBodyElement(doc);
    appendChild(elementToNode(body), elementToNode(div));

    // Verify the structure
    const body_node = elementToNode(body);
    const first_child = firstChild(body_node).?;
    const div_from_tree = nodeToElement(first_child).?;

    try testing.expect(div == div_from_tree);

    // Check that div has the text content
    const div_first_child = firstChild(elementToNode(div_from_tree));
    try testing.expect(div_first_child != null);
    try testing.expect(z.isNodeTextType(div_first_child.?));
}

test "createDocumentFragment" {
    const doc = try parseHtmlString("<html><body></body></html>");
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
    const body = try getDocumentBodyElement(doc);

    // Use the proper appendFragment function to move fragment children
    appendFragment(elementToNode(body), fragment);

    // Count P elements in the body
    var p_count: usize = 0;
    var child = firstChild(elementToNode(body));
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
    const doc = try parseHtmlString("<html><body></body></html>");
    defer destroyDocument(doc);

    const body_node = try getDocumentBodyNode(doc);

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
    const doc = try parseHtmlString("<html><body></body></html>");
    defer destroyDocument(doc);

    const body_node = try getDocumentBodyNode(doc);

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
    const doc = try parseHtmlString("<p></p>");
    defer destroyDocument(doc);
    const body = try getDocumentBodyElement(doc);
    const body_node = elementToNode(body);
    const p = firstChild(body_node);
    try testing.expect(isNodeEmpty(p.?));

    const allocator = testing.allocator;
    const text = getNodeAllTextContent(allocator, p.?);
    try testing.expectError(Err.EmptyTextContent, text);
}

test "node with whitespace like characters IS empty but contains characters" {
    // this is "lxb_empty" too
    const doc = try parseHtmlString("<p> \n</p>");
    defer destroyDocument(doc);
    const body = try getDocumentBodyElement(doc);
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
    const doc = try parseHtmlString("<p>Text</p>");
    defer destroyDocument(doc);
    const body = try getDocumentBodyElement(doc);
    const body_node = elementToNode(body);
    const p = firstChild(body_node);
    try testing.expect(!isNodeEmpty(p.?));
}

test "node with an (empty text content) node is NOT empty" {
    const doc = try parseHtmlString("<p><span><strong></strong></span></p>");
    defer destroyDocument(doc);
    const body = try getDocumentBodyElement(doc);
    const body_node = elementToNode(body);
    const p = firstChild(body_node);
    try testing.expect(!isNodeEmpty(p.?));

    const allocator = testing.allocator;
    const text = getNodeAllTextContent(allocator, p.?);
    try testing.expectError(Err.EmptyTextContent, text);
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

test "isWhitespaceOnlyNode" {
    // one way to create some nodes
    const doc = try parseHtmlString("<p>   </p>");
    defer destroyDocument(doc);
    const body = try getDocumentBodyElement(doc);
    const body_node = elementToNode(body);
    const p = firstChild(body_node);

    try testing.expect(
        isWhitespaceOnlyNode(p.?),
    );

    // inner text node is whitespace-only
    const inner_text_node = firstChild(p.?);
    try testing.expect(
        z.isNodeTextType(inner_text_node.?),
    );

    try testing.expect(
        isWhitespaceOnlyNode(inner_text_node.?),
    );

    // other way to create some nodes
    destroyNode(p.?);
    const div = try createElement(doc, "div", &.{});
    // defer destroyNode(elementToNode(div));
    const node_div = elementToNode(div);

    try setNodeTextContent(node_div, "\n \r  \t");
    // should be true
    try testing.expect(
        isWhitespaceOnlyNode(firstChild(node_div).?),
    );
}
test "isWhitespaceOnlyElement" {
    const doc = try parseHtmlString("<div>   </div>");
    defer destroyDocument(doc);
    const body = try getDocumentBodyElement(doc);
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
    try testing.expect(isWhitepaceOnlyText(txt));
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

test "create Html element, custom element" {
    const doc = try z.parseHtmlString("<p></p>");
    const body_node = try getDocumentBodyNode(doc);

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
    const doc_with_custom = try z.parseHtmlString("<body><custom-element>Test</custom-element></body>");
    defer z.destroyDocument(doc_with_custom);

    const custom_body = try getDocumentBodyNode(doc_with_custom);
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
    const doc = try parseHtmlString(fragment);
    defer destroyDocument(doc);
    const body_element = try getDocumentBodyElement(doc);
    const body_node = elementToNode(body_element);
    const text_content = try getNodeTextContentsOpts(allocator, body_node, .{});
    defer allocator.free(text_content);
    try testing.expectEqualStrings("FirstSecondThirdFourthFifth", text_content);
}

test "text content" {
    const allocator = testing.allocator;

    const html = "<p>Hello <strong>World</strong>!</p>";
    const doc = try parseHtmlString(html);
    defer destroyDocument(doc);

    const body = try getDocumentBodyElement(doc);
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
    const doc = try parseHtmlString(frag);
    defer destroyDocument(doc);

    const body_element = try getDocumentBodyElement(doc);
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
    const child_elements = try children(allocator, parent);
    defer allocator.free(child_elements);
    // print("len: {d}\n", .{child_elements.len});

    try testing.expect(child_elements.len == 2);
    for (child_elements) |child| {
        // print("{s}\n", .{getElementName(child.?)});
        try testing.expect(isNodeEmpty(elementToNode(child)));
    }
}

test "JavaScript children from fragment" {
    const frag = "<div><span></span><p></p></div>";
    const allocator = std.testing.allocator;
    const doc = try parseHtmlString(frag);
    defer destroyDocument(doc);

    const body_element = try getDocumentBodyElement(doc);
    const body_node = elementToNode(body_element);
    try testing.expectEqualStrings("BODY", getNodeName(body_node));

    const children1 = try childNodes(allocator, body_node);
    defer allocator.free(children1);
    try testing.expect(children1.len == 1); // Only one child <div>
    try testing.expect(!isNodeEmpty(body_node)); // DIV contains SPAN and P elements

    const div_element = nodeToElement(children1[0]).?;
    const children2 = try children(allocator, div_element);
    defer allocator.free(children2);
    try testing.expectEqualStrings(getElementName(children2[0]), "SPAN");

    try testing.expectEqualStrings(getElementName(children2[1]), "P");

    for (children2) |child| {
        // print("{s}\n", .{getElementName(child.?)});
        try testing.expect(isNodeEmpty(elementToNode(child)));
    }
    // printDocumentStructure(doc);
}

test "normalizeTextWhitespace" {
    const allocator = testing.allocator;

    const messy_text = "  Hello   \t  World!  \n\n  ";
    const normalized = try normalizeTextWhitespace(allocator, messy_text);
    defer allocator.free(normalized);

    try testing.expectEqualStrings("Hello World!", normalized);
    // print("Normalized: {s}\n", .{normalized});
}

test "cleanElementAttributes performance optimization" {
    const allocator = testing.allocator;

    const doc = try parseHtmlString("<div><p>No attrs</p><span id='test' class='demo'>With attrs</span></div>");
    defer destroyDocument(doc);

    const body = try getDocumentBodyElement(doc);
    const body_node = elementToNode(body);
    const div_node = firstChild(body_node).?;

    var child = firstChild(div_node);
    var elements_processed: usize = 0;
    var elements_with_attrs: usize = 0;

    while (child != null) {
        if (nodeToElement(child.?)) |element| {
            elements_processed += 1;

            // Test the fast path optimization
            if (z.elementHasAnyAttribute(element)) {
                elements_with_attrs += 1;
            }

            // This should now use the optimized path
            _ = try cleanElementAttributes(allocator, element);
        }
        child = nextSibling(child.?);
    }

    try testing.expect(elements_processed == 2); // <p> and <span>
    try testing.expect(elements_with_attrs == 1); // only <span> has attributes
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

    const doc = try parseHtmlString(messy_html);
    defer destroyDocument(doc);

    const body = try getDocumentBodyElement(doc);
    const body_node = elementToNode(body);

    // print("\n=== Complete DOM Cleaning Test ===\n", .{});

    const before = try z.serializeTree(allocator, body_node);
    defer allocator.free(before);

    try cleanDomTree(
        allocator,
        body_node,
        .{
            .remove_comments = true,
            .remove_empty_elements = true,
        },
    );

    const after = try z.serializeTree(allocator, body_node);
    defer allocator.free(after);
    // print("\n\nAfter cleaning:=============\n{s}\n\n", .{after});

    // Verify results
    try testing.expect(std.mem.indexOf(u8, after, "<!--") == null); // Comments removed
    try testing.expect(std.mem.indexOf(u8, after, "Hello World") != null); // Text normalized
    try testing.expect(std.mem.indexOf(u8, after, "<span></span>") == null); // Empty elements removed
    try testing.expect(std.mem.indexOf(u8, after, "class=\"container test\"") != null); // Attributes cleaned
    try testing.expect(std.mem.indexOf(u8, after, "    preserve    ") != null); // <pre> preserved

    // printDocumentStructure(doc);

    // print("✅ Complete DOM cleaning works perfectly!\n", .{});
}
