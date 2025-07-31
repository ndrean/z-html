const std = @import("std");

const Errors = error{
    DocCreateFailed,
    ParseFailed,
    RootNotFound,
    CollectionFailed,
    QueryFailed,
    SerializeFailed,
    SearchFailed,
};

//=============================================================================
// LEXBOR DOM HIERARCHY EXPLANATION:
//
// TYPICAL FLOW:
// lxb_html_document → Parse HTML → Get root/body → Search elements → Navigate nodes
//=============================================================================

// Opaque types - we don't see their internal structure
pub const lxb_html_document_t = opaque {}; // The HTML document container
pub const lxb_dom_node_t = opaque {}; // Generic DOM node (base type)
pub const lxb_dom_element_t = opaque {}; // HTML element (subset of nodes)
pub const lxb_dom_collection_t = opaque {}; // Collection of elements
pub const lxb_dom_attr_t = opaque {}; // Element attribute

// Lexbor primitive types
pub const lxb_char_t = u8; // Lexbor's character type
pub const lxb_status_t = c_uint; // Return status for operations
pub const LXB_STATUS_OK: lxb_status_t = 0; // Success value

// Lexbor string type - used for serialization output
pub const lexbor_str_t = extern struct {
    data: ?[*]lxb_char_t, // Pointer to string data
    length: usize, // String length
    size: usize, // Allocated size
};

//=============================================================================
// DOCUMENT LIFECYCLE FUNCTIONS
//=============================================================================

/// Create a new empty HTML document
///
/// Returns: New document ready for parsing, or null on failure
pub extern "c" fn lxb_html_document_create() ?*lxb_html_document_t;

/// Zig wrapper for creating a document with error handling
///
/// Returns: New document or DocCreateFailed error
pub fn createDocument() !*lxb_html_document_t {
    return lxb_html_document_create() orelse error.DocCreateFailed;
}

/// Parse HTML string into the document, building the DOM tree
///
/// Converts HTML text to DOM structure
///
/// doc: Document to parse into
///
/// html: Raw HTML bytes
///
/// len: Length of HTML
///
///  Returns: Status code (0 = success)
pub extern "c" fn lxb_html_document_parse(
    doc: *lxb_html_document_t,
    html: [*]const u8,
    len: usize,
) lxb_status_t;

/// Zig wrapper: Parse HTML with error handling
///
/// You can use the 'doc' to navigate the DOM tree that was built
pub fn parseDocument(doc: *lxb_html_document_t, html: []const u8) !void {
    const status = lxb_html_document_parse(doc, html.ptr, html.len);
    if (status != LXB_STATUS_OK) return error.ParseFailed;
}

/// Free all memory used by the document and its DOM tree
///
/// Call this when you're done with the document
pub extern "c" fn lxb_html_document_destroy(doc: *lxb_html_document_t) void;

//=============================================================================
// ELEMENT CREATION AND FRAGMENT PARSING
//=============================================================================

/// ???
extern "c" fn lxb_dom_interface_node(obj: *anyopaque) *lxb_dom_node_t;

/// Parse fragment as document - returns nullable pointer
extern "c" fn lexbor_parse_fragment_as_document(
    html: [*]const lxb_char_t,
    html_len: usize,
) ?*lxb_html_document_t; // Note the ? for nullable

/// Parse fragment and returns the document
pub fn parseFragmentAsDocument(fragment: []const u8) !*lxb_html_document_t {
    return lexbor_parse_fragment_as_document(fragment.ptr, fragment.len) orelse error.FragmentParseFailed;
}

/// Create a new HTML element in the document by tag name
extern "c" fn lexbor_create_dom_element(
    doc: *lxb_html_document_t,
    tag_name: [*]const lxb_char_t,
    tag_len: usize,
) ?*lxb_dom_element_t;

pub fn createDomElement(doc: *lxb_html_document_t, tag_name: []const u8) !*lxb_dom_element_t {
    return lexbor_create_dom_element(doc, tag_name.ptr, tag_name.len) orelse error.CreateElementFailed;
}

//=============================================================================
// C WRAPPER FUNCTIONS
// These exist because some lexbor functions are macros or need struct access
//=============================================================================

