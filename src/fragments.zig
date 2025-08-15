const std = @import("std");
const z = @import("zhtml.zig");

const Err = @import("errors.zig").LexborError;
const testing = std.testing;
const print = std.debug.print;

// External lexbor functions for fragment parsing
extern "c" fn lxb_html_document_parse_fragment(
    document: *z.HtmlDocument,
    element: *z.DomElement, // Context element
    html: [*]const u8,
    html_len: usize,
) ?*z.DomNode; // Returns parse root node, not status

extern "c" fn lxb_dom_document_create_element(document: *z.HtmlDocument, local_name: [*]const u8, local_name_len: usize, reserved: ?*anyopaque) ?*z.DomElement;

// Cross-document node cloning
extern "c" fn lexbor_clone_node_deep(node: *z.DomNode, target_doc: *z.HtmlDocument) ?*z.DomNode;

/// Fragment parsing context - defines how the fragment should be interpreted
pub const FragmentContext = enum {
    /// Parse as if inside <body> (default for most cases)
    body,
    /// Parse as if inside <div> (for general content)
    div,
    /// Parse as if inside <template> (for web components)
    template,
    /// Parse as if inside <table> (for table rows/cells)
    table,
    /// Parse as if inside <tr> (for table cells)
    table_row,
    /// Parse as if inside <select> (for options)
    select,
    /// Parse as if inside <head> (for meta tags, styles)
    head,
    /// Custom context element
    custom,

    fn toTagName(self: FragmentContext) []const u8 {
        return switch (self) {
            .body => "body",
            .div => "div",
            .template => "template",
            .table => "table",
            .table_row => "tr",
            .select => "select",
            .head => "head",
            .custom => "div", // fallback
        };
    }
};

/// Fragment parsing result
pub const FragmentResult = struct {
    document: *z.HtmlDocument,
    fragment_root: *z.DomNode,
    context_element: *z.DomElement,

    pub fn deinit(self: FragmentResult) void {
        z.destroyDocument(self.document);
    }

    /// Get all top-level nodes from the fragment
    pub fn getNodes(self: FragmentResult, allocator: std.mem.Allocator) ![]*z.DomNode {
        return z.getChildNodes(allocator, self.fragment_root);
    }

    /// Get all top-level elements from the fragment (skipping text nodes)
    pub fn getElements(self: FragmentResult, allocator: std.mem.Allocator) ![]*z.DomElement {
        const all_nodes = try self.getNodes(allocator);
        defer allocator.free(all_nodes);

        var elements = std.ArrayList(*z.DomElement).init(allocator);
        for (all_nodes) |node| {
            if (z.nodeToElement(node)) |element| {
                try elements.append(element);
            }
        }
        return elements.toOwnedSlice();
    }

    /// Serialize the fragment back to HTML
    pub fn serialize(self: FragmentResult, allocator: std.mem.Allocator) ![]u8 {
        // Serialize the fragment_root's innerHTML
        return z.innerHTML(allocator, z.nodeToElement(self.fragment_root).?);
    }
};

/// Parse an HTML fragment with specified context
pub fn parseFragment(allocator: std.mem.Allocator, html_fragment: []const u8, context: FragmentContext) !FragmentResult {
    _ = allocator; // May be needed for error handling in future

    // Create a new document for the fragment
    const doc = try z.createDocument();

    // Create context element that determines parsing rules
    const tag_name = context.toTagName();
    const context_element = lxb_dom_document_create_element(doc, tag_name.ptr, tag_name.len, null) orelse {
        z.destroyDocument(doc);
        return Err.CreateElementFailed;
    };

    // Parse the fragment within the context
    const parse_root = lxb_html_document_parse_fragment(doc, context_element, html_fragment.ptr, html_fragment.len) orelse {
        z.destroyDocument(doc);
        return Err.ParseFailed;
    };

    return FragmentResult{
        .document = doc,
        .fragment_root = parse_root,
        .context_element = context_element,
    };
}

/// Parse fragment with default body context
pub fn parseFragmentSimple(allocator: std.mem.Allocator, html_fragment: []const u8) !FragmentResult {
    return parseFragment(allocator, html_fragment, .body);
}

/// Parse fragment and immediately extract to existing document
pub fn parseFragmentInto(allocator: std.mem.Allocator, target_doc: *z.HtmlDocument, target_parent: *z.DomNode, html_fragment: []const u8, context: FragmentContext) !void {
    const fragment_result = try parseFragment(allocator, html_fragment, context);
    defer fragment_result.deinit();

    // Get all nodes from the fragment
    const children = try fragment_result.getNodes(allocator);
    defer allocator.free(children);

    // Clone each node into the target document and append
    for (children) |child| {
        if (lexbor_clone_node_deep(child, target_doc)) |cloned_node| {
            z.appendChild(target_parent, cloned_node);
        }
    }
}

// ============================================================================
// TESTS AND EXAMPLES
// ============================================================================

test "basic fragment parsing" {
    const allocator = testing.allocator;

    const fragment_html =
        \\<div class="card">
        \\  <h3>Product Title</h3>
        \\  <p class="price">$99.99</p>
        \\  <button>Add to Cart</button>
        \\</div>
    ;

    const result = try parseFragmentSimple(allocator, fragment_html);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 1);
    try testing.expectEqualStrings("DIV", z.tagName(elements[0]));

    const serialized = try result.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "card") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "Product Title") != null);
}

