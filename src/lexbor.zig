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
};

//=============================================================================
// CORE DOCUMENT FUNCTIONS
//=============================================================================

pub extern "c" fn lxb_html_document_create() OptionalHtmlDocumentPtr;
pub extern "c" fn lxb_html_document_destroy(doc: HtmlDocumentPtr) void;
pub extern "c" fn lxb_html_document_parse(doc: HtmlDocumentPtr, html: [*]const u8, len: usize) usize;

/// Create a new HTML document
pub fn createDocument() !HtmlDocumentPtr {
    return lxb_html_document_create() orelse LexborError.DocCreateFailed;
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
pub extern "c" fn lxb_dom_node_first_child_noi(node: DomNodePtr) OptionalDomNodePtr;

/// Get next sibling - confirmed to exist
pub extern "c" fn lxb_dom_node_next_noi(node: DomNodePtr) OptionalDomNodePtr;

/// Get node name - this one works directly
pub extern "c" fn lxb_dom_node_name(node: DomNodePtr, len: ?*usize) [*:0]const u8;

/// Insert child - IMPORTANT: returns void, not status!
pub extern "c" fn lxb_dom_node_insert_child(parent: DomNodePtr, child: DomNodePtr) void;

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

/// Get the document's body element
pub fn getBodyElement(doc: HtmlDocumentPtr) OptionalDomElementPtr {
    return lexbor_get_body_element_wrapper(doc);
}

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
pub fn getNodeName(node: DomNodePtr) !SliceU8 {
    const name_ptr = lxb_dom_node_name(node, null); // orelse LexborError.NotANode;
    return std.mem.span(name_ptr);
}

/// Get element's tag name as Zig string
pub fn getElementName(element: DomElementPtr) !SliceU8 {
    const node = elementToNode(element);
    const name = getNodeName(node);
    return name;
}

/// Insert child node into parent - no error handling needed since it returns void
pub fn insertChild(parent: DomNodePtr, child: DomNodePtr) void {
    lxb_dom_node_insert_child(parent, child); // No status to check!
}

//=============================================================================
// UTILITY FUNCTIONS
//=============================================================================

/// Walk and print DOM tree (for debugging)
pub fn walkTree(node: *lxb_dom_node_t, depth: u32) void {
    var child = getFirstChild(node);
    while (child != null) {
        const name = try getNodeName(child.?);
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
pub fn printDocumentStructure(doc: HtmlDocumentPtr) void {
    std.debug.print("\n=== DOCUMENT STRUCTURE ===\n", .{});
    const root = getDocumentNode(doc);
    walkTree(root, 0);
    std.debug.print("\n{s}\n", .{try getNodeName(root)});
    std.debug.print("\n{s}\n", .{try getElementName(getBodyElement(doc).?)});
    std.debug.print("\n=== END STRUCTURE ===\n", .{});
}

/// Parse and display fragment (for testing)
pub fn demonstrateFragmentParsing(fragment: SliceU8) !void {
    std.debug.print("\nParsing fragment: {s}\n", .{fragment});

    const frag_doc = try parseFragmentAsDocument(fragment);
    defer lxb_html_document_destroy(frag_doc);

    std.debug.print("Fragment parsed successfully!\n", .{});

    if (getBodyElement(frag_doc)) |body| {
        const body_node = elementToNode(body);
        walkTree(body_node, 0);
    }
}
