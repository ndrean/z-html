//! Core functions: Doc creation, parsing, and DOM manipulation
const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;
const time = std.time;
const Instant = time.Instant;
const Timer = time.Timer;
const writer = std.io.getStdOut().writer();

// pub const LXB_DOM_NODE_TYPE_ELEMENT: u32 = 1;
// pub const LXB_DOM_NODE_TYPE_TEXT: u32 = 3;
// pub const LXB_DOM_NODE_TYPE_COMMENT: u32 = 8;

pub const LXB_TAG_TEMPLATE: u32 = 0x31; // From lexbor source

pub const LXB_TAG_STYLE: u32 = 0x2d;
pub const LXB_TAG_SCRIPT: u32 = 0x29;

// =============================================================
extern "c" fn lxb_html_document_create() ?*z.HTMLDocument;
extern "c" fn lxb_html_document_destroy(doc: *z.HTMLDocument) void;

extern "c" fn lxb_html_document_create_element_noi(doc: *z.HTMLDocument, tag_name: [*]const u8, tag_len: usize, reserved_for_opt: ?*anyopaque) ?*z.HTMLElement;

extern "c" fn lxb_dom_document_create_text_node(doc: *z.HTMLDocument, text: [*]const u8, text_len: usize) ?*z.DomNode;

extern "c" fn lxb_dom_node_insert_before_wo_events(to: *z.DomNode, node: *z.DomNode) void;
extern "c" fn lxb_dom_node_insert_after_wo_events(to: *z.DomNode, node: *z.DomNode) void;
extern "c" fn lxb_dom_document_create_comment(doc: *z.HTMLDocument, data: [*]const u8, len: usize) ?*z.Comment;
extern "c" fn lxb_dom_comment_interface_destroy(doc: *z.Comment) *z.Comment;
extern "c" fn lxb_dom_node_insert_child(parent: *z.DomNode, child: *z.DomNode) void;
extern "c" fn lxb_html_document_body_element_noi(doc: *z.HTMLDocument) ?*z.HTMLElement;
extern "c" fn lxb_dom_document_root(doc: *z.HTMLDocument) ?*z.DomNode;
extern "c" fn lexbor_node_owner_document(node: *z.DomNode) *z.HTMLDocument;
extern "c" fn lxb_dom_node_parent_noi(node: *z.DomNode) ?*z.DomNode;
// extern "c" fn lxb_dom_document_create_element(doc: *z.HTMLDocument, local_name: [*]const u8, lname_len: usize, reserved_for_opt: ?*anyopaque) ?*z.HTMLElement;

extern "c" fn lxb_dom_document_destroy_element(element: *z.HTMLElement) *z.HTMLElement;
extern "c" fn lexbor_dom_interface_node_wrapper(obj: *anyopaque) *z.DomNode;
extern "c" fn lexbor_dom_interface_element_wrapper(node: *z.DomNode) ?*z.HTMLElement;
// extern "c" fn lxb_html_template_to_element(template: *z.Template) *z.HTMLElement;
extern "c" fn lxb_dom_node_name(node: *z.DomNode, len: ?*usize) [*:0]const u8;
extern "c" fn lxb_dom_element_tag_name(element: *z.HTMLElement, len: ?*usize) [*:0]const u8;
extern "c" fn lxb_dom_element_qualified_name(element: *z.HTMLElement, len: *usize) [*:0]const u8;
extern "c" fn lxb_dom_node_remove_wo_events(node: *z.DomNode) void;
extern "c" fn lxb_dom_node_destroy(node: *z.DomNode) void;
extern "c" fn lxb_dom_document_destroy_text_noi(node: *z.DomNode, text: []const u8) void;

extern "c" fn lexbor_clone_node_deep(node: *z.DomNode, target_doc: *z.HTMLDocument) ?*z.DomNode;
extern "c" fn lxb_dom_document_import_node(doc: *z.HTMLDocument, node: *z.DomNode, deep: bool) *z.DomNode;

extern "c" fn lxb_html_node_is_void_noi(node: *z.DomNode) bool;
extern "c" fn lxb_dom_node_is_empty(node: *z.DomNode) bool;

extern "c" fn lxb_dom_node_first_child_noi(node: *z.DomNode) ?*z.DomNode;
extern "c" fn lxb_dom_node_next_noi(node: *z.DomNode) ?*z.DomNode;
extern "c" fn lxb_dom_node_last_child_noi(node: *z.DomNode) ?*z.DomNode;

//===========================================================================
// CORE DOCUMENT FUNCTIONS
//===========================================================================

/// [core] Creates and returns a new HTML document.
///
/// Caller must free with `destroyDocument`.
///
/// To create a useable document, simply use instead `z.parseFromString("")`
/// ## Example
/// ```
/// const doc = try createDocument();
/// defer destroyDocument(doc);
/// ```
pub fn createDocument() !*z.HTMLDocument {
    return lxb_html_document_create() orelse Err.DocCreateFailed;
}

/// [core] Destroy an HTML document.
pub fn destroyDocument(doc: *z.HTMLDocument) void {
    lxb_html_document_destroy(doc);
}

// =============================================================================
// CREATION
// =============================================================================

/// [core] Element creation with a lowercased HTML tag name
///
/// ## Example
/// ```
/// const element = try createElement(doc, "div");
/// ---
/// ```
pub fn createElement(doc: *z.HTMLDocument, name: []const u8) !*z.HTMLElement {
    return z.createElementAttr(doc, name, &.{});
}

/// [core] Element creation with attributes options
///
/// Can create HTMLElements or custom elements.
///
/// It takes an optional slice of attributes pair struct `{name, value}`.
/// ## Example
///
/// ```
/// const span: *z.HTMLElement = try createElementAttr(doc, "span", &.{});
/// const button: *z.HTMLElement = try createElementAttr(doc, "button",
///     &.{
///         .{.name = "phx-click", .value = "submit"},
///         .{.name = "disabled", .value= ""}
///     });
/// ---
/// ```
pub fn createElementAttr(
    doc: *z.HTMLDocument,
    name: []const u8,
    attrs: []const z.AttributePair,
) !*z.HTMLElement {
    const element = lxb_html_document_create_element_noi(
        doc,
        name.ptr,
        name.len,
        null,
    ) orelse return Err.CreateElementFailed;

    if (attrs.len == 0) return element;

    for (attrs) |attr| {
        _ = z.setAttributes(
            element,
            &.{
                z.AttributePair{ .name = attr.name, .value = attr.value },
            },
        );
    }
    return element;
}

test "create elt" {
    const doc = try z.parseFromString("");
    defer z.destroyDocument(doc);

    const body = try z.bodyNode(doc);
    const button = try z.createElementAttr(
        doc,
        "button",
        &.{
            .{ .name = "phx-click", .value = "increment" },
            .{ .name = "hidden", .value = "" },
        },
    );
    z.appendChild(body, z.elementToNode(button));

    const allocator = testing.allocator;
    const attrs = try z.getAttributes(allocator, button);
    defer {
        for (attrs) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        allocator.free(attrs);
    }
    try testing.expectEqualStrings("hidden", attrs[1].name);
}

/// [core] Create a text node in the document
///
/// ## Example
/// ```
/// const textNode: *z.HTMLElement = try createTextNode(doc, "Hello, World!");
/// ---
/// ```
pub fn createTextNode(doc: *z.HTMLDocument, text: []const u8) !*z.DomNode {
    return lxb_dom_document_create_text_node(
        doc,
        text.ptr,
        text.len,
    ) orelse Err.CreateTextNodeFailed;
}

/// [core] Create a comment node and returns a !Comment
///
/// ## Example
/// ```
/// const commentNode: *z.Comment = try createComment(doc, "Hello");
/// ```
/// ## Signature
pub fn createComment(doc: *z.HTMLDocument, data: []const u8) !*z.Comment {
    return lxb_dom_document_create_comment(
        doc,
        data.ptr,
        data.len,
    ) orelse Err.CreateCommentFailed;
}

// ---------------------------------------------------------------------------
// Root, Owner, Body node/element access
// ---------------------------------------------------------------------------

/// [core] Returns the document root node ("HTML" or "XML")
pub fn documentRoot(doc: *z.HTMLDocument) ?*z.DomNode {
    return lxb_dom_document_root(doc);
}

/// [core] Returns the document
///
/// Useful with fragments/templates
pub fn ownerDocument(node: *z.DomNode) *z.HTMLDocument {
    return lexbor_node_owner_document(node);
}

test "documentRoot - ownerDocument" {
    const doc = try z.parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const doc_root = documentRoot(doc);
    try testing.expectEqualStrings("HTML", z.nodeName_zc(doc_root.?));

    const owner = ownerDocument(doc_root.?);
    try testing.expect(owner == doc);
}
/// [core] Get the document's body element (usually BODY)
///
/// ## Example
/// ```
/// const bodyElement: *z.HTMLElement = try bodyElement(doc);
/// ```
/// ## Signature
pub fn bodyElement(doc: *z.HTMLDocument) !*z.HTMLElement {
    if (lxb_html_document_body_element_noi(doc)) |element| {
        return element;
    } else {
        return Err.NoBodyElement;
    }
}

/// [core] Get the document's body node (usually BODY)
pub fn bodyNode(doc: *z.HTMLDocument) !*z.DomNode {
    const body_element = bodyElement(doc) catch {
        return Err.NoBodyElement;
    };
    return elementToNode(body_element);
}

test "getBodyElement/node & error returned" {
    {
        const doc = try z.parseFromString("<html><body></body></html>");
        defer z.destroyDocument(doc);

        const body_elt = try z.bodyElement(doc);
        try testing.expectEqualStrings("BODY", z.tagName_zc(body_elt));

        const body_node = try z.bodyNode(doc);
        try testing.expectEqualStrings("BODY", z.nodeName_zc(body_node));
        try testing.expect(.element == z.nodeType(body_node));
    }
    {
        const doc = try z.createDocument();
        defer z.destroyDocument(doc);
        const body_node = z.bodyNode(doc);
        try testing.expectError(Err.NoBodyElement, body_node);
        const body_elt = bodyElement(doc);
        try testing.expectError(Err.NoBodyElement, body_elt);
    }
}