/// Convert any lexbor object to a DOM node
///
/// Used for type casting in the lexbor hierarchy
extern "c" fn lexbor_dom_interface_node_wrapper(obj: *anyopaque) *lxb_dom_node_t;

/// Convert a DOM node to a DOM element (if it is one)
///
/// Returns null if the node is not an element (e.g., text node, comment)
extern "c" fn lexbor_dom_interface_element_wrapper(node: *lxb_dom_node_t) ?*lxb_dom_element_t;

/// Create a collection for storing search results
///
/// Needs access to document's internal DOM document structure
extern "c" fn lexbor_collection_make_wrapper(doc: *lxb_html_document_t, size: usize) ?*lxb_dom_collection_t;

/// Get the document's <body> element as a DOM element
///
/// Handles the type conversion from HTML-specific body to generic element
extern "c" fn lexbor_get_body_element_wrapper(doc: *lxb_html_document_t) ?*lxb_dom_element_t;

//=============================================================================
// DOM TREE NAVIGATION FUNCTIONS
// These let you walk through the parsed HTML structure
//=============================================================================

/// Get the first child node of a given node
///
/// For \<div\>\<p\>text\<\/p\>\<\/div\>, the div's first child is the \<p\> element
pub extern "c" fn lxb_dom_node_first_child_noi(node: *lxb_dom_node_t) ?*lxb_dom_node_t;

/// Get the next sibling node at the same level
///
/// Example:
///   For \<div\>\<p\>1\<\/p\>\<p\>2\<\/p\>\<\/div\>, first \<p\>'s next sibling is second \<p\>
pub extern "c" fn lxb_dom_node_next_noi(node: *lxb_dom_node_t) ?*lxb_dom_node_t;
/// Get the tag name of a node (like "div", "p", "span")
///
/// len: parameter can be null if you don't need the length
///
/// Returns: Null-terminated string with the tag name
pub extern "c" fn lxb_dom_node_name(node: *lxb_dom_node_t, len: ?*usize) [*:0]const lxb_char_t;

// DOCUMENT-LEVEL ACCESSORS
// These get specific parts of the document structure
//=============================================================================

/// Get the document's <body> element as HTML-specific type
///
/// Returns opaque pointer that needs conversion to use with DOM functions
pub extern "c" fn lxb_html_document_body_element(document: *lxb_html_document_t) ?*anyopaque;

//=============================================================================
// COLLECTION FUNCTIONS
// Collections hold multiple elements (like search results)
//=============================================================================

/// Get the number of elements in a collection
pub extern "c" fn lxb_dom_collection_length(collection: *lxb_dom_collection_t) usize;

/// Get a specific element from a collection by index
///
/// Like collection[idx] in other languages
pub extern "c" fn lxb_dom_collection_element(
    collection: *lxb_dom_collection_t,
    idx: usize,
) ?*lxb_dom_element_t;

/// Search for all elements with a specific tag name within a root element
///
/// This MODIFIES the collection by adding found elements to it
///
/// root: Where to start searching (usually body or document root)
///
/// collection: Where to store the results
///
/// qualified_name: Tag name to search for (like "div", "p")
pub extern "c" fn lxb_dom_elements_by_tag_name(
    root: *lxb_dom_element_t,
    collection: *lxb_dom_collection_t,
    qualified_name: [*]const lxb_char_t,
    len: usize,
) lxb_status_t;

/// Zig wrapper: Search for elements by tag name with error handling
///
/// After this succeeds, use lxb_dom_collection_length/element to access results
pub fn findElementsByTagName(
    root: *lxb_dom_element_t,
    collection: *lxb_dom_collection_t,
    tag_name: []const u8,
) !void {
    const status = lxb_dom_elements_by_tag_name(
        root,
        collection,
        tag_name.ptr,
        tag_name.len,
    );

    if (status != LXB_STATUS_OK) {
        return error.SearchFailed;
    }
}

//=============================================================================
// SERIALIZATION FUNCTIONS
// Convert DOM back to HTML strings
//=============================================================================

/// Convert an element back to HTML string
///
/// Returns allocated buffer that must be freed with lxb_html_serialize_free
pub extern "c" fn lxb_html_serialize(node: *lxb_dom_element_t, out_len: *usize) ?[*]u8;

