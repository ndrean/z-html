const std = @import("std");

const testing = std.testing;
const Print = std.debug.print;

//=============================================================================
// TYPES AND CONSTANTS
//=============================================================================

// Opaque types
pub const lxb_html_document_t = opaque {};
pub const lxb_dom_node_t = opaque {};
pub const lxb_dom_element_t = opaque {};
pub const lxb_dom_collection_t = opaque {};
pub const lxb_dom_attr_t = opaque {};

// Lexbor types
pub const lxb_char_t = u8;
pub const lxb_status_t = usize;
pub const LXB_STATUS_OK: usize = 0;

const SliceU8 = []const u8;

// Aliases for lexbor pointers
pub const HtmlDocumentPtr = *lxb_html_document_t;
pub const DomNodePtr = *lxb_dom_node_t;
pub const DomElementPtr = *lxb_dom_element_t;
pub const DomCollectionPtr = *lxb_dom_collection_t;
pub const DomAttrPtr = *lxb_dom_attr_t;

pub const OptionalDomNodePtr = ?*lxb_dom_node_t;
pub const OptionalDomElementPtr = ?*lxb_dom_element_t;
pub const OptionalHtmlDocumentPtr = ?*lxb_html_document_t;
pub const OptionalDomCollectionPtr = ?*lxb_dom_collection_t;

pub const LexborError = error{
    DocCreateFailed,
    ParseFailed,
    CreateElementFailed,
    FragmentParseFailed,
    InsertChildFailed,
    CollectionFailed,
    SearchFailed,
    NotANode,
    NotAnElement,
    NoNode,
    EmptyTextContent,
    SetTextContentFailed,
};

//=============================================================================
// CORE DOCUMENT FUNCTIONS
//=============================================================================

extern "c" fn lxb_html_document_create() OptionalHtmlDocumentPtr;
extern "c" fn lxb_html_document_destroy(doc: HtmlDocumentPtr) void;
extern "c" fn lxb_html_document_parse(doc: HtmlDocumentPtr, html: [*]const u8, len: usize) usize;

/// Create a new HTML document
pub fn createDocument() !HtmlDocumentPtr {
    return lxb_html_document_create() orelse LexborError.DocCreateFailed;
}

pub fn destroyDocument(doc: HtmlDocumentPtr) void {
    lxb_html_document_destroy(doc);
}

/// Parse HTML into document
pub fn parseLxbDocument(doc: HtmlDocumentPtr, html: SliceU8) !void {
    const status = lxb_html_document_parse(doc, html.ptr, html.len);
    if (status != LXB_STATUS_OK) return LexborError.ParseFailed;
}

/// Parse HTML string into new document (convenience function)
pub fn parseHtml(html: SliceU8) !HtmlDocumentPtr {
    const doc = try createDocument();
    parseLxbDocument(doc, html) catch |err| {
        lxb_html_document_destroy(doc);
        return err;
    };
    return doc;
}

//=============================================================================
// C WRAPPER FUNCTIONS (for macros/inline functions)
//=============================================================================

extern "c" fn lexbor_dom_interface_node_wrapper(obj: *anyopaque) DomNodePtr;
extern "c" fn lexbor_dom_interface_element_wrapper(node: DomNodePtr) OptionalDomElementPtr;
extern "c" fn lexbor_get_body_element_wrapper(doc: HtmlDocumentPtr) OptionalDomElementPtr;
extern "c" fn lexbor_collection_make_wrapper(doc: HtmlDocumentPtr, size: usize) OptionalDomCollectionPtr;
extern "c" fn lexbor_create_dom_element(doc: HtmlDocumentPtr, tag_name: [*]const u8, tag_len: usize) OptionalDomElementPtr;

//=========================================================
// DOM NAVIGATION FUNCTIONS - Check which ones actually exist
//=============================================================================

/// Get first child - confirmed to exist
extern "c" fn lxb_dom_node_first_child_noi(node: DomNodePtr) OptionalDomNodePtr;

/// Get next sibling - confirmed to exist
extern "c" fn lxb_dom_node_next_noi(node: DomNodePtr) OptionalDomNodePtr;