// ------------------------------------------------------------------------------
// Element / Node conversions
// ------------------------------------------------------------------------------

/// [core] Internal: convert any lexbor object to DOM node
pub fn objectToNode(obj: *anyopaque) *z.DomNode {
    return lexbor_dom_interface_node_wrapper(obj);
}

/// [core] Convert DOM Element to Node
pub fn elementToNode(element: *z.HTMLElement) *z.DomNode {
    return objectToNode(element);
}

/// [core] Convert Comment to Node
pub fn commentToNode(comment: *z.Comment) *z.DomNode {
    return objectToNode(comment);
}

/// [core] Convert DOM node to Element
///
/// Returns NULL if the node is not an element
pub fn nodeToElement(node: *z.DomNode) ?*z.HTMLElement {
    // Only convert if it's actually an element node
    if (z.nodeType(node) != .element) {
        return null;
    }

    return lexbor_dom_interface_element_wrapper(node);
}

test "element/node/element" {
    const doc = try createDocument();
    const div_elt = try createElementAttr(doc, "div", &.{});
    const div_node = elementToNode(div_elt);
    const element = nodeToElement(div_node);
    try testing.expect(element == div_elt);
}

/// [core] Cast Node of type `.comment` into *z.Comment
///
/// Returns NULL if the node is not a comment
pub fn nodeToComment(node: *z.DomNode) ?*z.Comment {
    if (z.nodeType(node) != .comment) {
        return null;
    }
    const comment: *z.Comment = @ptrCast(node);
    return comment;
}

test "creation & convertions" {
    const doc = try z.parseFromString("<html><body><!-- a comment --></body></html>");
    defer destroyDocument(doc);

    const body = try bodyNode(doc);

    const first_comment_node = firstChild(body);
    const first_comment = nodeToComment(first_comment_node.?);
    try testing.expect(first_comment != null);

    const div_elt = try createElementAttr(doc, "div", &.{});
    const comment = try createComment(doc, "Hello, comment!");
    const text = try createTextNode(doc, "Hello, text!");

    const div = elementToNode(div_elt);
    appendChild(body, div);

    appendChild(body, commentToNode(comment));
    appendChild(body, text);

    // text node is not an element
    const my_err1 = nodeToElement(text);
    try testing.expect(my_err1 == null);

    // comment node is not an element
    const comment_node = commentToNode(comment);
    const my_err2 = nodeToElement(comment_node);
    try testing.expect(my_err2 == null);

    try testing.expectEqualStrings("#element", z.nodeTypeName(div));
}

// ---------------------------------------------------------------------------

/// [core] Get the tag name (UPPERCASED if element) or type of a _node_ as borrowed zero-copy
///
/// - returns the `nodeType` (#text, #comment) for non-elements nodes,
/// - returns the `tagName` in UPPERCASE for element nodes.
///
/// ⚠️ Unsafe : to be used only within the lifetime of the function call
///
/// Use the allocated `z.nodeName()` if you need to store the result.
/// ## Example
/// ```
/// test "nodeType/tagname" {
///     const doc = try createDocument();
///     const div_elt = try createElementAttr(doc, "div", &.{});
///     const div_name = z.nodeName_zc(elementToNode(div_elt));
///     try testing.expectEqualStrings(div_name, "DIV");
/// }
/// ---
/// ```
pub fn nodeName_zc(node: *z.DomNode) []const u8 {
    const name_ptr = lxb_dom_node_name(node, null);
    return std.mem.span(name_ptr);
}

/// [core] Get the tag name (UPPERCASED if element) or type of a _node_ as owned Zig string.
///
/// - returns the `nodeType` (#text, #comment) for non-elements nodes,
/// - returns the `tagName` in UPPERCASE for element nodes.
///
/// Allocated: aller must free the returned string.
/// ## Example
/// ```
/// const allocator = testing.allocator;
/// const text = try createTextNode(doc, "Hello"); // a node
/// const text_name = try nodeName(allocator, text);
/// defer allocator.free(text_name);
/// try testing.expectEqualStrings(text_name, "#text");
///
/// const div = try createElementAttr(doc, "div", &.{}); // an element
/// const name = try nodeName(allocator, elementToNode(div));
/// defer allocator.free(name);
/// try testing.expectEqualStrings(name, "DIV");
/// ---
/// ```
pub fn nodeName(allocator: std.mem.Allocator, node: *z.DomNode) ![]u8 {
    const name_slice = z.nodeName_zc(node);
    return try allocator.dupe(u8, name_slice);
}

test "nodeName/_zc" {
    const allocator = testing.allocator;
    const doc = try createDocument();

    const div_elt = try createElementAttr(doc, "div", &.{});
    const div_name = z.nodeName_zc(elementToNode(div_elt));
    try testing.expectEqualStrings(div_name, "DIV");
    const node_type = z.nodeType(elementToNode(div_elt));
    try testing.expect(node_type == .element);
    const owned_div_name = try nodeName(allocator, elementToNode(div_elt));
    defer allocator.free(owned_div_name);
    try testing.expectEqualStrings(owned_div_name, "DIV");

    const text = try createTextNode(doc, "Hello");
    const owned_text_name = try nodeName(allocator, text);
    defer allocator.free(owned_text_name);
    try testing.expectEqualStrings(owned_text_name, "#text");
    const text_name = nodeName_zc(text);
    try testing.expectEqualStrings(text_name, "#text");
}

/// [core] Get the tag name on an _element_ (UPPERCASED)  as borrowed zero-copy
///
/// Use tagName() if you need to store the result.
///
/// ⚠️ Unsafe : to be used only within the lifetime of the function call
/// ## Example
/// ```
/// const allocator = testing.allocator;
/// const doc = try createDocument();
/// const div = try createElementAttr(doc, "div", &.{});
/// const name = tagName_zc(elementToNode(div));
/// try testing.expectEqualStrings(name, "DIV");
/// ---
/// ```
pub fn tagName_zc(element: *z.HTMLElement) []const u8 {
    const name_ptr = lxb_dom_element_tag_name(element, null);
    return std.mem.span(name_ptr);
}

/// [core] Get the tag name on an _element_ (UPPERCASED)  as owned Zig string
///
/// Returns a copy of the tag name that is owned by the caller.
///
/// Allocated: Caller must free the returned string.
/// ## Example
/// ```
/// const allocator = testing.allocator;
/// const doc = try createDocument();
/// const div = try createElementAttr(doc, "div", &.{});
/// const name = try tagName(allocator, elementToNode(div));
/// defer allocator.free(name);
/// try testing.expectEqualStrings(name, "DIV");
/// ---
/// ```
pub fn tagName(allocator: std.mem.Allocator, element: *z.HTMLElement) ![]u8 {
    const name_slice = tagName_zc(element);
    return try allocator.dupe(u8, name_slice);
}

/// [core] Get the allocated qualified name (lowercased)  of an _element_ (namespace:tagname or just tagname) as owned Zig slice
///
/// This is useful for elements with namespaces like SVG or MathML.
///
/// Allocated: Caller must free the returned slice.
/// ## Example
/// ```
/// const allocator = testing.allocator;
/// const doc = try createDocument();
/// const div = try z.createElementAttr(doc, "div", &.{});
/// const name = try qualifiedName(allocator, elementToNode(div));
/// defer allocator.free(name);
/// try testing.expectEqualStrings(name, "div");
/// ---
/// ```
pub fn qualifiedName(allocator: std.mem.Allocator, element: *z.HTMLElement) ![]u8 {
    var name_len: usize = 0;
    const name_ptr = lxb_dom_element_qualified_name(element, &name_len);

    const result = try allocator.alloc(u8, name_len);
    @memcpy(result, name_ptr[0..name_len]);
    return result;
}

test "qualified name" {
    const allocator = testing.allocator;
    const doc = try createDocument();
    const div = try createElementAttr(doc, "div", &.{});
    const owned_name = try qualifiedName(allocator, div);
    defer allocator.free(owned_name);
    try testing.expectEqualStrings(owned_name, "div");
    const borrow_name = qualifiedName_zc(div);
    try testing.expectEqualStrings(borrow_name, "div");
}

/// [core] Get the qualified name (lowercased) of an _element_ (borrowed, zero-copy version)
///
/// ⚠️ Unsafe : to be used only within the lifetime of the function call
/// ## Example
/// ```zig
/// const doc = try createDocument();
/// const div_elt = try createElementAttr(doc, "div", &.{});
/// const name = qualifiedName_zc(div_elt);
/// try testing.expectEqualStrings(name, "div");
/// ---
/// ```
pub fn qualifiedName_zc(element: *z.HTMLElement) []const u8 {
    var name_len: usize = 0;
    const name_ptr = lxb_dom_element_qualified_name(element, &name_len);
    return name_ptr[0..name_len];
}

//=============================================================================

/// [core] Destroy a comment node in the document
pub fn destroyComment(comment: *z.Comment) void {
    _ = lxb_dom_comment_interface_destroy(comment);
}

/// [core] Remove a node from its parent
pub fn removeNode(node: *z.DomNode) void {
    lxb_dom_node_remove_wo_events(node);
}

/// [core] Destroy a node from the DOM
pub fn destroyNode(node: *z.DomNode) void {
    lxb_dom_node_destroy(node);
}

/// [core] Destroy an element in the document
pub fn destroyElement(element: *z.HTMLElement) void {
    _ = lxb_dom_document_destroy_element(element);
}

/// [core] Deep cross document clone
///
///  JavaScript `importNode()`
pub fn importNode(node: *z.DomNode, target_doc: *z.HTMLDocument) *z.DomNode {
    return lxb_dom_document_import_node(target_doc, node, true);
}