test "table fragment parsing with context" {
    const allocator = testing.allocator;

    const table_fragment =
        \\<tr>
        \\  <td>John Doe</td>
        \\  <td>Engineer</td>
        \\  <td>$75,000</td>
        \\</tr>
        \\<tr>
        \\  <td>Jane Smith</td>
        \\  <td>Designer</td>
        \\  <td>$65,000</td>
        \\</tr>
    ;

    // Parse as if inside a table body
    const result = try parseFragment(allocator, table_fragment, .table);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    // Debug what we actually got
    // print("Table elements found: {}\n", .{elements.len});
    // for (elements, 0..) |element, i| {
    //     print("Element {}: {s}\n", .{ i, z.tagName(element) });
    // }

    const serialized = try result.serialize(allocator);
    defer allocator.free(serialized);
    // print("Table serialized: {s}\n", .{serialized});

    // lexbor might auto-wrap TR elements in TBODY
    try testing.expect(elements.len >= 1);

    // Check if we got TBODY wrapper or direct TR elements
    const first_tag = z.tagName(elements[0]);
    if (std.mem.eql(u8, first_tag, "TBODY")) {
        // lexbor auto-wrapped in TBODY, check its children
        const tbody_children = try z.getChildren(allocator, elements[0]);
        defer allocator.free(tbody_children);
        try testing.expect(tbody_children.len == 2); // Two TR elements
        try testing.expectEqualStrings("TR", z.tagName(tbody_children[0]));
        try testing.expectEqualStrings("TR", z.tagName(tbody_children[1]));
    } else {
        // Direct TR elements
        try testing.expect(elements.len == 2); // Two <tr> elements
        try testing.expectEqualStrings("TR", z.tagName(elements[0]));
        try testing.expectEqualStrings("TR", z.tagName(elements[1]));
    }
}

test "select options fragment" {
    const allocator = testing.allocator;

    const options_fragment =
        \\<option value="us">United States</option>
        \\<option value="ca">Canada</option>
        \\<option value="mx">Mexico</option>
        \\<optgroup label="Europe">
        \\  <option value="uk">United Kingdom</option>
        \\  <option value="de">Germany</option>
        \\</optgroup>
    ;

    const result = try parseFragment(allocator, options_fragment, .select);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    // Should have 3 options + 1 optgroup = 4 elements
    try testing.expect(elements.len == 4);
    try testing.expectEqualStrings("OPTION", z.tagName(elements[0]));
    try testing.expectEqualStrings("OPTGROUP", z.tagName(elements[3]));
}

test "template component parsing" {
    const allocator = testing.allocator;

    const component_template =
        \\<div class="user-card" data-user-id="{{id}}">
        \\  <img src="{{avatar}}" alt="{{name}}" class="avatar">
        \\  <div class="user-info">
        \\    <h4>{{name}}</h4>
        \\    <p class="role">{{role}}</p>
        \\    <span class="status {{status_class}}">{{status}}</span>
        \\  </div>
        \\  <div class="actions">
        \\    <button data-action="message">Message</button>
        \\    <button data-action="follow">Follow</button>
        \\  </div>
        \\</div>
    ;

    const result = try parseFragment(allocator, component_template, .template);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 1);

    const serialized = try result.serialize(allocator);
    defer allocator.free(serialized);

    // Template variables should be preserved as-is
    try testing.expect(std.mem.indexOf(u8, serialized, "{{id}}") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "{{name}}") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "user-card") != null);
}

test "multiple fragment parsing and composition" {
    const allocator = testing.allocator;

    // Create a target document to compose fragments into
    const doc = try z.parseFromString("<html><body><div id='app'></div></body></html>");
    defer z.destroyDocument(doc);

    const app_div = try z.getElementById(doc, "app");
    const app_node = z.elementToNode(app_div.?);

    // Parse and add header fragment
    const header_fragment = "<header><h1>My App</h1><nav>Navigation</nav></header>";
    try parseFragmentInto(allocator, doc, app_node, header_fragment, .body);

    // Parse and add main content fragment
    const main_fragment =
        \\<main>
        \\  <section class="content">
        \\    <p>Main content here</p>
        \\  </section>
        \\</main>
    ;
    try parseFragmentInto(allocator, doc, app_node, main_fragment, .body);

    // Parse and add footer fragment
    const footer_fragment = "<footer><p>&copy; 2024 My Company</p></footer>";
    try parseFragmentInto(allocator, doc, app_node, footer_fragment, .body);

    // Verify the composition
    const app_children = try z.getChildren(allocator, app_div.?);
    defer allocator.free(app_children);

    try testing.expect(app_children.len == 3); // header, main, footer
    try testing.expectEqualStrings("HEADER", z.tagName(app_children[0]));
    try testing.expectEqualStrings("MAIN", z.tagName(app_children[1]));
    try testing.expectEqualStrings("FOOTER", z.tagName(app_children[2]));

    const final_html = try z.innerHTML(allocator, app_div.?);
    defer allocator.free(final_html);

    try testing.expect(std.mem.indexOf(u8, final_html, "<header>") != null);
    try testing.expect(std.mem.indexOf(u8, final_html, "<main>") != null);
    try testing.expect(std.mem.indexOf(u8, final_html, "<footer>") != null);
}

test "malformed fragment recovery" {
    const allocator = testing.allocator;

    const malformed_fragment =
        \\<div class="card">
        \\  <h3>Title
        \\  <p>Missing closing tags
        \\  <span>More content
        \\</div>
    ;

    const result = try parseFragmentSimple(allocator, malformed_fragment);
    defer result.deinit();

    const serialized = try result.serialize(allocator);
    defer allocator.free(serialized);

    // lexbor should auto-fix the malformed HTML
    try testing.expect(std.mem.indexOf(u8, serialized, "</h3>") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "</p>") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "</span>") != null);
}
