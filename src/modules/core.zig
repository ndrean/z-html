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

// External lexbor functions
extern "c" fn lxb_html_interface_template_wrapper() ?*const anyopaque;
extern "c" fn lxb_html_template_content_wrapper(template_element: *anyopaque) ?*z.DomNode;
extern "c" fn lxb_html_tree_node_is_wrapper(node: *z.DomNode, tag_id: u32) bool;

/// Check if a node is a template element
pub fn isTemplateElement(node: *z.DomNode) bool {
    return lxb_html_tree_node_is_wrapper(node, LXB_TAG_TEMPLATE);
}

/// Get template interface for template elements
pub fn templateInterface(element: *z.DomElement) ?*z.HtmlTemplate {
    _ = element; // For compatibility - wrapper doesn't need element parameter
    return @ptrCast(@constCast(lxb_html_interface_template_wrapper()));
}

/// Template-aware first child - handles template elements correctly
pub fn templateAwareFirstChild(node: *z.DomNode) ?*z.DomNode {
    if (isTemplateElement(node)) {
        // Template elements store content in DocumentFragment
        if (getTemplateContent(node)) |content| {
            return firstChild(content);
        }
        return null;
    }
    return firstChild(node);
}

// Helper function for template content access (needs implementation)
/// Get the content of a template element
pub fn getTemplateContent(node: *z.DomNode) ?*z.DomNode {
    if (!isTemplateElement(node)) return null;
    return lxb_html_template_content_wrapper(node);
}

fn templateContentFirstChild(template: *z.HtmlTemplate) ?*z.DomNode {
    _ = template; // Simplified - use node-based approach
    return null; // Will be replaced by getTemplateContent flow
}
pub const LXB_TAG_STYLE: u32 = 0x2d;
pub const LXB_TAG_SCRIPT: u32 = 0x29;

//===========================================================================
// CORE DOCUMENT FUNCTIONS
//===========================================================================

extern "c" fn lxb_html_document_create() ?*z.HtmlDocument;
extern "c" fn lxb_html_document_destroy(doc: *z.HtmlDocument) void;
extern "c" fn lxb_html_document_parse(doc: *z.HtmlDocument, html: [*]const u8, len: usize) usize;

/// [core] Creates and returns a new HTML document.
///
/// Caller must free with `destroyDocument`.
///
/// To create a useable document, simply use instead `parseFromString("")`
/// ## Example
/// ```
/// const doc = try createDocument();
/// defer destroyDocument(doc);
/// ```
pub fn createDocument() !*z.HtmlDocument {
    return lxb_html_document_create() orelse Err.DocCreateFailed;
}

/// [core] Destroy an HTML document.
pub fn destroyDocument(doc: *z.HtmlDocument) void {
    lxb_html_document_destroy(doc);
}

/// [core] Parse HTML string into document and creates a new document.
/// Returns a new document.
///
/// Caller must free with `destroyDocument`.
///
/// ## Example
/// ```
/// const doc = try parseFromString("<!DOCTYPE html><html><body></body></html>");
/// defer destroyDocument(doc);
/// ```
pub fn parseFromString(html: []const u8) !*z.HtmlDocument {
    const doc = createDocument() catch {
        return Err.DocCreateFailed;
    };
    const status = lxb_html_document_parse(doc, html.ptr, html.len);
    if (status != z.LXB_STATUS_OK) return Err.ParseFailed;
    return doc;
}

// =============================================================================
// CREATION
// =============================================================================

extern "c" fn lxb_html_document_create_element_noi(doc: *z.HtmlDocument, tag_name: [*]const u8, tag_len: usize, reserved_for_opt: ?*anyopaque) ?*z.DomElement;

extern "c" fn lxb_dom_document_create_text_node(doc: *z.HtmlDocument, text: [*]const u8, text_len: usize) ?*z.DomNode;
extern "c" fn lxb_dom_document_create_document_fragment(doc: *z.HtmlDocument) ?*z.DomNode;
extern "c" fn lxb_dom_node_insert_before(to: *z.DomNode, node: *z.DomNode) void;
extern "c" fn lxb_dom_node_insert_after(to: *z.DomNode, node: *z.DomNode) void;
extern "c" fn lxb_dom_document_create_comment(doc: *z.HtmlDocument, data: [*]const u8, len: usize) ?*z.Comment;
extern "c" fn lxb_dom_comment_interface_destroy(doc: *z.Comment) *z.Comment;
extern "c" fn lxb_dom_node_insert_child(parent: *z.DomNode, child: *z.DomNode) void;
extern "c" fn lxb_html_document_body_element_noi(doc: *z.HtmlDocument) ?*z.DomElement;
extern "c" fn lxb_dom_document_root(doc: *z.HtmlDocument) ?*z.DomNode;
extern "c" fn lexbor_node_owner_document(node: *z.DomNode) *z.HtmlDocument;
extern "c" fn lxb_dom_node_parent_noi(node: *z.DomNode) ?*z.DomNode;
extern "c" fn lxb_dom_document_create_element(doc: *z.HtmlDocument, local_name: [*]const u8, lname_len: usize, reserved_for_opt: ?*anyopaque) ?*z.DomElement;

extern "c" fn lxb_dom_document_destroy_element(element: *z.DomElement) *z.DomElement;
extern "c" fn lexbor_dom_interface_node_wrapper(obj: *anyopaque) *z.DomNode;
extern "c" fn lexbor_dom_interface_element_wrapper(node: *z.DomNode) ?*z.DomElement;
extern "c" fn lxb_dom_node_name(node: *z.DomNode, len: ?*usize) [*:0]const u8;
extern "c" fn lxb_dom_element_tag_name(element: *z.DomElement, len: ?*usize) [*:0]const u8;
extern "c" fn lxb_dom_element_qualified_name(element: *z.DomElement, len: *usize) [*:0]const u8;
extern "c" fn lxb_dom_node_remove(node: *z.DomNode) void;
extern "c" fn lxb_dom_node_destroy(node: *z.DomNode) void;