/// [core] Deep cross document clone
///
///  JavaScript `cloneNode()`
pub fn cloneNode(node: *z.DomNode, target_doc: *z.HTMLDocument) ?*z.DomNode {
    return lexbor_clone_node_deep(node, target_doc);
}

//=============================================================================
// DOM NAVIGATION
//=============================================================================

/// [core] Get the parent node of a given node
pub fn parentNode(node: *z.DomNode) ?*z.DomNode {
    return lxb_dom_node_parent_noi(node);
}

/// [core] Get the parent element of a given element
pub fn parentElement(element: *z.HTMLElement) ?*z.HTMLElement {
    const node = elementToNode(element);
    const parent_node = parentNode(node);
    if (parent_node) |parent| {
        return nodeToElement(parent);
    }
    return null;
}

/// [core] Get next sibling of node
///
/// Returns NULL when there is no next sibling.
pub fn nextSibling(node: *z.DomNode) ?*z.DomNode {
    return lxb_dom_node_next_noi(node);
}

/// [core] Get previous sibling of node
///
/// Returns NULL when there is no previous sibling.
pub fn previousSibling(node: *z.DomNode) ?*z.DomNode {
    const parent = z.parentNode(node) orelse return null;
    var child = z.firstChild(parent);

    var prev: ?*z.DomNode = null;

    while (child != null) {
        if (child.? == node) return prev;
        prev = child;
        child = z.nextSibling(child.?);
    }
    return null;
}

/// [core] Get first child of node
///
/// Returns NULL when there are no children.
pub fn firstChild(node: *z.DomNode) ?*z.DomNode {
    return lxb_dom_node_first_child_noi(node);
}

/// [core] Get last child of node
///
/// Returns NULL when there are no children.
pub fn lastChild(node: *z.DomNode) ?*z.DomNode {
    return lxb_dom_node_last_child_noi(node);
}

test "firstChild / lastChild" {
    {
        const doc = try z.parseFromString("<ul><li>Hello</li><li>World</li></ul>");
        defer z.destroyDocument(doc);
        const body = try bodyNode(doc);
        const ul = firstChild(body);
        const first_child = firstChild(ul.?);
        const last_child = lastChild(ul.?);

        const hello = z.textContent_zc(first_child.?);
        const world = z.textContent_zc(last_child.?);
        try testing.expectEqualStrings("Hello", hello);
        try testing.expectEqualStrings("World", world);
    }
    {
        const doc = try z.parseFromString("<p></p>");
        defer z.destroyDocument(doc);
        const body = try bodyNode(doc);
        const p = firstChild(body);
        const first = z.firstChild(p.?);
        const last = z.lastChild(p.?);
        try testing.expect(first == null);
        try testing.expect(last == null);
    }
}

/// [core] Get first element child
///
/// Takes an element and returns the first child element, or null if none exists.
///
/// Skips non-element nodes such as text nodes, comments
pub fn firstElementChild(element: *z.HTMLElement) ?*z.HTMLElement {
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

test "firstElementChild" {
    const doc = try z.parseFromString("hello <div>world <p></p></div>");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);
    const first_text = z.firstChild(body);
    try testing.expectEqualStrings(
        "#text",
        z.nodeName_zc(first_text.?),
    );

    const div = z.firstElementChild(nodeToElement(body).?);
    try testing.expectEqualStrings(
        "#element",
        z.nodeTypeName(elementToNode(div.?)),
    );
    try testing.expectEqualStrings(
        "DIV",
        z.tagName_zc(div.?),
    );
}

/// [core] Get next element sibling
///
/// Takes an element and returns the next sibling element, or null if none exists.
///
/// Skips non-element nodes such as text nodes, comments, etc.
pub fn nextElementSibling(element: *z.HTMLElement) ?*z.HTMLElement {
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

test "nextElementSibling" {
    const doc = try z.parseFromString("<div>test</div><br/><code></code>");
    defer z.destroyDocument(doc);
    const body = try z.bodyElement(doc);
    var current_elt = z.firstElementChild(body);

    // const elements = [_]struct { tag: []const u8 }{
    //     .{ .tag = "DIV" },
    //     .{ .tag = "BR" },
    //     .{ .tag = "CODE" },
    // };
    const elements: [3][]const u8 = .{ "DIV", "BR", "CODE" };

    var index: usize = 0;
    while (current_elt != null and index < elements.len) {
        if (z.tagFromQualifiedName(z.tagName_zc(current_elt.?)) == .div) {
            const first_child = z.firstChild(elementToNode(current_elt.?));
            try testing.expectEqualStrings(
                "#text",
                z.nodeTypeName(first_child.?),
            );
        }
        try testing.expectEqualStrings(
            elements[index],
            z.tagName_zc(current_elt.?),
        );
        current_elt = z.nextElementSibling(current_elt.?);
        index += 1;
    }

    try testing.expect(index == elements.len);
    try testing.expect(current_elt == null);
}

/// [core] Helper: Collect all child nodes from a node
///
/// Returns a slice of all child nodes (including text, comments)
///
/// Caller needs to free the slice
pub fn childNodes(allocator: std.mem.Allocator, parent_node: *z.DomNode) ![]*z.DomNode {
    var nodes: std.ArrayList(*z.DomNode) = .empty;

    var child = firstChild(parent_node);
    while (child != null) {
        try nodes.append(allocator, child.?);
        child = nextSibling(child.?);
    }

    return nodes.toOwnedSlice(allocator);
}

/// [core] Helper: Collect only element children from an element
///
/// Allocated: Caller needs to free the slice
/// ## Example
/// ```
/// test "children" {
///     const allocator = testing.allocator;
///     const doc = try z.parseFromString("<ul><li>First</li><li>Second</li><li>Third</li></ul>");
///     defer z.destroyDocument(doc);
///
///     const body_elt = try z.bodyElement(doc);
///     const ul_elt = z.firstElementChild(body_elt).?;
///     const result = try z.children(allocator, ul_elt);
///     defer allocator.free(result);
///
///     try testing.expect(result.len == 3);
///     try testing.expectEqualStrings(z.tagName_zc(result[0]), "LI");
/// }
/// ```
/// ## Signature
pub fn children(allocator: std.mem.Allocator, parent_element: *z.HTMLElement) ![]*z.HTMLElement {
    var elements: std.ArrayList(*z.HTMLElement) = .empty;

    var child = firstElementChild(parent_element);
    while (child != null) {
        try elements.append(allocator, child.?);
        child = nextElementSibling(child.?);
    }

    return elements.toOwnedSlice(allocator);
}

test "children" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<ul><li>First</li><li>Second</li><li>Third</li></ul>");
    defer z.destroyDocument(doc);

    const body_elt = try z.bodyElement(doc);
    const ul_elt = z.firstElementChild(body_elt).?;

    const result = try z.children(allocator, ul_elt);
    defer allocator.free(result);

    try testing.expect(result.len == 3);
    try testing.expectEqualStrings(
        z.tagName_zc(result[0]),
        "LI",
    );
}

/// [core] Append a child node to parent
///
/// ## Example
/// ```
/// const parentNode: *z.DomNode = try bodyNode(doc);
/// const childNode: *z.DomNode = try createTextNode(doc, "Hello");
/// z.appendChild(parentNode, childNode);
/// ```
///
/// ## Signature
pub fn appendChild(parent: *z.DomNode, child: *z.DomNode) void {
    lxb_dom_node_insert_child(parent, child);
}

/// [core] Append multiple child nodes to parent
///
/// ## Example
/// ```
/// const parentNode: *z.DomNode = try bodyNode(doc);
/// const child1: *z.HTMLElement = try createElementAttr(doc, "div", &.{});
/// const div = elementToNode(child1);
/// const child2: *z.HTMLElement = try createElementAttr(doc, "p", &.{});
/// const p = elementToNode(child2);
/// const childNodes: []const *z.DomNode = &.{div, p};
/// appendChildren(parentNode, childNodes);
/// ```
/// ## Signature
pub fn appendChildren(parent: *z.DomNode, child_nodes: []const *z.DomNode) void {
    for (child_nodes) |child| {
        appendChild(parent, child);
    }
}

test "appendChild/dren" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const body = try bodyNode(doc);
    const child1 = try createElementAttr(doc, "div", &.{});
    const div = elementToNode(child1);
    const child2 = try createElementAttr(doc, "p", &.{});
    const p = elementToNode(child2);
    const child_nodes: []const *z.DomNode = &.{ div, p };
    appendChildren(body, child_nodes);

    const html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html);
    try testing.expectEqualStrings(
        "<body><div></div><p></p></body>",
        html,
    );
}

/// [core] Insert a node after a reference node.
pub fn insertAfter(reference_node: *z.DomNode, new_node: *z.DomNode) void {
    lxb_dom_node_insert_after_wo_events(reference_node, new_node);
}

/// [core] Insert a node before a reference node
pub fn insertBefore(reference_node: *z.DomNode, new_node: *z.DomNode) void {
    lxb_dom_node_insert_before_wo_events(reference_node, new_node);
}

test "insertBefore / insertAfter" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<html><body><ul><li id=\"1\">First</li></ul></body></html>");
    defer destroyDocument(doc);

    const body = try bodyNode(doc);
    const first_li = z.getElementById(body, "1");
    const new_li = try z.createElementAttr(
        doc,
        "li",
        &.{.{ .name = "id", .value = "0" }},
    );
    const last_li = try z.createElementAttr(
        doc,
        "li",
        &.{.{ .name = "id", .value = "2" }},
    );
    insertBefore(
        elementToNode(first_li.?),
        elementToNode(new_li),
    );
    insertAfter(
        elementToNode(first_li.?),
        elementToNode(last_li),
    );
    const html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html);
    try testing.expectEqualStrings(
        "<body><ul><li id=\"0\"></li><li id=\"1\">First</li><li id=\"2\"></li></ul></body>",
        html,
    );
}

