const std = @import("std");

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
pub const lxb_status_t = c_uint;
pub const LXB_STATUS_OK: lxb_status_t = 0;

// Errors
pub const LexborError = error{
    DocCreateFailed,
    ParseFailed,
    CreateElementFailed,
    FragmentParseFailed,
    InsertChildFailed,
    CollectionFailed,
    SearchFailed,
};

//=============================================================================
// CORE DOCUMENT FUNCTIONS
//=============================================================================

pub extern "c" fn lxb_html_document_create() ?*lxb_html_document_t;
pub extern "c" fn lxb_html_document_destroy(doc: *lxb_html_document_t) void;
pub extern "c" fn lxb_html_document_parse(doc: *lxb_html_document_t, html: [*]const u8, len: usize) lxb_status_t;

/// Create a new HTML document
pub fn createDocument() !*lxb_html_document_t {
    return lxb_html_document_create() orelse LexborError.DocCreateFailed;
}

/// Parse HTML into document
pub fn parseDocument(doc: *lxb_html_document_t, html: []const u8) !void {
    const status = lxb_html_document_parse(doc, html.ptr, html.len);
    if (status != LXB_STATUS_OK) return LexborError.ParseFailed;
}

/// Parse HTML string into new document (convenience function)
pub fn parseHtml(html: []const u8) !*lxb_html_document_t {
    const doc = try createDocument();
    parseDocument(doc, html) catch |err| {
        lxb_html_document_destroy(doc);
        return err;
    };
    return doc;
}

//=============================================================================
// C WRAPPER FUNCTIONS (for macros/inline functions)
//=============================================================================

extern "c" fn lexbor_dom_interface_node_wrapper(obj: *anyopaque) *lxb_dom_node_t;
extern "c" fn lexbor_dom_interface_element_wrapper(node: *lxb_dom_node_t) ?*lxb_dom_element_t;
extern "c" fn lexbor_get_body_element_wrapper(doc: *lxb_html_document_t) ?*lxb_dom_element_t;
extern "c" fn lexbor_collection_make_wrapper(doc: *lxb_html_document_t, size: usize) ?*lxb_dom_collection_t;
extern "c" fn lexbor_create_dom_element(doc: *lxb_html_document_t, tag_name: [*]const lxb_char_t, tag_len: usize) ?*lxb_dom_element_t;

//=========================================================
// DOM NAVIGATION FUNCTIONS - Check which ones actually exist
//=============================================================================

/// Get first child - confirmed to exist
pub extern "c" fn lxb_dom_node_first_child_noi(node: *lxb_dom_node_t) ?*lxb_dom_node_t;

/// Get next sibling - confirmed to exist
pub extern "c" fn lxb_dom_node_next_noi(node: *lxb_dom_node_t) ?*lxb_dom_node_t;

/// Get node name - this one works directly
pub extern "c" fn lxb_dom_node_name(node: *lxb_dom_node_t, len: ?*usize) [*:0]const lxb_char_t;

/// Insert child - IMPORTANT: returns void, not status!
pub extern "c" fn lxb_dom_node_insert_child(parent: *lxb_dom_node_t, child: *lxb_dom_node_t) void;

//=============================================================================
// FRAGMENT PARSING
//=============================================================================

extern "c" fn lexbor_parse_fragment_as_document(html: [*]const lxb_char_t, html_len: usize) ?*lxb_html_document_t;

/// Parse HTML fragment as a standalone document
pub fn parseFragmentAsDocument(fragment: []const u8) !*lxb_html_document_t {
    return lexbor_parse_fragment_as_document(fragment.ptr, fragment.len) orelse LexborError.FragmentParseFailed;
}

//=============================================================================
// TYPE CONVERSION FUNCTIONS
//=============================================================================

/// Convert any lexbor object to DOM node
pub fn objectToNode(obj: *anyopaque) *lxb_dom_node_t {
    return lexbor_dom_interface_node_wrapper(obj);
}

/// Convert DOM node to element (if it is one)
pub fn nodeToElement(node: *lxb_dom_node_t) ?*lxb_dom_element_t {
    return lexbor_dom_interface_element_wrapper(node);
}

/// Convert DOM element to node
pub fn elementToNode(element: *lxb_dom_element_t) *lxb_dom_node_t {
    return objectToNode(element);
}

/// Get document as DOM node for navigation
pub fn getDocumentNode(doc: *lxb_html_document_t) *lxb_dom_node_t {
    return objectToNode(doc);
}

//=============================================================================
// HIGH-LEVEL DOM ACCESS
//=============================================================================

/// Create a DOM element in the document
pub fn createElement(doc: *lxb_html_document_t, tag_name: []const u8) !*lxb_dom_element_t {
    return lexbor_create_dom_element(doc, tag_name.ptr, tag_name.len) orelse LexborError.CreateElementFailed;
}

/// Get the document's body element
pub fn getBodyElement(doc: *lxb_html_document_t) ?*lxb_dom_element_t {
    return lexbor_get_body_element_wrapper(doc);
}

//=============================================================================
// DOM NAVIGATION
//=============================================================================

/// Get first child of node
pub fn getFirstChild(node: *lxb_dom_node_t) ?*lxb_dom_node_t {
    return lxb_dom_node_first_child_noi(node);
}

/// Get next sibling of node
pub fn getNextSibling(node: *lxb_dom_node_t) ?*lxb_dom_node_t {
    return lxb_dom_node_next_noi(node);
}

/// Get node's tag name as Zig string
pub fn getNodeName(node: *lxb_dom_node_t) []const u8 {
    const name_ptr = lxb_dom_node_name(node, null);
    return std.mem.span(name_ptr);
}

/// Insert child node into parent - no error handling needed since it returns void
pub fn insertChild(parent: *lxb_dom_node_t, child: *lxb_dom_node_t) void {
    lxb_dom_node_insert_child(parent, child); // No status to check!
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
        std.debug.print("{s}{s}\n", .{ indent, name });

        walkTree(child.?, depth + 1);
        child = getNextSibling(child.?);
    }
}

/// Print document structure (for debugging)
pub fn printDocumentStructure(doc: *lxb_html_document_t) void {
    std.debug.print("=== DOCUMENT STRUCTURE ===\n", .{});
    const root = getDocumentNode(doc);
    walkTree(root, 0);
    std.debug.print("=== END STRUCTURE ===\n", .{});
}

/// Parse and display fragment (for testing)
pub fn demonstrateFragmentParsing(fragment: []const u8) !void {
    std.debug.print("Parsing fragment: {s}\n", .{fragment});

    const frag_doc = try parseFragmentAsDocument(fragment);
    defer lxb_html_document_destroy(frag_doc);

    std.debug.print("Fragment parsed successfully!\n", .{});

    if (getBodyElement(frag_doc)) |body| {
        const body_node = elementToNode(body);
        walkTree(body_node, 0);
    }
}