/// [core] Element creation and returns a !Element
///
/// Can create HTMLElements or custom elements.
///
/// It takes an optional array of attributes pair (`.name`, `.value`).
/// If the tag is a custom element, the `name` will be copied to the element's tag name.
/// ## Example
///
/// ```
/// const span: *z.DomElement = try createElement(doc, "span", &.{});
/// const button: *z.DomElement = try createElement(doc, "button",
///     &.{
///         .{.name = "phx-click", .value = "submit"},
///         .{.name = "phx-value-myvar", .value= "myvar"}
///     });
/// ```
pub fn createElement(doc: *z.HtmlDocument, name: []const u8, attrs: []const z.AttributePair) !*z.DomElement {
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

/// [core] Create a text node in the document and returns a !Node
///
/// ## Example
/// ```
/// const textNode: *z.DomElement = try createTextNode(doc, "Hello, World!");
/// ```
pub fn createTextNode(doc: *z.HtmlDocument, text: []const u8) !*z.DomNode {
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
/// const commentNode: *z.Comment = try createComment(doc, "Hello, World!");
/// ```
pub fn createComment(doc: *z.HtmlDocument, data: []const u8) !*z.Comment {
    return lxb_dom_document_create_comment(
        doc,
        data.ptr,
        data.len,
    ) orelse Err.CreateCommentFailed;
}

/// [core] Create a document fragment and returns a !Node
///
/// Document fragments are lightweight containers that can hold multiple nodes. Useful for batch DOM operations
///
/// When you append a fragment to the DOM, only its children are added, not the fragment itself.
pub fn createDocumentFragment(doc: *z.HtmlDocument) !*z.DomNode {
    return lxb_dom_document_create_document_fragment(doc) orelse Err.FragmentParseFailed;
}

// ---------------------------------------------------------------------------
// Root, Owner, Body node/element access
// ---------------------------------------------------------------------------

/// [core] Returns the document root node ("HTML" or "XML")
pub fn documentRoot(doc: *z.HtmlDocument) ?*z.DomNode {
    return lxb_dom_document_root(doc);
}

/// [core] Returns the document
pub fn ownerDocument(node: *z.DomNode) *z.HtmlDocument {
    return lexbor_node_owner_document(node);
}

test "documentRoot - ownerDocument" {
    const doc = try parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const doc_root = documentRoot(doc);
    try testing.expectEqualStrings("HTML", z.nodeNameBorrow(doc_root.?));

    const owner = ownerDocument(doc_root.?);
    try testing.expect(owner == doc);
}
/// [core] Get the document's body element (usually BODY)
///
/// ## Example
/// ```
/// const bodyElement: *z.DomElement = try bodyElement(doc);
/// ```
pub fn bodyElement(doc: *z.HtmlDocument) !*z.DomElement {
    if (lxb_html_document_body_element_noi(doc)) |element| {
        return element;
    } else {
        return Err.NoBodyElement;
    }
}

/// [core] Get the document's body node (usually BODY)
pub fn bodyNode(doc: *z.HtmlDocument) !*z.DomNode {
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
        try testing.expectEqualStrings("BODY", z.tagNameBorrow(body_elt));

        const body_node = try z.bodyNode(doc);
        try testing.expectEqualStrings("BODY", z.nodeNameBorrow(body_node));
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
fn objectToNode(obj: *anyopaque) *z.DomNode {
    return lexbor_dom_interface_node_wrapper(obj);
}

/// [core] Convert DOM Element to Node
pub fn elementToNode(element: *z.DomElement) *z.DomNode {
    return objectToNode(element);
}

/// [core] Convert Comment to Node
pub fn commentToNode(comment: *z.Comment) *z.DomNode {
    return objectToNode(comment);
}

/// [core] Convert DOM node to Element
///
/// Returns NULL if the node is not an element
pub fn nodeToElement(node: *z.DomNode) ?*z.DomElement {
    // Only convert if it's actually an element node
    if (z.nodeType(node) != .element) {
        return null;
    }

    return lexbor_dom_interface_element_wrapper(node);
}

test "element/node/element" {
    const doc = try createDocument();
    const div_elt = try createElement(doc, "div", &.{});
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
    const doc = try parseFromString("<html><body><!-- a comment --></body></html>");
    defer destroyDocument(doc);

    const body = try bodyNode(doc);

    const first_comment_node = firstChild(body);
    const first_comment = nodeToComment(first_comment_node.?);
    try testing.expect(first_comment != null);

    const div_elt = try createElement(doc, "div", &.{});
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

/// [core] (UPPERCASED if element) Get the tag name or type of a _node_ as Zig string (UNSAFE: borrows lexbor's memory)
///
/// - returns the `nodeType` (#text, #comment) for non-elements nodes,
/// - returns the `tagName` in UPPERCASE for element nodes.
///
/// ⚠️ Do NOT store this slice beyond the lifetime of the node.
///
/// Use the allocated `z.nodeName()` if you need to store the result.
/// ## Example
/// ```
/// test "nodeType/tagname" {
///     const doc = try createDocument();
///     const div_elt = try createElement(doc, "div", &.{});
///     const div_name = z.nodeNameBorrow(elementToNode(div_elt));
///     try testing.expectEqualStrings(div_name, "DIV");
/// }
/// ---
/// ```
pub fn nodeNameBorrow(node: *z.DomNode) []const u8 {
    const name_ptr = lxb_dom_node_name(node, null);
    return std.mem.span(name_ptr);
}

/// [core] (UPPERCASED if element) Get the tag name or type of a _node_ as owned Zig string.
///
/// - returns the `nodeType` (#text, #comment) for non-elements nodes,
/// - returns the `tagName` in UPPERCASE for element nodes.
///
/// Caller must free the returned string.
/// ## Example
/// ```
/// const allocator = testing.allocator;
/// const text = try createTextNode(doc, "Hello"); // a node
/// const text_name = try nodeName(allocator, text);
/// defer allocator.free(text_name);
/// try testing.expectEqualStrings(text_name, "#text");
///
/// const div = try createElement(doc, "div", &.{}); // an element
/// const name = try nodeName(allocator, elementToNode(div));
/// defer allocator.free(name);
/// try testing.expectEqualStrings(name, "DIV");
/// ---
/// ```
pub fn nodeName(allocator: std.mem.Allocator, node: *z.DomNode) ![]u8 {
    const name_slice = z.nodeNameBorrow(node);
    return try allocator.dupe(u8, name_slice);
}

test "nodeName/Borrow" {
    const allocator = testing.allocator;
    const doc = try createDocument();

    const div_elt = try createElement(doc, "div", &.{});
    const div_name = z.nodeNameBorrow(elementToNode(div_elt));
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
    const text_name = nodeNameBorrow(text);
    try testing.expectEqualStrings(text_name, "#text");
}

/// [core] (UPPERCASED) Get the tag name on an _element_ as Zig string (UNSAFE: borrows lexbor's memory)
///
/// ⚠️  Do NOT store this slice beyond the lifetime of the element.
///
/// Use tagName() if you need to store the result.
/// ## Example
/// ```
/// const allocator = testing.allocator;
/// const doc = try createDocument();
/// const div = try createElement(doc, "div", &.{});
/// const name = tagNameBorrow(elementToNode(div));
/// try testing.expectEqualStrings(name, "DIV");
/// ---
/// ```
pub fn tagNameBorrow(element: *z.DomElement) []const u8 {
    const name_ptr = lxb_dom_element_tag_name(element, null);
    return std.mem.span(name_ptr);
}

/// [core]  (UPPERCASED) Get the tag name on an _element_ as owned Zig string (SAFE: copies to Zig memory)
///
/// Returns a copy of the tag name that is owned by the caller.
///
/// Caller must free the returned string.
/// ## Example
/// ```
/// const allocator = testing.allocator;
/// const doc = try createDocument();
/// const div = try createElement(doc, "div", &.{});
/// const name = try tagName(allocator, elementToNode(div));
/// defer allocator.free(name);
/// try testing.expectEqualStrings(name, "DIV");
/// ___
/// ```
pub fn tagName(allocator: std.mem.Allocator, element: *z.DomElement) ![]u8 {
    const name_slice = tagNameBorrow(element);
    return try allocator.dupe(u8, name_slice);
}

/// [core] (lowercased) Get the allocated qualified name of an _element_ (namespace:tagname or just tagname)
///
/// This is useful for elements with namespaces like SVG or MathML.
///
/// Caller must free the returned slice.
/// ## Example
/// ```
/// const allocator = testing.allocator;
/// const doc = try createDocument();
/// const div = try z.createElement(doc, "div", &.{});
/// const name = try qualifiedName(allocator, elementToNode(div));
/// defer allocator.free(name);
/// try testing.expectEqualStrings(name, "div");
/// ___
/// ```
pub fn qualifiedName(allocator: std.mem.Allocator, element: *z.DomElement) ![]u8 {
    var name_len: usize = 0;
    const name_ptr = lxb_dom_element_qualified_name(element, &name_len);

    const result = try allocator.alloc(u8, name_len);
    @memcpy(result, name_ptr[0..name_len]);
    return result;
}

test "qualified name" {
    const allocator = testing.allocator;
    const doc = try createDocument();
    const div = try createElement(doc, "div", &.{});
    const owned_name = try qualifiedName(allocator, div);
    defer allocator.free(owned_name);
    try testing.expectEqualStrings(owned_name, "div");
    const borrow_name = qualifiedNameBorrow(div);
    try testing.expectEqualStrings(borrow_name, "div");
}

/// [core] (lowercased) Get the qualified name of an _element_ (borrowed, zero-copy version)
///
/// Caller must free the returned slice.
///
///
/// ⚠️  Do NOT store this slice beyond the lifetime of the element.
/// ## Example
/// ```zig
/// const doc = try createDocument();
/// const div_elt = try createElement(doc, "div", &.{});
/// const name = qualifiedNameBorrow(div_elt);
/// try testing.expectEqualStrings(name, "div");
/// ---
/// ```
pub fn qualifiedNameBorrow(element: *z.DomElement) []const u8 {
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
    lxb_dom_node_remove(node);
}

/// [core] Destroy a node from the DOM
pub fn destroyNode(node: *z.DomNode) void {
    lxb_dom_node_destroy(node);
}

/// [core] Destroy an element in the document
pub fn destroyElement(element: *z.DomElement) void {
    _ = lxb_dom_document_destroy_element(element);
}

//=============================================================================

//=============================================================================
// Reflexion

extern "c" fn lxb_html_node_is_void_noi(node: *z.DomNode) bool;
extern "c" fn lxb_dom_node_is_empty(node: *z.DomNode) bool;

/// [core] Check if element is _void_ (self-closing like <img>, <br>)
pub fn isSelfClosingNode(node: *z.DomNode) bool {
    return lxb_html_node_is_void_noi(node);
}

/// [core] Used to check if node that is an _non self-closing element_ contains only whitespace
///
/// Self-closing elements, #text or #comments nodes are seen as empty nodes
///
/// ## Examples
/// ```
/// const img = try z.createElement(doc, "img", &.{.name = "src", .value = "image.png"});
/// try testing.expect(z.isSelfClosing(z.elementToNode(img)));
/// try testing.expect(z.isNodeEmpty(z.elementToNode(img)));
///
/// const p = try z.createTextNode(doc, "some text");
/// try testing.expect(z.isNodeEmpty(p));
///
/// const comment = try z.createComment(doc, "some comment");
/// try testing.expect(z.isNodeEmpty(z.commentToNode(comment)));
///
/// // to select only non self-closing elements, do:
/// if (!z.isSelfClosingNode(node) and !(z.nodeType(node) == .comment) and !(z.nodeType(node) == .text)) {
///   if (z.isNodeEmpty(node)) {
///     std.debug.print("node is \"really\" empty!", .{} );
///   }
/// }
pub fn isNodeEmpty(node: *z.DomNode) bool {
    return lxb_dom_node_is_empty(node);
}

test "what is empty?" {
    const allocator = testing.allocator;
    const doc = try parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const body_node = try bodyNode(doc);
    const body = try bodyElement(doc);

    try testing.expect(isNodeEmpty(body_node));

    const innerHtml =
        "<p id=\"1\"></p><span>  </span><br/><img alt=\"img\"/><div>  \n </div><script></script><p> text </p>";
    _ = try z.setInnerHTML(allocator, body, innerHtml, .{});
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
    try testing.expect((!isSelfClosingNode(p.?) and !(z.nodeType(p.?) == .comment) and !(z.nodeType(p.?) == .text)));
    try testing.expect(isNodeEmpty(span.?));
    try testing.expect(isNodeEmpty(br.?)); // self-closing empty
    try testing.expect(isNodeEmpty(img.?)); // self-closing empty
    try testing.expect(isNodeEmpty(div.?)); // whitespace only is empty
    try testing.expect(isNodeEmpty(script.?));
    try testing.expect(!isNodeEmpty(last_p.?)); // contains a node
    try testing.expect(isNodeEmpty(inner_div.?)); // #text are empty
    try testing.expect(isNodeEmpty(inner_last_p.?)); // #text are empty

    const text1 = getTextContent(allocator, p.?);
    try testing.expectError(Err.EmptyTextContent, text1);

    // DIv is empty but contains whotespace like characters.
    const text2 = try getTextContent(allocator, div.?);
    defer allocator.free(text2);
    try testing.expect(text2.len == 4); // 3 ' ' and 1 '\n'

    const text3 = try getTextContent(allocator, inner_last_p.?);
    defer allocator.free(text3);
    try testing.expect(text3.len == 6);

    const p2 = try z.createTextNode(doc, "some text ");
    try testing.expect(z.isNodeEmpty(p2));
    const comment = try z.createComment(doc, "some comment");
    try testing.expect(z.isNodeEmpty(z.commentToNode(comment)));
}

//=============================================================================
// DOM NAVIGATION
//=============================================================================

/// [core] Get the parent node of a given node
pub fn parentNode(node: *z.DomNode) ?*z.DomNode {
    return lxb_dom_node_parent_noi(node);
}

/// [core] Get the parent element of a given element
pub fn parentElement(element: *z.DomElement) ?*z.DomElement {
    const node = elementToNode(element);
    const parent_node = parentNode(node);
    if (parent_node) |parent| {
        return nodeToElement(parent);
    }
    return null;
}

extern "c" fn lxb_dom_node_first_child_noi(node: *z.DomNode) ?*z.DomNode;
extern "c" fn lxb_dom_node_next_noi(node: *z.DomNode) ?*z.DomNode;

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
/// ### Example
/// ```
/// test "firstChild" {
///    const doc = try parseFromString("");
///    const body = try bodyNode(doc);
///    const text_node = try createTextNode(doc, "Hello, World!");
///    appendChild(body, text_node);
///
///    const first_child = firstChild(body);
///    try testing.expect(first_child == text_node);
///
///    const grandchild = firstChild(first_child.?);
///    try testing.expect(grandchild == null);
/// }
/// ```
pub fn firstChild(node: *z.DomNode) ?*z.DomNode {
    return lxb_dom_node_first_child_noi(node);
}

test "firstChild" {
    const doc = try parseFromString("");
    const body = try bodyNode(doc);
    const text_node = try createTextNode(doc, "Hello, World!");
    appendChild(body, text_node);

    const first_child = firstChild(body);

    try testing.expect(first_child == text_node);
    const grandchild = firstChild(first_child.?);
    try testing.expect(grandchild == null);
}

/// [core] Get first element child
///
/// Takes an element and returns the first child element, or null if none exists.
///
/// Skips non-element nodes such as text nodes, comments, etc.
pub fn firstElementChild(element: *z.DomElement) ?*z.DomElement {
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
        z.nodeNameBorrow(first_text.?),
    );

    const div = z.firstElementChild(nodeToElement(body).?);
    try testing.expectEqualStrings(
        "#element",
        z.nodeTypeName(elementToNode(div.?)),
    );
    try testing.expectEqualStrings(
        "DIV",
        z.tagNameBorrow(div.?),
    );
}

/// [core] Get next element sibling
///
/// Takes an element and returns the next sibling element, or null if none exists.
///
/// Skips non-element nodes such as text nodes, comments, etc.
pub fn nextElementSibling(element: *z.DomElement) ?*z.DomElement {
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
        if (z.parseTag(z.tagNameBorrow(current_elt.?)) == .div) {
            const first_child = z.firstChild(elementToNode(current_elt.?));
            try testing.expectEqualStrings(
                "#text",
                z.nodeTypeName(first_child.?),
            );
        }
        try testing.expectEqualStrings(
            elements[index],
            z.tagNameBorrow(current_elt.?),
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
pub fn getChildNodes(allocator: std.mem.Allocator, parent_node: *z.DomNode) ![]*z.DomNode {
    var nodes = std.ArrayList(*z.DomNode).init(allocator);

    var child = firstChild(parent_node);
    while (child != null) {
        try nodes.append(child.?);
        child = nextSibling(child.?);
    }

    return nodes.toOwnedSlice();
}

/// [core] Helper: Collect only element children from an element
///
/// (JavaScript convention: children)
///
/// Caller needs to free the slice
pub fn getChildren(allocator: std.mem.Allocator, parent_element: *z.DomElement) ![]*z.DomElement {
    var elements = std.ArrayList(*z.DomElement).init(allocator);

    var child = firstElementChild(parent_element);
    while (child != null) {
        try elements.append(child.?);
        child = nextElementSibling(child.?);
    }

    return elements.toOwnedSlice();
}

// ----------------------------------------------------------------------------------------
// Append
// ----------------------------------------------------------------------------------------

/// [core] Append a child node to parent
///
/// ## Example
/// ```
/// const parentNode: *z.DomNode = try bodyNode(doc);
/// const childNode: *z.DomNode = try createTextNode(doc, "Hello, World!");
/// appendChild(parentNode, childNode);
/// ```
pub fn appendChild(parent: *z.DomNode, child: *z.DomNode) void {
    lxb_dom_node_insert_child(parent, child);
}

/// [core] Append multiple child nodes to parent
///
/// ## Example
/// ```
/// const parentNode: *z.DomNode = try bodyNode(doc);
/// const child1: *z.DomElement = try createElement(doc, "div", &.{});
/// const div = elementToNode(child1);
/// const child2: *z.DomElement = try createElement(doc, "p", &.{});
/// const p = elementToNode(child2);
/// const childNodes: []const *z.DomNode = &.{div, p};
/// appendChildren(parentNode, childNodes);
/// ```
pub fn appendChildren(parent: *z.DomNode, child_nodes: []const *z.DomNode) void {
    for (child_nodes) |child| {
        appendChild(parent, child);
    }
}

test "appendChildren" {
    const doc = try parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const parentNodes = try bodyNode(doc);
    const child1 = try createElement(doc, "div", &.{});
    const div = elementToNode(child1);
    const child2 = try createElement(doc, "p", &.{});
    const p = elementToNode(child2);
    const childNodes: []const *z.DomNode = &.{ div, p };
    appendChildren(parentNodes, childNodes);
}

/// [core] Append all children from a document fragment to a parent node
///
///
/// The fragment children are moved (not copied)
pub fn appendFragment(parent: *z.DomNode, fragment: *z.DomNode) void {
    var fragment_child = firstChild(fragment);
    while (fragment_child != null) {
        const next_sibling = nextSibling(fragment_child.?);
        appendChild(parent, fragment_child.?);
        fragment_child = next_sibling;
    }
}

/// [utility] Tag name matcher function (safe: uses immediate comparison)
///
/// This is safe because it compares the tag name immediately without storing it.
pub fn matchesTagName(element: *z.DomElement, tag_name: []const u8) bool {
    const tag = tagNameBorrow(element); // Safe for immediate use
    return std.mem.eql(u8, tag, tag_name);
}

//=============================================================================
// TEXT CONTENT FUNCTIONS -
//=============================================================================

extern "c" fn lxb_dom_node_text_content(node: *z.DomNode, len: ?*usize) ?[*:0]u8;
extern "c" fn lxb_dom_node_text_content_set(node: *z.DomNode, content: [*]const u8, len: usize) u8;
extern "c" fn lxb_dom_character_data_replace(node: *z.DomNode, data: [*]const u8, len: usize, offset: usize, count: usize) u8;
extern "c" fn lexbor_destroy_text_wrapper(node: *z.DomNode, text: ?[*:0]u8) void; //<- ?????

/// [core] Get concatenated text content of a node. !! It is wrong to return an error if NULL. Change
///
/// It returns a concatenation of the text contents of all descendant text nodes or an error if none are found. !! This is wrong, should return NULL if NULL!!
///
/// Works on nodes (text, comment or element).
///
/// Caller needs to free the returned string
///
/// DEPRECATED: This API is incorrect - empty text content is not an error.
/// Use getTextContentOptional() for the correct behavior, or getTextContentOrEmpty() for JS-like behavior.
pub fn getTextContent(allocator: std.mem.Allocator, node: *z.DomNode) ![]u8 {
    var len: usize = 0;
    const text_ptr = lxb_dom_node_text_content(node, &len) orelse return Err.EmptyTextContent;

    defer lexbor_destroy_text_wrapper(node, text_ptr);

    if (len == 0) return Err.EmptyTextContent;

    const result = try allocator.alloc(u8, len);
    @memcpy(result, text_ptr[0..len]);
    return result;
}

/// [core] Get concatenated text content of a node as optional (CORRECT API)
///
/// Returns the concatenated text content of all descendant text nodes,
/// or null if the node has no text content (which is NOT an error).
///
/// Works on nodes (text, comment or element).
///
/// Caller needs to free the returned string if not null.
pub fn getTextContentOptional(allocator: std.mem.Allocator, node: *z.DomNode) !?[]u8 {
    var len: usize = 0;
    const text_ptr = lxb_dom_node_text_content(node, &len) orelse return null;

    defer lexbor_destroy_text_wrapper(node, text_ptr);

    if (len == 0) return null;

    const result = try allocator.alloc(u8, len);
    @memcpy(result, text_ptr[0..len]);
    return result;
}

/// [core] Get text content with empty string fallback (JavaScript-like behavior)
///
/// Returns the text content or an empty string if none exists.
/// This matches JavaScript's element.textContent behavior.
///
/// [core] Get text content with empty string fallback (JavaScript-like behavior)
///
/// Returns the text content or an empty string if none exists.
/// This matches JavaScript's element.textContent behavior.
///
/// Caller needs to free the returned string.
pub fn getTextContentOrEmpty(allocator: std.mem.Allocator, node: *z.DomNode) ![]u8 {
    if (try getTextContentOptional(allocator, node)) |content| {
        return content;
    }
    return allocator.dupe(u8, "");
}

/// [core] Get text content as zero-copy slice (FASTEST)
///
/// Returns a slice directly into lexbor's internal memory - no allocation!
///
/// **Use when:** Processing immediately, node lifetime is guaranteed
/// **Performance:** Fastest (direct pointer access), but lifetime-bound
///
/// ⚠️  **LIFETIME WARNING:** The returned slice is only valid while:
/// - The node remains in the DOM tree
/// - The document is not destroyed
/// - No DOM modifications that might cause internal reallocation
///
/// ```zig
/// if (getTextContentBorrow(node)) |text| {
///     // Use immediately - don't store for later!
///     processText(text);
/// }
/// ```
pub fn getTextContentBorrow(node: *z.DomNode) ?[]const u8 {
    var len: usize = 0;
    const text_ptr = lxb_dom_node_text_content(node, &len) orelse return null;

    if (len == 0) return null;

    return text_ptr[0..len];
}

/// [core] Set text content on a node
pub fn setTextContent(node: *z.DomNode, content: []const u8) !void {
    const status = lxb_dom_node_text_content_set(
        node,
        content.ptr,
        content.len,
    );
    if (status != z.LXB_STATUS_OK) return Err.SetTextContentFailed;
}

/// [core] set or replace text data on a text node
///
/// If the inner text node is void, it will be created.
/// If options.escape is true, the text will be HTML-escaped before insertion.
pub fn setOrReplaceText(allocator: std.mem.Allocator, node: *z.DomNode, text: []const u8, options: z.TextOptions) !void {
    // Apply HTML escaping if requested (for new user input)
    const final_text = if (options.escape)
        try escapeHtml(allocator, text)
    else
        text;
    defer if (options.escape) allocator.free(final_text);

    const inner_text_node = firstChild(node) orelse null;
    if (inner_text_node == null) {
        return try setTextContent(node, final_text);
    }

    const current_text = try getTextContent(
        allocator,
        node,
    );
    defer allocator.free(current_text);
    const status = lxb_dom_character_data_replace(
        inner_text_node.?,
        final_text.ptr,
        final_text.len,
        0, // Start at beginning
        current_text.len,
    );
    if (status != z.LXB_STATUS_OK) return Err.SetTextContentFailed;
}

/// [core] Get comment text content
///
/// Needs to be freed by caller
pub fn getCommentTextContent(allocator: std.mem.Allocator, comment: *z.Comment) ![]u8 {
    const inner_text = try getTextContent(
        allocator,
        commentToNode(comment),
    );
    return inner_text;
}

test "first text content & comment" {
    const allocator = testing.allocator;
    const doc = try parseFromString("<p>hello</p><br/><!--comment-->");
    const p = firstChild(try bodyNode(doc));
    const text = try getTextContent(allocator, p.?);
    defer allocator.free(text);
    try testing.expectEqualStrings("hello", text);
    const inner = z.firstChild(p.?);
    const inner_text = try getTextContent(allocator, inner.?);
    defer allocator.free(inner_text);
    try testing.expectEqualStrings("hello", inner_text);
    const br = elementToNode(nextElementSibling(nodeToElement(p.?).?).?);
    const br_text = getTextContent(allocator, br);
    try testing.expectError(Err.EmptyTextContent, br_text);
    const comment_node = nextSibling(br);
    const comment_text = try getTextContent(allocator, comment_node.?);
    try testing.expectEqualStrings("comment", comment_text);
    defer allocator.free(comment_text);
    const comment = nodeToComment(comment_node.?);
    const c_text = try getCommentTextContent(allocator, comment.?);
    defer allocator.free(c_text);
    try testing.expectEqualStrings("comment", c_text);
}

test "first set text content" {
    const allocator = testing.allocator;
    const doc = try parseFromString("<p></p><span>first</span>");
    const p = firstChild(try bodyNode(doc));
    const span = nextSibling(p.?).?;
    try setTextContent(p.?, "new text");
    try setTextContent(span, "second");

    const p_text = try getTextContent(allocator, p.?);
    defer allocator.free(p_text);
    try testing.expectEqualStrings("new text", p_text);
    const span_text = try getTextContent(allocator, span);
    defer allocator.free(span_text);
    try testing.expectEqualStrings("second", span_text);
}

/// Free lexbor-allocated memory ????
extern "c" fn lexbor_free(ptr: *anyopaque) void;

/// [core] HTML escape text content for safe output
///
/// Caller must free the returned slice.
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
pub fn walkElementChildren(parent_node: *z.DomNode, callback: fn (element: ?*z.DomElement) void) void {
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

pub fn isWhitespaceOnlyNode(node: *z.DomNode) bool {
    if (isSelfClosingNode(node)) return false; // Self-closing nodes are not considered whitespace-only
    if (isNodeEmpty(node)) return true;
    return false;
}

/// [core] Check if a node contains only whitespace.
/// However, the node can contain only whitespace text nodes.
/// The function `getNodeTextContentsOpts` can be used to retrieve all the text content recursively inside.
pub fn isWhitespaceOnlyElement(element: *z.DomElement) bool {
    const node = elementToNode(element);
    return isWhitespaceOnlyNode(node);
}

// =====================================================================
// Tests
// =====================================================================

test "memory safety: nodeName vs nodeNameOwned" {
    const allocator = std.testing.allocator;
    const doc = try createDocument();
    defer destroyDocument(doc);

    const element = try createElement(doc, "div", &.{});
    defer destroyNode(elementToNode(element));

    // Test immediate use (safe with both versions)
    const unsafe_name = tagNameBorrow(element);
    try testing.expectEqualStrings("DIV", unsafe_name);

    // Test owned version (safe for storage)
    const owned_name = try tagName(allocator, element);
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
    const name = tagNameBorrow(element);
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
    const comment_name = z.nodeNameBorrow(comment_node);
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
    const child_name = tagNameBorrow(nodeToElement(first_child).?);
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
    const doc = try parseFromString("");
    defer z.destroyDocument(doc);
    // // try z.printDocumentStructure(doc);
    const body_doc_node = try bodyNode(doc);
    const body_element = try bodyElement(doc);

    try testing.expectEqualStrings("BODY", tagNameBorrow(body_element));
    try testing.expectEqualStrings("BODY", z.nodeNameBorrow(body_doc_node));
}

test "children and childNodes" {
    const allocator = testing.allocator;
    const doc = try parseFromString("<html><body><div>text<p>para</p><!-- comment --><span>span</span></div></body></html>");
    defer destroyDocument(doc);

    const body = try bodyElement(doc);
    const div = firstElementChild(body).?;

    // Test children (only elements)
    const element_children = try getChildren(allocator, div);
    defer allocator.free(element_children);
    try testing.expect(element_children.len == 2); // p and span
    try testing.expectEqualStrings("P", tagNameBorrow(element_children[0]));
    try testing.expectEqualStrings("SPAN", tagNameBorrow(element_children[1]));

    // Test childNodes (all nodes including text and comments)
    const all_child_nodes = try getChildNodes(allocator, elementToNode(div));
    defer allocator.free(all_child_nodes);
    try testing.expect(all_child_nodes.len == 4); // text, p, comment, span

    // Verify legacy functions still work
    const legacy_children = try getChildren(allocator, div);
    defer allocator.free(legacy_children);
    try testing.expect(legacy_children.len == element_children.len);
}

test "consistency check" {
    const allocator = testing.allocator;
    const doc = try parseFromString("<html><body><div id='test' class='demo'>text<p>para</p><!-- comment --><span>span</span></div></body></html>");
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
    const element_children = try getChildren(allocator, div);
    defer allocator.free(element_children);
    try testing.expect(element_children.len == 2); // p and span only

    const all_child_nodes = try getChildNodes(allocator, elementToNode(div));
    defer allocator.free(all_child_nodes);
    try testing.expect(all_child_nodes.len == 4); // text, p, comment, span

    // Verify no legacy function usage
    try testing.expectEqualStrings("P", tagNameBorrow(element_children[0]));
    try testing.expectEqualStrings("SPAN", tagNameBorrow(element_children[1]));
}

test "createTextNode and appendChild" {
    const doc = try parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const div = try createElement(doc, "div", &.{});
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

test "createDocumentFragment" {
    const doc = try parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const fragment = try createDocumentFragment(doc);
    const p1 = try createElement(doc, "p", &.{});
    const p2 = try createElement(doc, "p", &.{});
    const text1 = try createTextNode(doc, "First paragraph");
    const text2 = try createTextNode(doc, "Second paragraph");

    appendChild(elementToNode(p1), text1);
    appendChild(elementToNode(p2), text2);
    appendChild(fragment, elementToNode(p1));
    appendChild(fragment, elementToNode(p2));

    const body_node = try bodyNode(doc);
    appendFragment(body_node, fragment);

    var p_count: usize = 0;
    var child = firstChild(body_node);
    while (child != null) {
        if (nodeToElement(child.?)) |element| {
            const tag_name = tagNameBorrow(element);
            if (std.mem.eql(u8, tag_name, "P")) {
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

    const body_node = try bodyNode(doc);

    const div1 = try createElement(doc, "div", &.{});
    const div2 = try createElement(doc, "div", &.{});
    const div3 = try createElement(doc, "div", &.{});

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
    const doc = try parseFromString("<html><body></body></html>");
    defer destroyDocument(doc);

    const body_node = try bodyNode(doc);

    const div1 = try createElement(doc, "div", &.{});
    const div2 = try createElement(doc, "p", &.{});
    const div3 = try createElement(doc, "span", &.{});

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
    // one way to create some nodes
    const doc = try parseFromString("<p>   </p>");
    defer destroyDocument(doc);
    const body = try bodyElement(doc);
    const body_node = elementToNode(body);
    const p = firstChild(body_node);

    try testing.expect(
        isWhitespaceOnlyNode(p.?),
    );

    // inner text node is whitespace-only
    const inner_text_node = firstChild(p.?);
    try testing.expect(
        z.isTypeText(inner_text_node.?),
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
    const body = try bodyElement(doc);
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
    const txt = try getTextContent(allocator, div);
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
    try setOrReplaceText(allocator, node, "Initial text", .{});

    const initial_text = try getTextContent(allocator, node);
    defer allocator.free(initial_text);
    try testing.expectEqualStrings("Initial text", initial_text);

    try setOrReplaceText(allocator, node, "Updated text", .{});

    const updated_text = try getTextContent(allocator, node);
    defer allocator.free(updated_text);
    try testing.expectEqualStrings("Updated text", updated_text);
}

test "create Html element, parseTag, custom element" {
    const doc = try z.parseFromString("<p></p>");
    const body_node = try bodyNode(doc);

    const span_element = try createElement(doc, "span", &.{});
    const tag = tagNameBorrow(span_element);
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
    const custom_tag = (tagNameBorrow(custom_elt));
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
            const element_name = tagNameBorrow(element);
            if (std.mem.eql(u8, element_name, "CUSTOM-ELEMENT")) {
                found_custom = true;
                break;
            }
        }
        child = nextSibling(child.?);
    }
    try testing.expect(found_custom);

    const allocator = std.testing.allocator;
    const text = try z.serializeToString(allocator, body_node);
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
            const element_name = tagNameBorrow(element);
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

test "get & set NodeTextContent and escape option" {
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

    const text_content = try getTextContent(
        allocator,
        node,
    );
    defer allocator.free(text_content);

    try testing.expectEqualStrings("Hello, world!", text_content);

    const options = z.TextOptions{ .escape = true };
    try setOrReplaceText(allocator, node, "<script>alert('xss')</script> & \"quotes\"", options);

    const new_escaped_text = try getTextContent(
        allocator,
        node,
    );
    defer allocator.free(new_escaped_text);
    try testing.expectEqualStrings("&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt; &amp; &quot;quotes&quot;", new_escaped_text);
}

test "gets all text elements from Fragment" {
    const fragment = "<div><p>First<span>Second</span></p><p>Third</p></div><div><ul><li>Fourth</li><li>Fifth</li></ul></div>";

    const allocator = testing.allocator;
    const doc = try parseFromString(fragment);
    defer destroyDocument(doc);
    const body_element = try bodyElement(doc);
    const body_node = elementToNode(body_element);
    const text_content = try getTextContent(allocator, body_node);
    defer allocator.free(text_content);
    try testing.expectEqualStrings("FirstSecondThirdFourthFifth", text_content);
}

test "text content" {
    const allocator = testing.allocator;

    const html = "<p>Hello <strong>World</strong>!</p>";
    const doc = try parseFromString(html);
    defer destroyDocument(doc);

    const body = try bodyElement(doc);
    const body_node = elementToNode(body);
    const p_node = firstChild(body_node).?;
    const text = try getTextContent(
        allocator,
        p_node,
    );
    defer allocator.free(text);

    try testing.expectEqualStrings("Hello World!", text);
    const text_node = firstChild(p_node);
    const strong_node = nextSibling(text_node.?);
    const strong_text = try getTextContent(
        allocator,
        strong_node.?,
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

    const body_element = try bodyElement(doc);
    const body_node = elementToNode(body_element);

    const first_child = firstChild(body_node);
    const second_child = nextSibling(first_child.?);

    const all_text = try getTextContent(
        allocator,
        body_node,
    );
    const first_text = try getTextContent(
        allocator,
        first_child.?,
    );
    const second_text = try getTextContent(
        allocator,
        second_child.?,
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
        // print("{s}\n", .{tagNameBorrow(child.?)});
        try testing.expect(isNodeEmpty(elementToNode(child)));
    }
}

test "Append JS fragment" {
    const allocator = testing.allocator;

    const doc = try parseFromString("<html><body></body></html>");
    const body_node = try bodyNode(doc);

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

    const fragment_txt = try z.serializeToString(
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

    // Instead of using normalizeWhitespace (which was for text nodes),
    // use the new lexbor-based approach for accurate HTML comparison

    const options = z.TextOptions{};
    // const start2 = try Instant.now();
    const expected_html2 = try z.normalizeWhitespace(allocator, pretty_html, options);
    defer allocator.free(expected_html2);
    // const end2 = try Instant.now();
    // const elapsed2: f64 = @floatFromInt(end2.since(start2));
    // print("Time elapsed is: {d:.3}ms\n", .{
    // elapsed2 / time.ns_per_ms,
    // });

    const expected =
        "<div class=\"container-list\"><!--a comment--><ul><li data-id=\"1\">Item 1</li><li data-id=\"2\">Item 2</li><li data-id=\"3\">Item 3</li></ul></div>";

    try testing.expectEqualStrings(
        expected,
        expected_html2,
    );
    try testing.expectEqualStrings(
        expected_html2, // Use expected_html instead of expected
        fragment_txt,
    );
    try testing.expectEqualStrings(expected_html2, fragment_txt);
    try testing.expectEqualStrings(expected_html2, fragment_txt);

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

    // try z.printDocumentStructure(doc);

    const tree = try z.documentToTupleTree(allocator, doc);
    defer z.freeHtmlTree(allocator, tree);

    for (tree, 0..) |node, i| {
        _ = i;
        _ = node;
        // print("[{}]: ", .{i});
        // z.printNode(node, 0);
    }

    const json_tree = try z.documentToJsonTree(allocator, doc);
    defer z.freeJsonTree(allocator, json_tree);
    const json_string = try z.jsonNodeToString(allocator, json_tree[0]);
    defer allocator.free(json_string);
    // print("\n\n{s}\n", .{json_string});
}

test "JavaScript children from fragment" {
    const frag = "<div><span></span><p></p></div>";
    const allocator = std.testing.allocator;
    const doc = try parseFromString(frag);
    defer destroyDocument(doc);

    const body_element = try bodyElement(doc);
    const body_node = elementToNode(body_element);
    try testing.expectEqualStrings("BODY", z.nodeNameBorrow(body_node));

    const children1 = try getChildNodes(allocator, body_node);
    defer allocator.free(children1);
    try testing.expect(children1.len == 1); // Only one child <div>
    try testing.expect(!isNodeEmpty(body_node)); // DIV contains SPAN and P elements

    const div_element = nodeToElement(children1[0]).?;
    const children2 = try getChildren(allocator, div_element);
    defer allocator.free(children2);
    try testing.expectEqualStrings(tagNameBorrow(children2[0]), "SPAN");

    try testing.expectEqualStrings(tagNameBorrow(children2[1]), "P");

    for (children2) |child| {
        // print("{s}\n", .{tagNameBorrow(child.?)});
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

    const body = try bodyElement(doc);
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
            const tag_name = z.nodeNameBorrow(child.?);
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

    const body_node = try z.bodyNode(doc);
    var child = z.firstChild(body_node);

    // Test hasClass function and compare with existing classList
    while (child != null) {
        if (z.nodeToElement(child.?)) |element| {
            const element_name = z.tagNameBorrow(element);
            if (std.mem.eql(u8, element_name, "div")) {
                const text_content = try z.getTextContent(allocator, child.?);
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

    const body_node = try z.bodyNode(doc);

    // Test CSS selector for second li
    var engine = try z.CssSelectorEngine.init(allocator);
    defer engine.deinit();

    // Find the second li element using nth-child
    const second_li_results = try engine.querySelectorAll(body_node, "ul > li:nth-child(2)");
    defer allocator.free(second_li_results);

    try testing.expect(second_li_results.len == 1);

    if (second_li_results.len > 0) {
        const second_li_node = second_li_results[0];
        const text_content = try z.getTextContent(allocator, second_li_node);
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
        const text_content = try z.getTextContent(allocator, node);
        defer allocator.free(text_content);
        try testing.expect(std.mem.eql(u8, std.mem.trim(u8, text_content, " \t\n\r"), "First item"));
    } else {
        try testing.expect(false); // Should find first li
    }
}

test "show" {
    const allocator = testing.allocator;

    const doc = try parseFromString("");
    defer z.destroyDocument(doc);

    const body_node = try bodyNode(doc);

    const fragment = try z.createDocumentFragment(doc);
    // defer destroyNode(fragment);

    const div_elt = try z.createElement(
        doc,
        "div",
        &.{.{ .name = "class", .value = "container-list" }},
    );

    const div = elementToNode(div_elt);
    // defer destroyNode(div);

    const comment_node = try z.createComment(doc, "a comment");
    // defer destroyComment(comment_node);
    z.appendChild(div, commentToNode(comment_node));

    const ul_elt = try z.createElement(doc, "ul", &.{});
    const ul = elementToNode(ul_elt);
    // defer destroyNode(ul);

    for (1..4) |i| {
        const inner_content = try std.fmt.allocPrint(
            allocator,
            "<li data-id=\"{d}\">Item {d}</li>",
            .{ i, i },
        );
        defer allocator.free(inner_content);

        const temp_div_elt = try createElement(doc, "div", &.{});
        const temp_div = elementToNode(temp_div_elt);

        _ = try z.setInnerHTML(
            allocator,
            temp_div_elt,
            inner_content,
            .{},
        );

        // Move the LI element to the UL
        if (firstChild(temp_div)) |li| {
            appendChild(ul, li);
        }
        destroyNode(temp_div);
    }

    // for (1..4) |i| {
    // Convert integer to ASCII digit
    //     const digit_char = @as(u8, @intCast(i)) + '0';
    //     const value_str = &[_]u8{digit_char};

    //    const li = try z.createElement(
    //       doc,
    //       "li",
    //        &.{.{ .name = "data-id", .value = value_str }},
    //     );

    //     const li_node = elementToNode(li);

    //     const text_content = try std.fmt.allocPrint(
    //       testing.allocator,
    //       "Item {d}",
    //       .{i},
    //     );
    //     defer allocator.free(text_content);

    //     const text_node = try z.createTextNode(doc, text_content);
    //     z.appendChild(li_node, text_node);
    //     z.appendChild(ul_node, li_node);
    // }

    z.appendChild(div, ul);
    z.appendChild(fragment, div);

    // batch it into the DOM
    z.appendFragment(body_node, fragment);

    const lis = try z.getElementsByTagName(doc, "LI");
    defer if (lis) |collection| {
        z.destroyCollection(collection);
    };
    const li_count = z.collectionLength(lis.?);
    try testing.expect(li_count == 3);

    const fragment_txt = try z.serializeToString(allocator, div);
    // print("\n\n{s}\n\n", .{fragment_txt});

    defer allocator.free(fragment_txt);

    const pretty_expected =
        \\<div class="container-list">
        \\  <!--a comment-->
        \\  <ul>
        \\      <li data-id="1">Item 1</li>
        \\      <li data-id="2">Item 2</li>
        \\      <li data-id="3">Item 3</li>
        \\  </ul>
        \\</div>
    ;

    const expected = try z.normalizeWhitespace(allocator, pretty_expected, .{});
    defer allocator.free(expected);

    try testing.expectEqualStrings(expected, fragment_txt);
}

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

test "practical string-to-DOM scenarios" {
    const allocator = testing.allocator;

    // print("\n=== Practical String-to-DOM Scenarios ===\n", .{});

    // Scenario 1: Full page parsing with parseFromString
    // print("\n1. Full HTML Document Parsing:\n", .{});
    const full_page =
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>My Page</title></head>
        \\<body>
        \\  <h1>Welcome</h1>
        \\  <p>Content here</p>
        \\</body>
        \\</html>
    ;

    const doc = try parseFromString(full_page);
    defer destroyDocument(doc);

    const body = try bodyElement(doc);
    const page_content = try z.serializeElement(allocator, body);
    defer allocator.free(page_content);

    // print("   Use case: Loading complete HTML documents\n", .{});
    // print("   Result: '{s}'\n", .{page_content});

    // Scenario 2: Template fragment insertion with setInnerHTML
    // print("\n2. Dynamic Content Insertion:\n", .{});
    const template_doc = try parseFromString("<html><body><div id='content'></div></body></html>");
    defer destroyDocument(template_doc);

    const content_div = try z.getElementById(template_doc, "content");

    // Simulate user data
    const user_data = [_]struct { name: []const u8, email: []const u8 }{
        .{ .name = "Alice", .email = "alice@example.com" },
        .{ .name = "Bob", .email = "bob@example.com" },
    };

    // Build user list dynamically
    var user_list = std.ArrayList(u8).init(allocator);
    defer user_list.deinit();

    try user_list.appendSlice("<ul>");
    for (user_data) |user| {
        const user_item = try std.fmt.allocPrint(allocator, "<li><strong>{s}</strong> - {s}</li>", .{ user.name, user.email });
        defer allocator.free(user_item);

        try user_list.appendSlice(user_item);
    }
    try user_list.appendSlice("</ul>");

    // Insert the generated HTML
    _ = try z.setInnerHTML(allocator, content_div.?, user_list.items, .{ .allow_html = true });

    const dynamic_result = try z.serializeElement(allocator, content_div.?);
    defer allocator.free(dynamic_result);

    // print("   Use case: Dynamic content generation and insertion\n", .{});
    // print("   Result: '{s}'\n", .{dynamic_result});

    // Scenario 3: Fragment parsing for reusable components
    // print("\n3. Component Fragment Parsing:\n", .{});
    const components = [_][]const u8{
        "<button class='btn btn-primary'>Click me</button>",
        "<input type='email' placeholder='Enter email' required>",
        "<div class='alert alert-info'>Information message</div>",
    };

    const app_doc = try parseFromString("<html><body><div id='app'></div></body></html>");
    defer destroyDocument(app_doc);

    const app_div = try z.getElementById(app_doc, "app");

    // Add each component to the app
    for (components, 0..) |component, i| {
        const current_content = try z.innerHTML(allocator, app_div.?);
        defer allocator.free(current_content);

        const updated_content = try std.fmt.allocPrint(allocator, "{s}<div class='component-{d}'>{s}</div>", .{ current_content, i, component });
        defer allocator.free(updated_content);

        _ = try z.setInnerHTML(allocator, app_div.?, updated_content, .{ .allow_html = true });

        // print("   Added component {d}: {s}\n", .{ i + 1, component });
    }

    const app_result = try z.serializeElement(allocator, app_div.?);
    defer allocator.free(app_result);

    // print("   Final app: '{s}'\n", .{app_result});

    // print("\n=== Summary ===\n", .{});
    // print("• parseFromString: Creates complete documents, handles DOCTYPE, etc.\n", .{});
    // print("• setInnerHTML: Injects HTML fragments into existing elements\n", .{});
    // print("• Both convert strings to DOM, but serve different use cases\n", .{});
}