/// [core] Position flags for insertAdjacent operations (matches JavaScript API)
/// Values are:
/// - `beforebegin`: Insert before the element itself (as a previous sibling)
/// - `afterbegin`: Insert as the first child of the element
/// - `beforeend`: Insert as the last child of the element
/// - `afterend`: Insert after the element itself (as a next sibling)
///
/// Inline conversion string to enum
pub const InsertPosition = enum {
    beforebegin,
    afterbegin,
    beforeend,
    afterend,

    pub inline fn fromString(position: []const u8) ?InsertPosition {
        if (std.mem.eql(u8, position, "beforebegin")) return .beforebegin;
        if (std.mem.eql(u8, position, "afterbegin")) return .afterbegin;
        if (std.mem.eql(u8, position, "beforeend")) return .beforeend;
        if (std.mem.eql(u8, position, "afterend")) return .afterend;
        return null;
    }
};

test "InsertPosition.fromString" {
    try testing.expect(InsertPosition.fromString("beforebegin") == .beforebegin);
    try testing.expect(InsertPosition.fromString("afterbegin") == .afterbegin);
    try testing.expect(InsertPosition.fromString("beforeend") == .beforeend);
    try testing.expect(InsertPosition.fromString("afterend") == .afterend);
    try testing.expect(InsertPosition.fromString("invalid") == null);
}

/// [core] Insert an element at the specified position relative to the target element
///
/// The position is either an `InsertPosition` enum value (compile check) or a string representation (runtime error if unknown).
///
/// ## Example
/// ```zig
/// const target = try z.getElementById(doc, "my-element");
/// const new_div = try z.createElementAttr(doc, "div", &.{});
/// try insertAdjacentElement(target.?, .beforebegin, new_div);
/// try insertAdjacentElement(target.?, "beforeend", new_div);
/// ---
/// ```
pub fn insertAdjacentElement(
    target: *z.HTMLElement,
    position: anytype,
    element: *z.HTMLElement,
) !void {
    const T = @TypeOf(position);
    const pos_enum: InsertPosition = if (T == InsertPosition)
        position // if InsertPosition.beforebegin
    else switch (@typeInfo(T)) {
        .enum_literal => position, // if .beforebegin
        // you want to return a value for `pos_enum`. You can't use `return` otherwise the function will return. `break` requires a labelled block to break from.
        else => blk: {
            const str: []const u8 = position[0..];
            break :blk InsertPosition.fromString(str) orelse return Err.InvalidPosition;
        },
    };

    const target_node = elementToNode(target);
    const element_node = elementToNode(element);

    switch (pos_enum) {
        .beforebegin => {
            _ = parentNode(target_node) orelse return Err.NoParentNode;
            insertBefore(target_node, element_node);
        },
        .afterbegin => {
            const first_child = firstChild(target_node);
            if (first_child) |first| {
                insertBefore(first, element_node);
            } else {
                appendChild(target_node, element_node);
            }
        },
        .beforeend => {
            appendChild(target_node, element_node);
        },
        .afterend => {
            _ = parentNode(target_node) orelse return Err.NoParentNode;
            insertAfter(target_node, element_node);
        },
    }
}

test "insertAdjacentElement - all positions & invalid" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<div id=\"target\">Target Content</div>");
    defer destroyDocument(doc);

    const body = try z.bodyNode(doc);
    const target = z.getElementById(body, "target");

    // Test beforebegin - insert before the target element
    const before_element = try z.createElementAttr(
        doc,
        "p",
        &.{.{ .name = "id", .value = "before" }},
    );
    try insertAdjacentElement(
        target.?,
        .beforebegin,
        before_element,
    );

    // Test afterbegin - insert as first child
    const afterbegin_element = try z.createElementAttr(
        doc,
        "span",
        &.{.{ .name = "id", .value = "first" }},
    );
    try insertAdjacentElement(
        target.?,
        .afterbegin,
        afterbegin_element,
    );

    // Test beforeend - insert as last child
    const beforeend_element = try z.createElementAttr(
        doc,
        "span",
        &.{.{ .name = "id", .value = "last" }},
    );
    try insertAdjacentElement(
        target.?,
        .beforeend,
        beforeend_element,
    );

    // Test afterend - insert after the target element
    const after_element = try z.createElementAttr(
        doc,
        "p",
        &.{.{ .name = "id", .value = "after" }},
    );
    try insertAdjacentElement(
        target.?,
        .afterend,
        after_element,
    );

    const invalid = insertAdjacentElement(target.?, "invalid", after_element);
    try testing.expectError(Err.InvalidPosition, invalid);

    const html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html);

    const pretty_expected =
        \\<body>
        \\  <p id="before"></p>
        \\  <div id="target">
        \\      <span id="first"></span>Target Content<span id="last"></span>
        \\  </div>
        \\  <p id="after"></p>
        \\</body>
    ;

    const expected = try z.normalizeText(allocator, pretty_expected, .{});
    defer allocator.free(expected);
    try testing.expectEqualStrings(expected, html);
}

test "insertAdjacentElement - empty target & cloning" {
    const allocator = testing.allocator;

    const doc = try z.parseFromString("<div id=\"target\"><p id=\"1\"></p></div>");
    defer destroyDocument(doc);

    const body = try z.bodyNode(doc);
    const target = z.getElementById(body, "target");

    // Test afterbegin on empty element
    const child_element = try z.createElementAttr(
        doc,
        "p",
        &.{.{ .name = "class", .value = "child" }},
    );

    const positions = [_]InsertPosition{ .afterbegin, .beforeend, .beforebegin, .afterend };
    for (positions) |position| {
        const cloned_node = z.cloneNode(
            z.elementToNode(child_element),
            doc,
        );
        const clone_element = z.nodeToElement(cloned_node.?).?;
        try insertAdjacentElement(
            target.?,
            position,
            clone_element,
        );
    }
    const resulting_html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(resulting_html);

    const pretty_expectation =
        \\<body>
        \\  <p class="child"></p>
        \\  <div id="target">
        \\      <p class="child"></p>
        \\      <p id="1"></p>
        \\      <p class="child"></p>
        \\  </div>
        \\  <p class="child"></p>
        \\</body>
    ;

    const expectation = try z.normalizeText(
        allocator,
        pretty_expectation,
        .{},
    );
    defer allocator.free(expectation);

    try testing.expectEqualStrings(
        expectation,
        resulting_html,
    );
}

/// [core] Helper: Insert all children from fragment before a reference node by iterating over the child nodes of the parent node
fn insertChildNodesBefore(reference_node: *z.DomNode, parent_node: *z.DomNode) void {
    var fragment_child = firstChild(parent_node);
    while (fragment_child) |current_child| {
        const next = nextSibling(current_child);
        insertBefore(reference_node, current_child);
        fragment_child = next;
    }
}

/// [core] Helper: Insert all children from fragment after a reference by iterating over the child nodes of the parent node
fn insertChildNodesAfter(reference_node: *z.DomNode, parent_node: *z.DomNode) void {
    var fragment_child = firstChild(parent_node);
    var insert_after_node = reference_node;
    while (fragment_child) |current_child| {
        const next = nextSibling(current_child);
        insertAfter(insert_after_node, current_child);
        insert_after_node = current_child; // Next insertion point
        fragment_child = next;
    }
}

/// [core] Insert HTML string at the specified position relative to the target element
///
/// The position is either an `InsertPosition` enum value (compile check) or a string representation (runtime error if unknown).
///
/// ## Example
/// ```zig
/// const target = try z.getElementById(doc, "my-element");
/// try insertAdjacentHTML(target.?, .beforeend, "<p>New <em>content</em></p>");
/// try insertAdjacentHTML(target.?, "beforeend", "<p>New content</p>");
/// ---
/// ```
pub fn insertAdjacentHTML(
    target: *z.HTMLElement,
    position: anytype,
    html: []const u8,
) !void {
    const T = @TypeOf(position);
    const pos_enum: InsertPosition =
        switch (@typeInfo(T)) {
            .enum_literal => position,
            // this need to return, so need break, which in turn need a block
            else => blk: {
                const str: []const u8 = position[0..];
                break :blk InsertPosition.fromString(str) orelse return Err.InvalidPosition;
            },
        };

    const target_node = elementToNode(target);

    // Parse the HTML fragment once
    const fragment_root = try z.parseFragmentSimple(
        target_node,
        html,
        .body,
    );
    defer z.destroyNode(fragment_root);

    switch (pos_enum) {
        .beforebegin => {
            _ = parentNode(target_node) orelse return Err.NoParentNode;
            insertChildNodesBefore(target_node, fragment_root);
        },
        .afterbegin => {
            if (firstChild(target_node)) |first| {
                insertChildNodesBefore(first, fragment_root);
            } else {
                // Target is empty, just append all
                z.appendFragment(target_node, fragment_root);
            }
        },
        .beforeend => {
            z.appendFragment(target_node, fragment_root);
        },
        .afterend => {
            _ = parentNode(target_node) orelse return Err.NoParentNode;
            insertChildNodesAfter(target_node, fragment_root);
        },
    }
}