/// Get node name - this one works directly
extern "c" fn lxb_dom_node_name(node: DomNodePtr, len: ?*usize) [*:0]const u8;

/// Insert child - IMPORTANT: returns void, not status!
extern "c" fn lxb_dom_node_insert_child(parent: DomNodePtr, child: DomNodePtr) void;

//=============================================================================
// FRAGMENT PARSING
//=============================================================================

extern "c" fn lexbor_parse_fragment_as_document(html: [*]const u8, html_len: usize) OptionalHtmlDocumentPtr;

/// Parse HTML fragment as a standalone document
pub fn parseFragmentAsDocument(fragment: SliceU8) !HtmlDocumentPtr {
    return lexbor_parse_fragment_as_document(fragment.ptr, fragment.len) orelse LexborError.FragmentParseFailed;
}

//=============================================================================
// TYPE CONVERSION FUNCTIONS
//=============================================================================

/// Destroy a DOM node
extern "c" fn lxb_dom_node_destroy(node: DomNodePtr) void;

/// Destroy a DOM node - wrapper for C function
pub fn destroyNode(node: DomNodePtr) void {
    lxb_dom_node_destroy(node);
}

/// Convert any lexbor object to DOM node
pub fn objectToNode(obj: *anyopaque) DomNodePtr {
    return lexbor_dom_interface_node_wrapper(obj);
}

/// Convert DOM node to Element (if it is one)
pub fn nodeToElement(node: DomNodePtr) OptionalDomElementPtr {
    return lexbor_dom_interface_element_wrapper(node);
}

/// Convert DOM Element to Node
pub fn elementToNode(element: DomElementPtr) DomNodePtr {
    return objectToNode(element);
}

/// Get document as DOM node for navigation
pub fn getDocumentNode(doc: HtmlDocumentPtr) DomNodePtr {
    return objectToNode(doc);
}

//=============================================================================
// HIGH-LEVEL DOM ACCESS
//=============================================================================

/// Create a DOM element in the document
pub fn createElement(doc: HtmlDocumentPtr, tag_name: SliceU8) !DomElementPtr {
    return lexbor_create_dom_element(doc, tag_name.ptr, tag_name.len) orelse LexborError.CreateElementFailed;
}

// lxb_dom_document_create_comment(lxb_dom_document_t *document, const lxb_char_t *data, size_t len)

/// Get the document's body element
pub fn getBodyElement(doc: HtmlDocumentPtr) OptionalDomElementPtr {
    return lexbor_get_body_element_wrapper(doc);
}

test "create element" {
    const doc = try createDocument();
    defer destroyDocument(doc);
    const element = try createElement(doc, "div");
    defer destroyNode(elementToNode(element));
    const name = try getElementName(element);
    try testing.expectEqualStrings("DIV", name);
}

test "check error get body of empty element" {
    const doc = try createDocument();
    defer destroyDocument(doc);
    const body_element = getBodyElement(doc) orelse
        LexborError.EmptyTextContent;

    try testing.expectError(LexborError.EmptyTextContent, body_element);
}

// test "get body element" {
//     const doc = try createDocument();
//     defer destroyDocument(doc);
//     const body_element = getBodyElement(doc) orelse
//         LexborError.EmptyTextContent;

//     Print("{any}", .{body_element});
//     // testing.expect(body_element != null);
// }

//=============================================================================
// DOM NAVIGATION
//=============================================================================

/// Get first child of node
pub fn getFirstChild(node: DomNodePtr) OptionalDomNodePtr {
    return lxb_dom_node_first_child_noi(node);
}

/// Get next sibling of node
pub fn getNextSibling(node: DomNodePtr) OptionalDomNodePtr {
    return lxb_dom_node_next_noi(node);
}

/// Get node's tag name as Zig string
pub fn getNodeName(node: DomNodePtr) SliceU8 {
    const name_ptr = lxb_dom_node_name(node, null);
    return std.mem.span(name_ptr);
}

/// Get element's tag name as Zig string
pub fn getElementName(element: DomElementPtr) !SliceU8 {
    const node = elementToNode(element);
    return getNodeName(node);
    // return name;
}