/// Free buffer returned by lxb_html_serialize
pub extern "c" fn lxb_html_serialize_free(buf: [*]u8) void;

//=============================================================================
// DOCUMENT QUERY FUNCTIONS
// High-level search functions that work on the whole document
//=============================================================================

/// Get the root element of the document (usually \<html\>)
pub extern "c" fn lxb_html_document_get_root(doc: *lxb_html_document_t) ?*lxb_dom_element_t;

/// Find element by its ID attribute (like getElementById in JS)
pub extern "c" fn lxb_html_document_get_element_by_id(
    doc: *lxb_html_document_t,
    id: [*]const u8,
    id_len: usize,
) ?*lxb_dom_element_t;

//=============================================================================
// COLLECTION MANAGEMENT
//=============================================================================

/// Destroy a collection and free its memory
pub extern "c" fn lxb_dom_collection_destroy(
    collection: *lxb_dom_collection_t,
    destroy_self: bool,
) ?*lxb_dom_collection_t;

/// Alternative collection creation (may not work - needs &doc->dom_document)
pub extern "c" fn lxb_dom_collection_create(
    doc: *lxb_html_document_t,
    size: usize,
) ?*lxb_dom_collection_t;

//=============================================================================
// DOCUMENT-LEVEL SEARCH FUNCTIONS
// These return collections of elements matching criteria
//=============================================================================

/// Find all elements with a specific CSS class
pub extern "c" fn lxb_html_document_get_elements_by_class_name(
    doc: *lxb_html_document_t,
    class_name: [*]const u8,
    class_len: usize,
) ?*lxb_dom_collection_t;

/// Find all elements with a specific tag name in the whole document
pub extern "c" fn lxb_html_document_get_elements_by_tag_name(
    doc: *lxb_html_document_t,
    tag_name: [*]const u8,
    tag_len: usize,
) ?*lxb_dom_collection_t;

/// Find all elements with a specific name attribute
pub extern "c" fn lxb_html_document_get_elements_by_name(
    doc: *lxb_html_document_t,
    name: [*]const u8,
    name_len: usize,
) ?*lxb_dom_collection_t;

/// Find all elements that have a specific attribute (regardless of value)
pub extern "c" fn lxb_html_document_get_elements_by_attribute(
    doc: *lxb_html_document_t,
    attr_name: [*]const u8,
    attr_len: usize,
) ?*lxb_dom_collection_t;

/// Find all elements where an attribute has a specific value
pub extern "c" fn lxb_html_document_get_elements_by_attribute_value(
    doc: *lxb_html_document_t,
    attr_name: [*]const u8,
    attr_len: usize,
    value: [*]const u8,
    value_len: usize,
) ?*lxb_dom_collection_t;

//=============================================================================
// ZIG WRAPPERS - Updated to use correct function names
//=============================================================================

/// Convert any lexbor object to DOM node
pub fn objectToNode(obj: *anyopaque) *lxb_dom_node_t {
    return lexbor_dom_interface_node_wrapper(obj);
}

/// Convert DOM node to element (if it is one)
pub fn nodeToElement(node: *lxb_dom_node_t) ?*lxb_dom_element_t {
    return lexbor_dom_interface_element_wrapper(node);
}

/// Try to convert a generic node to an element
///
/// Returns null if the node is not an element (e.g., text node)
// pub fn nodeToElement(node: *lxb_dom_node_t) ?*lxb_dom_element_t {
//     return lexbor_dom_interface_element_wrapper(node);
// }

extern "c" fn lxb_dom_node_insert_child(
    parent: *lxb_dom_node_t,
    child: *lxb_dom_node_t,
) lxb_status_t;

/// Insert a child node into a parent node
pub fn insertChild(parent: *lxb_dom_node_t, child: *lxb_dom_node_t) !void {
    const status = lxb_dom_node_insert_child(parent, child);
    if (status != LXB_STATUS_OK) return error.InsertChildFailed;
}

// Convert document to its root DOM node for tree navigation
///
/// The document itself becomes a node you can walk through
pub fn getDocumentNode(doc: *lxb_html_document_t) *lxb_dom_node_t {
    return objectToNode(doc);
}