test "enum / string insertAdjacentHTML" {
    const allocator = testing.allocator;
    const pretty_html =
        \\<body>
        \\  <div id="target">Original</div>
        \\</body>
    ;
    const init_html = try z.normalizeText(allocator, pretty_html, .{});
    defer allocator.free(init_html);
    const doc = try z.parseFromString(init_html);
    defer destroyDocument(doc);

    const body = try z.bodyNode(doc);

    const target = z.getElementById(body, "target");

    try insertAdjacentHTML(
        target.?,
        .beforebegin,
        "<p>Before Begin</p>",
    );

    try insertAdjacentHTML(
        target.?,
        "afterbegin",
        "<span>After Begin</span>",
    );

    try insertAdjacentHTML(
        target.?,
        .beforeend,
        "<span>Before End</span>",
    );

    try insertAdjacentHTML(
        target.?,
        .afterend,
        "<p>After End</p>",
    );

    const html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html);

    // const clean_html = try z.normalizeText(allocator, html, .{});
    // defer allocator.free(clean_html);

    const expected_pretty_html =
        \\<body>
        \\  <p>Before Begin</p>
        \\  <div id="target">
        \\    <span>After Begin</span>
        \\      Original
        \\    <span>Before End</span>
        \\  </div>
        \\  <p>After End</p>
        \\</body>
    ;

    const expected_html = try z.normalizeText(allocator, expected_pretty_html, .{});
    defer allocator.free(expected_html);
    // const expected = "<body><p>Before Begin</p><div id=\"target\"><span>After Begin</span>Original<span>Before End</span></div><p>After End</p></body>";
    // try testing.expectEqualStrings(expected_html, html);

    // Test 5: Error handling for invalid position string
    const invalid_result = insertAdjacentHTML(
        target.?,
        "invalid",
        "<p>Test</p>",
    );
    try testing.expectError(Err.InvalidPosition, invalid_result);

    // Test 6: More natural usage examples
    try insertAdjacentHTML(
        target.?,
        .beforeend,
        "<em>Direct enum</em>",
    );
    try insertAdjacentHTML(
        target.?,
        "beforeend",
        "<strong>Direct string</strong>",
    );
}

test "insertAdjacentHTML - all positions" {
    const allocator = testing.allocator;

    const doc = try z.parseFromString("<div id=\"target\">Target Content</div>");
    defer destroyDocument(doc);

    const body = try z.bodyNode(doc);
    const target = z.getElementById(body, "target");

    try insertAdjacentHTML(
        target.?,
        .beforebegin,
        "<p id=\"before\">Before</p>",
    );

    try insertAdjacentHTML(
        target.?,
        .afterbegin,
        "<span id=\"first\">First</span>",
    );

    try insertAdjacentHTML(
        target.?,
        .beforeend,
        "<span id=\"last\">Last</span>",
    );

    try insertAdjacentHTML(
        target.?,
        .afterend,
        "<p id=\"after\">After</p>",
    );

    const html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html);

    const pretty_expected =
        \\<body>
        \\  <p id="before">Before</p>
        \\  <div id="target">
        \\    <span id="first">First</span>Target Content<span id="last">Last</span>
        \\  </div>
        \\  <p id="after">After</p>
        \\</body>
    ;

    const expected = try z.normalizeText(allocator, pretty_expected, .{});
    defer allocator.free(expected);
    try testing.expectEqualStrings(expected, html);
}

test "insertAdjacentHTML - preserve order with multiple elements" {
    {
        const allocator = testing.allocator;
        const doc = try z.parseFromString("<html><body><div id=\"target\">Content</div></body></html>");
        defer destroyDocument(doc);

        const body = try z.bodyNode(doc);
        const target = z.getElementById(body, "target");

        // Insert multiple elements at once
        try insertAdjacentHTML(
            target.?,
            .afterend,
            "<p>First</p><p>Second</p><span>Third</span>",
        );
        try insertAdjacentHTML(
            target.?,
            .beforeend,
            "<p>First</p><p>Second</p><span>Third</span>",
        );
        try insertAdjacentHTML(
            target.?,
            .afterbegin,
            "<p>First</p><p>Second</p><span>Third</span>",
        );
        try insertAdjacentHTML(
            target.?,
            .beforebegin,
            "<p>First</p><p>Second</p><span>Third</span>",
        );

        const html = try z.outerHTML(allocator, z.nodeToElement(body).?);
        defer allocator.free(html);

        const pretty_html =
            \\<body>
            \\  <p>First</p><p>Second</p><span>Third</span>
            \\  <div id="target">
            \\      <p>First</p><p>Second</p><span>Third</span>Content<p>First</p><p>Second</p><span>Third</span>
            \\  </div>
            \\  <p>First</p><p>Second</p><span>Third</span>
            \\</body>
            \\
        ;

        const expected = try z.normalizeText(allocator, pretty_html, .{});
        defer allocator.free(expected);

        try testing.expectEqualStrings(expected, html);
    }
    {}
}

test "insertAdjacent demo" {
    const allocator = testing.allocator;

    // Create a simple document structure
    const doc = try z.parseFromString(
        \\<html><body>
        \\    <div id="container">
        \\        <p id="target">Target Element</p>
        \\    </div>
        \\</body></html>
    );
    defer destroyDocument(doc);

    const body = try z.bodyNode(doc);
    const target = z.getElementById(body, "target");

    // Demo 1: insertAdjacentElement with all positions
    const before_elem = try z.createElementAttr(
        doc,
        "h2",
        &.{.{ .name = "class", .value = "before" }},
    );
    try z.setContentAsText(elementToNode(before_elem), "Before Begin");

    try insertAdjacentElement(
        target.?,
        .beforebegin,
        before_elem,
    );

    const after_elem = try z.createElementAttr(
        doc,
        "h2",
        &.{.{ .name = "class", .value = "after" }},
    );
    try z.setContentAsText(elementToNode(after_elem), "After End");

    try insertAdjacentElement(
        target.?,
        .afterend,
        after_elem,
    );

    // Show result after insertAdjacentElement
    const html1 = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html1);

    // Normalize whitespace for clean comparison
    const clean_html1 = try z.normalizeText(allocator, html1, .{});
    defer allocator.free(clean_html1);

    const pretty_html =
        \\<body>
        \\  <div id="container">
        \\  <h2 class="before">Before Begin</h2>
        \\  <p id="target">Target Element</p>
        \\  <h2 class="after">After End</h2>
        \\  </div>
        \\</body>
    ;
    const expected1 = try z.normalizeText(allocator, pretty_html, .{});
    defer allocator.free(expected1);

    try testing.expectEqualStrings(expected1, clean_html1);

    // Demo 2: insertAdjacentHTML with different positions
    try insertAdjacentHTML(
        target.?,
        .afterbegin,
        "<span style=\"color: blue;\">First Child</span>",
    );
    try insertAdjacentHTML(
        target.?,
        .beforeend,
        "<span style=\"color: red;\">Last Child</span>",
    );

    // Show final result
    const html2 = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html2);

    // Normalize whitespace for clean comparison
    const clean_html2 = try z.normalizeText(allocator, html2, .{});
    defer allocator.free(clean_html2);

    const pretty_html_2 =
        \\<body>
        \\  <div id="container">
        \\  <h2 class="before">Before Begin</h2>
        \\  <p id="target">
        \\    <span style="color: blue;">First Child</span>Target Element<span style="color: red;">Last Child</span>
        \\  </p>
        \\  <h2 class="after">After End</h2>
        \\  </div>
        \\</body>
    ;

    const expected2 = try z.normalizeText(allocator, pretty_html_2, .{});
    defer allocator.free(expected2);

    try testing.expectEqualStrings(expected2, clean_html2);

    // Demo 3: InsertPosition.fromString functionality
    const positions = [_][]const u8{ "beforebegin", "afterbegin", "beforeend", "afterend", "invalid" };
    var valid_count: usize = 0;
    for (positions) |pos_str| {
        if (InsertPosition.fromString(pos_str)) |pos| {
            try testing.expect(@tagName(pos).len > 0); // Verify it has a valid tag name
            valid_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 4), valid_count); // Should have 4 valid positions

    // Demo 4: Multiple elements insertion
    const container = z.getElementById(body, "container");
    try insertAdjacentHTML(
        container.?,
        .beforeend,
        "<p>First</p><p>Second</p><span>Third</span>",
    );

    const html3 = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html3);

    // Normalize and verify multiple elements were inserted
    const clean_html3 = try z.normalizeText(allocator, html3, .{});
    defer allocator.free(clean_html3);

    try testing.expect(std.mem.indexOf(u8, clean_html3, "<p>First</p>") != null);
    try testing.expect(std.mem.indexOf(u8, clean_html3, "<p>Second</p>") != null);
    try testing.expect(std.mem.indexOf(u8, clean_html3, "<span>Third</span>") != null);
}

//=============================================================================
// Reflection
//=============================================================================

/// [core] Check if element is _void_ (like `<img>` or `<input>`, aka "self-closing")
///
/// #text nodes are not void
/// ## Example
/// ```
/// test "isVoid" {
///     const doc = try z.parseFromString("<p></p><img src=\"image.png\"/>Hello");
///     defer z.destroyDocument(doc);
///     const body = try z.bodyNode(doc);
///     const p = z.firstChild(body);
///     const img = z.nextSibling(p.?);
///     const t = z.nextSibling(img.?);
///
///     try testing.expect(z.isVoid(img.?));
///     try testing.expect(!z.isVoid(p.?));
///     try testing.expect(!z.isVoid(t.?));
/// }
/// ---
///```
pub fn isVoid(node: *z.DomNode) bool {
    return lxb_html_node_is_void_noi(node);
}

test "isVoid" {
    const doc = try z.parseFromString("<p></p><img src=\"image.png\"/>Hello");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);
    const p = z.firstChild(body);
    const img = z.nextSibling(p.?);
    const t = z.nextSibling(img.?);
    try testing.expect(z.isVoid(img.?));
    try testing.expect(!z.isVoid(p.?));
    try testing.expect(!z.isVoid(t.?));
}

/// [core] Used to check if node that is an _non Void element_ contains only whitespace
///
/// !! Void elements, #text or #comments nodes are seen as empty nodes
///
/// ## Examples
/// ```
/// test "isNodeEmpty" {
///     const img_elt = try z.createElementAttr(doc, "img", &.{.name = "src", .value = "image.png"});
///     const img = z.elementToNode(img_elt);
///     try testing.expect(z.isVoid(img);
///     try testing.expect(z.isNodeEmpty(img));
///
///     const text = try z.createTextNode(doc, "some text");
///     try testing.expect(z.isNodeEmpty(text));
///
///     const p_elt = try z.createElement(doc, "p");
///     const p = z.elementToNode(p_elt);
///     try testing.expect(z.isNodeEmpty(p));
///
///     z.appendChild((p, text);
///     try testing.expect(!z.isNodeEmpty(p));
///
///     const comment = try z.createComment(doc, "some comment");
///     try testing.expect(z.isNodeEmpty(z.commentToNode(comment)));
///}
/// ---
/// ```
pub fn isNodeEmpty(node: *z.DomNode) bool {
    return lxb_dom_node_is_empty(node);
}