/// Insert child node into parent - no error handling needed since it returns void
pub fn insertChild(parent: DomNodePtr, child: DomNodePtr) void {
    lxb_dom_node_insert_child(parent, child); // No status to check!
}

test "getElementName" {
    const doc = try createDocument();
    defer destroyDocument(doc);
    const element = try createElement(doc, "div");
    defer destroyNode(elementToNode(element));
    // lxb.printDocumentStructure(doc);
    const name = try getElementName(element);
    try testing.expectEqualStrings("DIV", name);
}

test "getNodeName" {
    const fragment = "<div></div><p></p>";
    const doc = try parseFragmentAsDocument(fragment);
    defer destroyDocument(doc);

    const doc_node = getDocumentNode(doc);
    try testing.expectEqualStrings(getNodeName(doc_node), "#document");
    const body_element = getBodyElement(doc);
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
    const child_name = try getElementName(nodeToElement(first_child).?);
    try testing.expectEqualStrings("SPAN", child_name);
}

//=============================================================================
// TEXT CONTENT FUNCTIONS -
//=============================================================================

/// Get text content of a node (returns allocated string)
/// WARNING: You must free the returned string with lexbor_free()
extern "c" fn lxb_dom_node_text_content(node: DomNodePtr, len: ?*usize) ?[*:0]lxb_char_t;

/// Set text content of a node
extern "c" fn lxb_dom_node_text_content_set(node: DomNodePtr, content: [*]const lxb_char_t, len: usize) lxb_status_t;

/// Check if node is empty (only whitespace)
extern "c" fn lxb_dom_node_is_empty(node: DomNodePtr) bool;

/// Free lexbor-allocated memory
extern "c" fn lexbor_free(ptr: *anyopaque) void;

/// Get text content as Zig string (copies to Zig-managed memory)
pub fn getNodeTextContent(allocator: std.mem.Allocator, node: DomNodePtr) ![]u8 {
    var len: usize = 0;
    const text_ptr = lxb_dom_node_text_content(node, &len);

    if (len == 0) {
        Print("Text content length is 0\n", .{});
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
pub fn setNodeTextContent(node: DomNodePtr, content: []const u8) !void {
    const status = lxb_dom_node_text_content_set(node, content.ptr, content.len);
    if (status != LXB_STATUS_OK) return LexborError.SetTextContentFailed;
}

/// Check if node contains only whitespace
pub fn isNodeEmpty(node: DomNodePtr) bool {
    return lxb_dom_node_is_empty(node);
}

test "get & set NodeTextContent & empty node" {
    const allocator = std.testing.allocator;
    const doc = try createDocument();
    const element = try createElement(doc, "div");
    defer destroyDocument(doc);
    const node = elementToNode(element);

    try testing.expectError(
        error.EmptyTextContent,
        getNodeTextContent(allocator, node),
    );

    try setNodeTextContent(node, "Hello, world!");

    const text_content = try getNodeTextContent(allocator, node);
    defer allocator.free(text_content);

    try testing.expectEqualStrings("Hello, world!", text_content);
}

test "get all text elements from Fragment" {
    const fragment = "<div><p>First<span>Second</span></p><p>Third</p></div><div><ul><li>Fourth</li><li>Fifth</li></ul></div>";

    const allocator = testing.allocator;
    const doc = try parseFragmentAsDocument(fragment);
    defer destroyDocument(doc);
    const body_element = getBodyElement(doc);
    // orelse LexborError.EmptyTextContent;

    const body_node = elementToNode(body_element.?);
    const text_content = try getNodeTextContent(allocator, body_node);
    defer allocator.free(text_content);
    try testing.expectEqualStrings("FirstSecondThirdFourthFifth", text_content);
}

//=============================================================================
// UTILITY FUNCTIONS
//=============================================================================

/// Walk and print DOM tree (for debugging)
pub fn walkTree(node: *lxb_dom_node_t, depth: u32) void {
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
        Print("{s}{s}\n", .{ indent, name });

        walkTree(child.?, depth + 1);
        child = getNextSibling(child.?);
    }
}

/// Print document structure (for debugging)
pub fn printDocumentStructure(doc: HtmlDocumentPtr) void {
    Print("\n--- DOCUMENT STRUCTURE ----\n", .{});
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