pub fn elementToNode(element: *lxb_dom_element_t) *lxb_dom_node_t {
    return objectToNode(element);
}

/// Get the \<body\> element for content manipulation
///
/// Most HTML content lives inside the body
pub fn getBodyElement(doc: *lxb_html_document_t) ?*lxb_dom_element_t {
    return lexbor_get_body_element_wrapper(doc);
}

//=============================================================================
// HIGH-LEVEL ZIG HELPER FUNCTIONS
// These provide convenient Zig-friendly wrappers
//=============================================================================

/// Recursively print the entire DOM tree structure
///
/// Useful for debugging and understanding the parsed structure
pub fn walkTree(node: *lxb_dom_node_t, depth: u32) void {
    var child = lxb_dom_node_first_child_noi(node);
    // std.debug.print("{any}\n", .{child.?});
    while (child != null) {
        const name_ptr = lxb_dom_node_name(child.?, null);
        const name = std.mem.span(name_ptr); // Convert to Zig slice

        std.debug.print("{s}\n", .{name});

        // Recursively walk this child's children
        walkTree(child.?, depth + 1);

        // Move to next sibling
        child = lxb_dom_node_next_noi(child.?);

        // if (lxb_dom_node_name(child.?, null)) |name| {
        //     std.debug.print("{s}{s}\n", .{ "  " ** depth, name });
        // }
        // walkTree(child.?, depth + 1);
        // child = lxb_dom_node_next(child.?);
    }
}

/// Create a new collection for storing search results
///
/// Collections are like dynamic arrays for elements
pub fn createCollection(doc: *lxb_html_document_t, size: usize) !*lxb_dom_collection_t {
    return lexbor_collection_make_wrapper(doc, size) orelse error.CollectionFailed;
}

/// Get the tag name of a node as a Zig string slice
///
/// Converts C string to Zig slice for easier handling
pub fn getNodeName(node: *lxb_dom_node_t) ?[]const u8 {
    const name_ptr = lxb_dom_node_name(node, null);
    return std.mem.span(name_ptr);
}

//=============================================================================
// CONVENIENCE FUNCTIONS
// Higher-level operations combining multiple steps
//=============================================================================

/// One-step function: create document and parse HTML
///
/// Handles cleanup on parse failure
///
/// Returns: Parsed document ready for DOM operations
pub fn parseHtml(html: []const u8) !*lxb_html_document_t {
    const doc = createDocument() catch {
        return error.DocCreateFailed;
    };

    std.debug.print("document length: {d}\n", .{html.len});

    parseDocument(doc, html) catch {
        lxb_html_document_destroy(doc);
        return error.ParseFailed;
    };

    return doc;
}

pub fn demonstrateFragmentParsing(fragment: []const u8) !void {
    // const fragment = "<div>Hello</div><p>World</p>";

    // Parse fragment as document
    const frag_doc = try parseFragmentAsDocument(fragment);
    defer lxb_html_document_destroy(frag_doc); // Caller manages lifecycle

    std.debug.print("Fragment parsed successfully!\n", .{});

    // Get the body containing our fragment
    if (getBodyElement(frag_doc)) |body| {
        const body_node = elementToNode(body);
        walkTree(body_node, 0);
    }
}

//  Example to build: move content to another document:
// const main_doc = try createDocument();
// const target = try createElement(main_doc, "div");
// try moveFragmentContent(frag_doc, target);

pub fn printDocumentNodes(doc: *lxb_html_document_t) void {
    std.debug.print("=== DOCUMENT STRUCTURE ===\n", .{});
    const root = getDocumentNode(doc);
    walkTree(root, 0);
    std.debug.print("=== END STRUCTURE ===\n", .{});
}

/// Get the body element as the main content container
///
/// Most DOM operations start from the body
///
/// Note: This function name is confusing - it returns an element, not nodes
pub fn getDocumentStartElement(doc: *lxb_html_document_t) !*lxb_dom_element_t {
    const root_node = getBodyElement(doc) orelse {
        lxb_html_document_destroy(doc);
        return error.RootNotFound;
    };
    return root_node;
}