test "isNodeEmpty" {
    const doc = try z.parseFromString("<html><body></body></html>");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);
    try testing.expect(z.isNodeEmpty(body));

    const img_elt = try z.createElementAttr(doc, "img", &.{.{ .name = "src", .value = "image.png" }});
    const img = z.elementToNode(img_elt);
    try testing.expect(z.isVoid(img));
    try testing.expect(z.isNodeEmpty(img));

    const text_1 = try z.createTextNode(doc, "some text");
    try testing.expect(!z.isVoid(text_1));
    try testing.expect(z.isNodeEmpty(text_1)); // #text nodes are always empty

    const comment = try z.createComment(doc, "some comment");
    try testing.expect(z.isNodeEmpty(z.commentToNode(comment)));

    const p_elt = try z.createElement(doc, "p");
    const p = z.elementToNode(p_elt);

    z.appendChild(p, text_1);
    try testing.expect(!z.isNodeEmpty(p));

    const text_2 = try z.createTextNode(doc, " \t ");
    try testing.expect(z.isNodeEmpty(text_2)); // #text nodes are always empty
    const p_elt_2 = try z.createElement(doc, "p");
    const p_2 = z.elementToNode(p_elt_2);
    z.appendChild(p_2, text_2);
    try testing.expect(z.isNodeEmpty(p_2)); // elements with whitespace only inner text nodes are seen as empty

    const span_elt = try z.createElement(doc, "span");
    const span = z.elementToNode(span_elt);
    z.appendChild(p_2, span);
    try testing.expect(!z.isNodeEmpty(p_2)); // p_2 contains a <span> element
}

test "what is empty?" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const body_node = try bodyNode(doc);
    const body = try bodyElement(doc);

    try testing.expect(isNodeEmpty(body_node));

    const innerHtml =
        "<p id=\"1\"></p><span>  </span><br/><img alt=\"img\"/><div>  \n </div><script></script><p> text </p>";
    _ = try z.setInnerHTML(body, innerHtml);
    const p = firstChild(body_node);
    const span = nextSibling(p.?);
    const br = nextSibling(span.?);
    const img = nextSibling(br.?);
    const div = nextSibling(img.?);
    const inner_div = z.firstChild(div.?);
    const script = nextSibling(div.?);
    const last_p = nextSibling(script.?);
    const inner_last_p = z.firstChild(last_p.?);

    try testing.expect(!isNodeEmpty(body_node));
    try testing.expect(isNodeEmpty(p.?)); // attributes don't change emptyness
    try testing.expect((!isVoid(p.?) and !(z.nodeType(p.?) == .comment) and !(z.nodeType(p.?) == .text)));
    try testing.expect(isNodeEmpty(span.?));
    try testing.expect(isNodeEmpty(br.?)); // self-closing empty
    try testing.expect(isNodeEmpty(img.?)); // self-closing empty
    try testing.expect(isNodeEmpty(div.?)); // whitespace only is empty
    try testing.expect(isNodeEmpty(script.?));
    try testing.expect(!isNodeEmpty(last_p.?)); // contains a node
    try testing.expect(isNodeEmpty(inner_div.?)); // #text are empty
    try testing.expect(isNodeEmpty(inner_last_p.?)); // #text are empty

    const text1 = try z.textContent(allocator, p.?);
    try testing.expectEqualStrings("", text1);

    // DIv is empty but contains whotespace like characters.
    const text2 = try z.textContent(allocator, div.?);
    defer allocator.free(text2);
    try testing.expect(text2.len == 4); // 3 ' ' and 1 '\n'

    const text3 = try z.textContent(allocator, inner_last_p.?);
    defer allocator.free(text3);
    try testing.expect(text3.len == 6);

    const p2 = try z.createTextNode(doc, "some text ");
    try testing.expect(z.isNodeEmpty(p2));
    const comment = try z.createComment(doc, "some comment");
    try testing.expect(z.isNodeEmpty(z.commentToNode(comment)));
}

//=================================================================
// Whitespace and Empty Nodes
//===================================================================

/// [core] Check if text slice contains only whitespace characters
pub fn isWhitespaceOnlyText(text: []const u8) bool {
    if (text.len == 0) return true;
    for (text) |c| {
        if (!std.ascii.isWhitespace(c)) {
            return false;
        }
    }
    return true;
}

test "trim action on whitespace containing text" {
    {
        const doc = try z.parseFromString("<p> \t \n </p>");
        defer z.destroyDocument(doc);
        const body = try z.bodyNode(doc);
        const p = z.firstChild(body).?;
        const t = z.firstChild(p).?;
        const trimmed = std.mem.trim(u8, z.textContent_zc(t), &std.ascii.whitespace);

        try testing.expect(trimmed.len == 0);
    }
    {
        const html =
            \\<p> \t \n 
            \\</p>
        ;
        const doc = try z.parseFromString(html);
        defer z.destroyDocument(doc);
        const body = try z.bodyNode(doc);
        const p = z.firstChild(body).?;
        const t = z.firstChild(p).?;
        const trimmed = std.mem.trim(u8, z.textContent_zc(t), &std.ascii.whitespace);

        try testing.expect(trimmed.len == 5);
    }
    {
        const html =
            \\<p> \t \n</p>  // No space after \n
        ;
        const doc = try z.parseFromString(html);
        defer z.destroyDocument(doc);
        const body = try z.bodyNode(doc);
        const p = z.firstChild(body).?;
        const t = z.firstChild(p).?;
        const trimmed = std.mem.trim(u8, z.textContent_zc(t), &std.ascii.whitespace);

        try testing.expect(trimmed.len == 5);
    }
    {
        const html =
            \\<p> \t a \n</p>  // No space after \n
        ;
        const doc = try z.parseFromString(html);
        defer z.destroyDocument(doc);
        const body = try z.bodyNode(doc);
        const p = z.firstChild(body).?;
        const t = z.firstChild(p).?;
        const trimmed = std.mem.trim(u8, z.textContent_zc(t), &std.ascii.whitespace);

        try testing.expect(trimmed.len == 7);
    }
    {
        const html = "<p> \t a \n</p>" // No space after \n
        ;
        const doc = try z.parseFromString(html);
        defer z.destroyDocument(doc);
        const body = try z.bodyNode(doc);
        const p = z.firstChild(body).?;
        const t = z.firstChild(p).?;
        const trimmed = std.mem.trim(u8, z.textContent_zc(t), &std.ascii.whitespace);

        try testing.expect(trimmed.len == 1);
    }
}

/// [core] Check if a text node is empty (contains only whitespace)
pub fn isTextNodeEmpty(node: *z.DomNode) !bool {
    if (z.nodeType(node) != .text) return error.NotTextNode;
    const text = z.textContent_zc(node);
    const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
    return trimmed.len == 0;
}

// =================================================================
// Tests
// =================================================================

test "memory safety: nodeName vs nodeNameOwned" {
    const allocator = std.testing.allocator;
    const doc = try createDocument();
    defer destroyDocument(doc);

    const element = try createElementAttr(doc, "div", &.{});
    defer destroyNode(elementToNode(element));

    // Test immediate use (safe with both versions)
    const unsafe_name = tagName_zc(element);
    try testing.expectEqualStrings("DIV", unsafe_name);

    // Test owned version (safe for storage)
    const owned_name = try tagName(allocator, element);
    defer allocator.free(owned_name);
    try testing.expectEqualStrings("DIV", owned_name);

    // Both should have the same content
    try testing.expectEqualStrings(unsafe_name, owned_name);

    // The owned version can be safely used after modifications
    const another_element = try createElementAttr(doc, "span", &.{});
    defer destroyNode(elementToNode(another_element));

    // owned_name is still valid and safe to use
    try testing.expectEqualStrings("DIV", owned_name);
}

test "create element and comment" {
    const allocator = std.testing.allocator;
    const doc = try createDocument();
    defer destroyDocument(doc);
    const element = try createElementAttr(doc, "div", &.{});
    defer destroyNode(elementToNode(element));
    const name = tagName_zc(element);
    try testing.expectEqualStrings("DIV", name);

    const comment = try createComment(doc, "This is a comment");
    const comment_text = try z.commentContent(
        allocator,
        comment,
    );
    defer allocator.free(comment_text);

    try testing.expectEqualStrings("This is a comment", comment_text);

    // Test type-safe conversion
    const comment_node = commentToNode(comment);
    const comment_name = z.nodeName_zc(comment_node);
    try testing.expectEqualStrings("#comment", comment_name);

    destroyComment(comment);
}

test "insertChild" {
    const doc = try createDocument();
    defer destroyDocument(doc);
    const parent = try createElementAttr(doc, "div", &.{});
    defer destroyNode(elementToNode(parent));

    const child = try createElementAttr(doc, "span", &.{});
    defer destroyNode(elementToNode(child));
    appendChild(elementToNode(parent), elementToNode(child));

    const first_child = firstChild(elementToNode(parent)) orelse {
        return Err.EmptyTextContent;
    };
    const child_name = tagName_zc(nodeToElement(first_child).?);
    try testing.expectEqualStrings("SPAN", child_name);
}

test "check error get body of empty element" {
    const doc = try createDocument();
    const body_element = bodyElement(doc);
    try testing.expectError(Err.NoBodyElement, body_element);

    const body_node = bodyNode(doc);
    try testing.expectError(Err.NoBodyElement, body_node);
}

test "root node element" {
    const doc = try z.parseFromString("");
    defer z.destroyDocument(doc);
    // // try z.printDocumentStructure(doc);
    const body_doc_node = try bodyNode(doc);
    const body_element = try bodyElement(doc);

    try testing.expectEqualStrings("BODY", tagName_zc(body_element));
    try testing.expectEqualStrings("BODY", z.nodeName_zc(body_doc_node));
}

test "children and childNodes" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<html><body><div>text<p>para</p><!-- comment --><span>span</span></div></body></html>");
    defer destroyDocument(doc);

    const body = try bodyElement(doc);
    const div = firstElementChild(body).?;

    // Test children (only elements)
    const element_children = try children(allocator, div);
    defer allocator.free(element_children);
    try testing.expect(element_children.len == 2); // p and span
    try testing.expectEqualStrings("P", tagName_zc(element_children[0]));
    try testing.expectEqualStrings("SPAN", tagName_zc(element_children[1]));

    // Test childNodes (all nodes including text and comments)
    const all_child_nodes = try childNodes(allocator, elementToNode(div));
    defer allocator.free(all_child_nodes);
    try testing.expect(all_child_nodes.len == 4); // text, p, comment, span

    // Verify legacy functions still work
    const legacy_children = try children(allocator, div);
    defer allocator.free(legacy_children);
    try testing.expect(legacy_children.len == element_children.len);
}

test "consistency check" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<html><body><div id='test' class='demo'>text<p>para</p><!-- comment --><span>span</span></div></body></html>");
    defer destroyDocument(doc);

    const body = try bodyElement(doc);
    const div = firstElementChild(body).?;

    // Test JavaScript-style attribute functions
    try testing.expect(z.hasAttribute(div, "id"));
    try testing.expect(z.hasAttribute(div, "class"));
    if (try z.getAttribute(allocator, div, "id")) |id_value| {
        defer allocator.free(id_value);
        try testing.expectEqualStrings("test", id_value);
    }

    // Test JavaScript-style children functions
    const element_children = try children(allocator, div);
    defer allocator.free(element_children);
    try testing.expect(element_children.len == 2); // p and span only

    const all_child_nodes = try childNodes(allocator, elementToNode(div));
    defer allocator.free(all_child_nodes);
    try testing.expect(all_child_nodes.len == 4); // text, p, comment, span

    // Verify no legacy function usage
    try testing.expectEqualStrings("P", tagName_zc(element_children[0]));
    try testing.expectEqualStrings("SPAN", tagName_zc(element_children[1]));
}

test "createTextNode and appendChild" {
    const doc = try z.parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const div = try createElementAttr(doc, "div", &.{});
    const text_node = try createTextNode(doc, "Hello, World!");
    appendChild(elementToNode(div), text_node);
    const body = try bodyElement(doc);
    appendChild(elementToNode(body), elementToNode(div));

    const body_node = elementToNode(body);
    const first_child = firstChild(body_node).?;
    const div_from_tree = nodeToElement(first_child).?;

    try testing.expect(div == div_from_tree);

    const div_first_child = firstChild(elementToNode(div_from_tree));
    try testing.expect(div_first_child != null);
    try testing.expect(z.isTypeText(div_first_child.?));
}

test "insertNodeBefore and insertNodeAfter" {
    const doc = try z.parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const body_node = try bodyNode(doc);

    const div1 = try createElementAttr(doc, "div", &.{});
    const div2 = try createElementAttr(doc, "div", &.{});
    const div3 = try createElementAttr(doc, "div", &.{});

    appendChild(body_node, elementToNode(div1));
    appendChild(body_node, elementToNode(div2));
    appendChild(body_node, elementToNode(div3));

    var element_count: usize = 0;
    var child = firstChild(body_node);
    while (child != null) {
        if (nodeToElement(child.?)) |_| {
            element_count += 1;
        }
        child = nextSibling(child.?);
    }

    try testing.expectEqual(@as(usize, 3), element_count);

    // Verify order
    const first_child = z.firstChild(body_node).?;
    const second_child = nextSibling(first_child).?;
    const third_child = nextSibling(second_child).?;

    try testing.expect(first_child == elementToNode(div1));
    try testing.expect(second_child == elementToNode(div2));
    try testing.expect(third_child == elementToNode(div3));
}
test "appendChildren helper" {
    const doc = try z.parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const body_node = try bodyNode(doc);

    const div1 = try createElementAttr(doc, "div", &.{});
    const div2 = try createElementAttr(doc, "p", &.{});
    const div3 = try createElementAttr(doc, "span", &.{});

    const child_nodes = [_]*z.DomNode{ elementToNode(div1), elementToNode(div2), elementToNode(div3) };

    appendChildren(body_node, child_nodes[0..]);

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
    const doc = try z.parseFromString("<p>   </p>");
    defer destroyDocument(doc);
    const body_node = try z.bodyNode(doc);
    const p = firstChild(body_node);

    try testing.expect(z.isNodeEmpty(p.?));

    // inner text node is whitespace-only
    const inner_text_node = firstChild(p.?);
    try testing.expect(
        z.isTypeText(inner_text_node.?),
    );

    try testing.expect(
        try isTextNodeEmpty(inner_text_node.?),
    );

    try testing.expectError(Err.NotTextNode, isTextNodeEmpty(p.?));

    // other way to create some nodes
    destroyNode(p.?);
    const div = try createElement(doc, "div");
    const node_div = elementToNode(div);

    try z.setContentAsText(node_div, "\n \r  \t");
    // should be true
    const div_text = z.firstChild(node_div).?;
    try testing.expect(z.isTypeText(div_text));
    try testing.expect(z.isNodeEmpty(node_div));

    destroyNode(node_div);
    const span = try createElement(doc, "span");
    const node_span = elementToNode(span);

    try z.setContentAsText(node_span, "\n \r a \t");
    // should be true
    const span_text = z.firstChild(node_span).?;

    const my_test = try z.isNodeTextEmpty(span_text);
    try testing.expect(!my_test);
}

test "create Html element, tagFromQualifiedName, custom element" {
    const doc = try z.parseFromString("<p></p>");
    const body_node = try bodyNode(doc);

    const span_element = try createElementAttr(doc, "span", &.{});
    const tag = tagName_zc(span_element);
    const span_tag = z.tagFromQualifiedName("span");
    try testing.expectEqualStrings(tag, "SPAN");
    try testing.expect(span_tag.? == .span);
    try testing.expect(z.tagFromQualifiedName("span") == .span);

    // Test custom element creation
    const custom_elt = try createElementAttr(
        doc,
        "custom-element",
        &.{.{ .name = "data-id", .value = "123" }},
    );
    const custom_tag = (tagName_zc(custom_elt));
    try testing.expectEqualStrings(custom_tag, "CUSTOM-ELEMENT");
    // not an "official" HTML tag
    try testing.expect(z.tagFromQualifiedName("custom-element") == null);

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
            const element_name = tagName_zc(element);
            if (std.mem.eql(u8, element_name, "CUSTOM-ELEMENT")) {
                found_custom = true;
                break;
            }
        }
        child = nextSibling(child.?);
    }
    try testing.expect(found_custom);

    const allocator = std.testing.allocator;
    const text = try z.outerHTML(allocator, z.nodeToElement(body_node).?);
    defer allocator.free(text);
    try testing.expectEqualStrings("<body><p></p><custom-element data-id=\"123\"></custom-element><span></span></body>", text);

    // Now test what happens when parsing custom elements from HTML
    const doc_with_custom = try z.parseFromString("<body><custom-element>Test</custom-element></body>");
    defer z.destroyDocument(doc_with_custom);

    const custom_body = try bodyNode(doc_with_custom);
    var parsed_child = firstChild(custom_body);
    var found_parsed_custom = false;

    while (parsed_child != null) {
        if (nodeToElement(parsed_child.?)) |element| {
            const element_name = tagName_zc(element);
            if (std.mem.eql(u8, element_name, "CUSTOM-ELEMENT")) {
                found_parsed_custom = true;
                break;
            }
        }
        parsed_child = nextSibling(parsed_child.?);
    }

    try testing.expect(found_parsed_custom);
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

    const doc = try z.parseFromString(html);
    defer destroyDocument(doc);

    const body = try bodyElement(doc);
    const body_node = elementToNode(body);
    const div_node = firstChild(body_node).?;

    var child = firstChild(div_node);
    const void_elements = [_][]const u8{ "BR", "HR", "IMG", "INPUT", "META", "LINK", "AREA" };

    var empty_non_self_closing_non_text_nodes_count: usize = 0;
    var empty_text_nodes_count: usize = 0;
    var empty_nodes: usize = 0;

    while (child != null) {
        if (nodeToElement(child.?)) |_| {
            const tag_name = z.nodeName_zc(child.?);
            const is_void = isVoid(child.?);
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
                    if (z.isTypeText(child.?)) {
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

test "practical string-to-DOM scenarios" {
    {
        // 1: Full page `z.parseFromString()` and `outerHTML()` round-trip test
        const allocator = testing.allocator;

        const full_page =
            \\<!DOCTYPE html>
            \\<html>
            \\  <head><title>My Page</title></head>
            \\  <body>
            \\    <h1>Welcome</h1>
            \\    <p>Content here</p>
            \\  </body>
            \\</html>
        ;

        const doc = try z.parseFromString(full_page);
        defer destroyDocument(doc);

        const serialized_html = try z.outerHTML(
            allocator,
            z.nodeToElement(documentRoot(doc).?).?, // HTML
        );
        defer allocator.free(serialized_html);

        const normalized_html = try z.normalizeText(
            allocator,
            serialized_html,
            .{},
        );
        defer allocator.free(normalized_html);

        const expected_html =
            \\<html>
            \\  <head><title>My Page</title></head>
            \\  <body>
            \\    <h1>Welcome</h1>
            \\    <p>Content here</p>
            \\  </body>
            \\</html>
        ;
        const normalized_expected = try z.normalizeText(
            allocator,
            expected_html,
            .{},
        );
        defer allocator.free(normalized_expected);

        try testing.expectEqualStrings(normalized_expected, normalized_html);
    }
    {
        // 2: Dynamic fragment building and insertion with `setInnerHTML()`
        const template_doc = try z.parseFromString("<html><body><div id='content'></div></body></html>");
        defer destroyDocument(template_doc);

        const template_root = z.documentRoot(template_doc);
        const content_div = z.getElementById(template_root.?, "content");

        // Simulate user data
        const user_data = [_]struct { name: []const u8, email: []const u8 }{
            .{ .name = "Alice", .email = "alice@example.com" },
            .{ .name = "Bob", .email = "bob@example.com" },
        };
        const allocator = testing.allocator;
        var user_list: std.ArrayList(u8) = .empty;
        defer user_list.deinit(allocator);

        try user_list.appendSlice(allocator, "<ul>");
        for (user_data) |user| {
            const user_item = try std.fmt.allocPrint(
                allocator,
                "<li><strong>{s}</strong> - {s}</li>",
                .{ user.name, user.email },
            );
            defer allocator.free(user_item);

            try user_list.appendSlice(allocator, user_item);
        }
        try user_list.appendSlice(allocator, "</ul>");

        _ = try z.setInnerHTML(content_div.?, user_list.items);

        const result = try z.outerHTML(allocator, content_div.?);
        defer allocator.free(result);

        const expected_pretty_result =
            \\<div id="content">
            \\  <ul>
            \\    <li><strong>Alice</strong> - alice@example.com</li>
            \\    <li><strong>Bob</strong> - bob@example.com</li>
            \\  </ul>
            \\</div>
        ;
        const expected_result = try z.normalizeText(allocator, expected_pretty_result, .{});
        defer allocator.free(expected_result);

        try testing.expectEqualStrings(expected_result, result);
    }
    {
        // 3: Using `insertAdjacentHTML()` for reusable components
        const allocator = testing.allocator;

        const components = [_][]const u8{
            "<button class=\"btn btn-primary\">Click me</button>",
            "<input type=\"email\" placeholder=\"Enter email\" required>",
            "<div class=\"alert alert-info\">Information message</div>",
        };

        const app_doc = try z.parseFromString("<html><body><div id=\"app\"></div></body></html>");
        defer destroyDocument(app_doc);
        const app_root = z.documentRoot(app_doc);

        const app_div = z.getElementById(app_root.?, "app");

        for (components, 0..) |component, i| {
            // const current_content = try z.innerHTML(allocator, app_div.?);
            // defer allocator.free(current_content);

            // const updated_content = try std.fmt.allocPrint(
            //     allocator,
            //     "{s}<div class=\"component-{d}\">{s}</div>",
            //     .{ current_content, i, component },
            // );
            const updated_content = try std.fmt.allocPrint(
                allocator,
                "<div class=\"component-{d}\">{s}</div>",
                .{ i, component },
            );

            defer allocator.free(updated_content);

            try z.insertAdjacentHTML(
                app_div.?,
                .beforeend,
                updated_content,
            );
            // _ = try z.setInnerHTML(
            //     allocator,
            //     app_div.?,
            //     updated_content,
            //     .{ .allow_html = true },
            // );
        }

        const result = try z.outerHTML(allocator, app_div.?);
        defer allocator.free(result);

        const expected_pretty_result =
            \\  <div id="app">
            \\    <div class="component-0">
            \\      <button class="btn btn-primary">Click me</button>
            \\    </div>
            \\    <div class="component-1">
            \\      <input type="email" placeholder="Enter email" required>
            \\    </div>
            \\    <div class="component-2">
            \\      <div class="alert alert-info">Information message</div>
            \\    </div>
            \\  </div>
        ;
        const expected_result = try z.normalizeText(allocator, expected_pretty_result, .{});
        defer allocator.free(expected_result);

        try testing.expectEqualStrings(expected_result, result);
    }
    {
        // 4. Template rendering - TODO
        // const template = try z.createElementAttr(allocator, "template");
        // defer allocator.free(template);
    }
}

// TODO
test "Performance comparison: Character-based vs Lexbor-based HTML normalization" {
    // const allocator = testing.allocator;

    // Create a complex, realistic HTML document with lots of whitespace variations
    const complex_html =
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\  <head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <title>   Complex   HTML   Document   </title>
        \\    <style>
        \\      body {
        \\        margin: 0;
        \\        padding: 20px;
        \\        font-family: Arial, sans-serif;
        \\      }
        \\      .container {
        \\        max-width: 1200px;
        \\        margin: 0 auto;
        \\      }
        \\    </style>
        \\  </head>
        \\  <body>
        \\    <header class="main-header">
        \\      <nav>
        \\        <ul class="nav-list">
        \\          <li><a href="/">  Home  </a></li>
        \\          <li><a href="/about">   About   </a></li>
        \\          <li><a href="/services">    Services    </a></li>
        \\          <li><a href="/contact">     Contact     </a></li>
        \\        </ul>
        \\      </nav>
        \\    </header>
        \\    
        \\    <main class="container">
        \\      <section class="hero">
        \\        <h1>   Welcome to Our   Amazing   Website   </h1>
        \\        <p>
        \\          This is a   complex   HTML document   with   lots of   
        \\          whitespace   variations   to test   the performance   
        \\          of different   normalization   approaches.
        \\        </p>
        \\        <div class="cta-buttons">
        \\          <button class="btn primary">   Get Started   </button>
        \\          <button class="btn secondary">   Learn More   </button>
        \\        </div>
        \\      </section>
        \\      
        \\      <section class="features">
        \\        <h2>   Our   Features   </h2>
        \\        <div class="feature-grid">
        \\          <div class="feature-card">
        \\            <h3>   Fast   Performance   </h3>
        \\            <p>   Lightning fast   response times   for all   operations.   </p>
        \\            <ul>
        \\              <li>   Sub-millisecond   parsing   </li>
        \\              <li>   Optimized   memory   usage   </li>
        \\              <li>   Parallel   processing   </li>
        \\            </ul>
        \\          </div>
        \\          <div class="feature-card">
        \\            <h3>   Easy   Integration   </h3>
        \\            <p>   Simple   API   that   works   with   any   framework.   </p>
        \\            <ul>
        \\              <li>   RESTful   endpoints   </li>
        \\              <li>   SDK   for   popular   languages   </li>
        \\              <li>   Comprehensive   documentation   </li>
        \\            </ul>
        \\          </div>
        \\          <div class="feature-card">
        \\            <h3>   Reliable   Support   </h3>
        \\            <p>   24/7   customer   support   and   monitoring.   </p>
        \\            <ul>
        \\              <li>   99.9%   uptime   guarantee   </li>
        \\              <li>   Expert   technical   support   </li>
        \\              <li>   Real-time   monitoring   </li>
        \\            </ul>
        \\          </div>
        \\        </div>
        \\      </section>
        \\      
        \\      <section class="testimonials">
        \\        <h2>   What   Our   Customers   Say   </h2>
        \\        <div class="testimonial-list">
        \\          <blockquote class="testimonial">
        \\            <p>   "This   product   has   revolutionized   our   workflow.   
        \\            The   performance   improvements   are   incredible!"   </p>
        \\            <cite>   John   Smith,   CEO   of   TechCorp   </cite>
        \\          </blockquote>
        \\          <blockquote class="testimonial">
        \\            <p>   "Outstanding   support   and   rock-solid   reliability.   
        \\            We've   never   had   any   downtime   issues."   </p>
        \\            <cite>   Sarah   Johnson,   CTO   of   WebSolutions   </cite>
        \\          </blockquote>
        \\          <blockquote class="testimonial">
        \\            <p>   "The   integration   was   seamless   and   the   
        \\            documentation   is   excellent.   Highly   recommended!"   </p>
        \\            <cite>   Mike   Davis,   Lead   Developer   at   StartupXYZ   </cite>
        \\          </blockquote>
        \\        </div>
        \\      </section>
        \\    </main>
        \\    
        \\    <footer class="main-footer">
        \\      <div class="container">
        \\        <div class="footer-content">
        \\          <div class="footer-section">
        \\            <h4>   Company   </h4>
        \\            <ul>
        \\              <li><a href="/about">   About   Us   </a></li>
        \\              <li><a href="/careers">   Careers   </a></li>
        \\              <li><a href="/press">   Press   </a></li>
        \\            </ul>
        \\          </div>
        \\          <div class="footer-section">
        \\            <h4>   Support   </h4>
        \\            <ul>
        \\              <li><a href="/help">   Help   Center   </a></li>
        \\              <li><a href="/contact">   Contact   Us   </a></li>
        \\              <li><a href="/status">   System   Status   </a></li>
        \\            </ul>
        \\          </div>
        \\          <div class="footer-section">
        \\            <h4>   Legal   </h4>
        \\            <ul>
        \\              <li><a href="/privacy">   Privacy   Policy   </a></li>
        \\              <li><a href="/terms">   Terms   of   Service   </a></li>
        \\              <li><a href="/cookies">   Cookie   Policy   </a></li>
        \\            </ul>
        \\          </div>
        \\        </div>
        \\        <div class="footer-bottom">
        \\          <p>   ©   2024   Amazing   Company.   All   rights   reserved.   </p>
        \\        </div>
        \\      </div>
        \\    </footer>
        \\    
        \\    <script>
        \\      // Some JavaScript with whitespace
        \\      document.addEventListener('DOMContentLoaded', function() {
        \\        const   buttons   =   document.querySelectorAll('.btn');
        \\        buttons.forEach(function(button) {
        \\          button.addEventListener('click',   function(e)   {
        \\            console.log('Button   clicked:',   e.target.textContent.trim());
        \\          });
        \\        });
        \\      });
        \\    </script>
        \\  </body>
        \\</html>
    ;
    _ = complex_html;
}
