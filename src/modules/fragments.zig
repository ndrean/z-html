//! Fragment utilities
//! waiting lexbor issue on `appendChild` vs `appendFragment`

const std = @import("std");
const z = @import("../zhtml.zig");

const Err = z.Err;
const testing = std.testing;
const print = std.debug.print;

// ===
//<- z.objectToNode made pub
// extern "c" fn lexbor_dom_interface_node_wrapper(obj: *anyopaque) *z.DomNode;
extern "c" fn lxb_html_document_parse_fragment(
    document: *z.HTMLDocument,
    element: *z.HTMLElement, // Context element
    html: [*]const u8,
    html_len: usize,
) ?*z.DomNode; // Returns parse root node, not status

extern "c" fn lxb_dom_document_create_document_fragment(doc: *z.HTMLDocument) ?*z.DocumentFragment;

// Cross-document node cloning
extern "c" fn lexbor_clone_node_deep(node: *z.DomNode, target_doc: *z.HTMLDocument) ?*z.DomNode;
// ===

/// [fragments] Get the underlying DOM node from a fragment
pub fn fragmentToNode(fragment: *z.DocumentFragment) *z.DomNode {
    return z.objectToNode(fragment);
}

/// [fragment] Create a document fragment and returns a !Fragment
///
/// !! lexbor behaviour does not match the browser's specs on insertion. Use `appendFragment` for this.
///
/// Document fragments are lightweight containers that can hold multiple nodes. Useful for batch DOM operations
///
/// Official browser spec: when you append a fragment to the DOM, only its children are added, not the fragment itself which is destroyed.
pub fn createDocumentFragment(doc: *z.HTMLDocument) !*z.DocumentFragment {
    return lxb_dom_document_create_document_fragment(doc) orelse Err.FragmentParseFailed;
}

/// [fragments] Append all children from a document fragment to a parent node
///
/// Not the normal procedure
///
/// The fragment children are moved, not copied
pub fn appendFragment(parent: *z.DomNode, fragment: *z.DomNode) void {
    var fragment_child = z.firstChild(fragment);
    while (fragment_child != null) {
        const next_sibling = z.nextSibling(fragment_child.?);
        z.appendChild(parent, fragment_child.?);
        fragment_child = next_sibling;
    }
}

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
    /// Parse as if inside <ul> (for list items)
    ul,
    /// Parse as if inside <ol> (for ordered list items)
    ol,
    /// Parse as if inside <dl> (for definition terms/descriptions)
    dl,
    /// Parse as if inside <fieldset> (for legend elements)
    fieldset,
    /// Parse as if inside <details> (for summary elements)
    details,
    /// Parse as if inside <optgroup> (for grouped options)
    optgroup,
    /// Parse as if inside <map> (for area elements)
    map,
    /// Parse as if inside <figure> (for img/figcaption elements)
    figure,
    /// Parse as if inside <form> (for input/label/button elements)
    form,
    /// Parse as if inside <video> (for source/track elements)
    video,
    /// Parse as if inside <audio> (for source/track elements)
    audio,
    /// Parse as if inside <picture> (for source/img elements)
    picture,
    /// Parse as if inside <head> (for meta tags, styles)
    head,
    /// Custom context element
    custom,

    /// Convert context enum to HTML tag name string
    /// Inlined for zero function call overhead in fragment parsing
    inline fn toTagName(self: FragmentContext) []const u8 {
        return switch (self) {
            .body => "body",
            .div => "div",
            .template => "template",
            .table => "table",
            .table_row => "tr",
            .select => "select",
            .ul => "ul",
            .ol => "ol",
            .dl => "dl",
            .fieldset => "fieldset",
            .details => "details",
            .optgroup => "optgroup",
            .map => "map",
            .figure => "figure",
            .form => "form",
            .video => "video",
            .audio => "audio",
            .picture => "picture",
            .head => "head",
            .custom => "div", // fallback
        };
    }
};

/// Fragment parsing result
pub const FragmentResult = struct {
    document: *z.HTMLDocument,
    fragment_root: *z.DomNode,
    context_element: *z.HTMLElement,

    pub fn deinit(self: FragmentResult) void {
        z.destroyDocument(self.document);
    }

    /// Get all top-level nodes from the fragment
    pub fn getNodes(self: FragmentResult, allocator: std.mem.Allocator) ![]*z.DomNode {
        return z.getChildNodes(allocator, self.fragment_root);
    }

    /// Get all top-level elements from the fragment (skipping text nodes)
    pub fn getElements(self: FragmentResult, allocator: std.mem.Allocator) ![]*z.HTMLElement {
        const all_nodes = try self.getNodes(allocator);
        defer allocator.free(all_nodes);

        var elements = std.ArrayList(*z.HTMLElement).init(allocator);
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
        return z.innerHTML(
            allocator,
            z.nodeToElement(self.fragment_root).?,
        );
    }
};

/// Parse an HTML fragment with specified context
pub fn parseFragment(
    allocator: std.mem.Allocator,
    html_fragment: []const u8,
    context: FragmentContext,
) !FragmentResult {
    _ = allocator; // May be needed for error handling in future

    // Create a new document for the fragment
    const doc = try z.createDocument();

    // Create context element that determines parsing rules
    const tag_name = context.toTagName();
    const context_element = z.createElement(doc, tag_name, &.{}) catch {
        z.destroyDocument(doc);
        return Err.CreateElementFailed;
    };

    // Parse the fragment within the context
    const parse_root = lxb_html_document_parse_fragment(
        doc,
        context_element,
        html_fragment.ptr,
        html_fragment.len,
    ) orelse {
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
pub fn parseFragmentSimple(
    allocator: std.mem.Allocator,
    html_fragment: []const u8,
) !FragmentResult {
    return parseFragment(allocator, html_fragment, .body);
}

/// Parse fragment and immediately extract to existing document
pub fn parseFragmentInto(
    allocator: std.mem.Allocator,
    target_doc: *z.HTMLDocument,
    target_parent: *z.DomNode,
    html_fragment: []const u8,
    context: FragmentContext,
) !void {
    const fragment_result = try parseFragment(
        allocator,
        html_fragment,
        context,
    );
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
    try testing.expectEqualStrings("DIV", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("div", z.qualifiedName_zc(elements[0]));
    const class = try z.getAttribute(allocator, elements[0], "class");
    defer if (class) |c| {
        allocator.free(c);
    };
    try testing.expectEqualStrings("card", class.?);

    const serialized = try result.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "card") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "Product Title") != null);
}

test "table fragment parsing with context" {
    const allocator = testing.allocator;

    const table_fragment =
        \\<tr>
        \\  <td>John</td>
        \\  <td>Designer</td>
        \\  <td>$75,000</td>
        \\</tr>
        \\<tr>
        \\  <td>Jane</td>
        \\  <td>Dev</td>
        \\  <td>$75,000</td>
        \\</tr>
    ;

    // Parse as if inside a table body
    const result = try parseFragment(
        allocator,
        table_fragment,
        .table,
    );
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    // print("Table elements found: {}\n", .{elements.len});
    // for (elements, 0..) |element, i| {
    //     print("Element {}: {s}\n", .{ i, z.tagName_zc(element) });
    // }

    const serialized = try result.serialize(allocator);
    defer allocator.free(serialized);
    // print("Table serialized: {s}\n", .{serialized});

    // lexbor might auto-wrap TR elements in TBODY
    try testing.expect(elements.len >= 1);

    // Check if we got TBODY wrapper or direct TR elements
    const first_tag = z.parseTag(z.qualifiedName_zc(elements[0]));
    if (first_tag == .tbody) {
        // lexbor auto-wrapped in TBODY, check its children
        const tbody_children = try z.getChildren(allocator, elements[0]);
        defer allocator.free(tbody_children);
        try testing.expect(tbody_children.len == 2); // Two TR elements
        try testing.expectEqualStrings("tr", z.qualifiedName_zc(tbody_children[0]));
        try testing.expectEqualStrings("TR", z.tagName_zc(tbody_children[1]));
    } else {
        // Direct TR elements
        try testing.expect(elements.len == 2); // Two <tr> elements
        try testing.expectEqualStrings("TR", z.tagName_zc(elements[0]));
        try testing.expectEqualStrings("TR", z.tagName_zc(elements[1]));
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
        \\  <option value="fr">France</option>
        \\  <option value="de">Germany</option>
        \\</optgroup>
    ;

    const result = try parseFragment(
        allocator,
        options_fragment,
        .select,
    );
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    // Should have 3 options + 1 optgroup = 4 elements
    try testing.expect(elements.len == 4);
    try testing.expectEqualStrings("OPTION", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("optgroup", z.qualifiedName_zc(elements[3]));
}

test "list item fragments with context" {
    const allocator = testing.allocator;

    const list_items_fragment =
        \\<li>First item</li>
        \\<li>Second item</li>
        \\<li>Third item</li>
    ;

    // Test with unordered list context
    const ul_result = try parseFragment(allocator, list_items_fragment, .ul);
    defer ul_result.deinit();

    const ul_elements = try ul_result.getElements(allocator);
    defer allocator.free(ul_elements);

    try testing.expect(ul_elements.len == 3);
    try testing.expectEqualStrings("LI", z.tagName_zc(ul_elements[0]));
    try testing.expectEqualStrings("LI", z.tagName_zc(ul_elements[1]));
    try testing.expectEqualStrings("LI", z.tagName_zc(ul_elements[2]));

    // Test with ordered list context
    const ol_result = try parseFragment(allocator, list_items_fragment, .ol);
    defer ol_result.deinit();

    const ol_elements = try ol_result.getElements(allocator);
    defer allocator.free(ol_elements);

    try testing.expect(ol_elements.len == 3);
    try testing.expectEqualStrings("LI", z.tagName_zc(ol_elements[0]));

    const ol_serialized = try ol_result.serialize(allocator);
    defer allocator.free(ol_serialized);

    // Verify content is preserved
    try testing.expect(std.mem.indexOf(u8, ol_serialized, "First item") != null);
    try testing.expect(std.mem.indexOf(u8, ol_serialized, "Second item") != null);
    try testing.expect(std.mem.indexOf(u8, ol_serialized, "Third item") != null);
}

test "definition list fragments" {
    const allocator = testing.allocator;

    const dl_fragment =
        \\<dt>Term 1</dt>
        \\<dd>Definition for term 1</dd>
        \\<dt>Term 2</dt>  
        \\<dd>Definition for term 2</dd>
    ;

    const result = try parseFragment(allocator, dl_fragment, .dl);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 4); // 2 dt + 2 dd elements
    try testing.expectEqualStrings("DT", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("DD", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("DT", z.tagName_zc(elements[2]));
    try testing.expectEqualStrings("DD", z.tagName_zc(elements[3]));

    const serialized = try result.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "Term 1") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "Definition for term 1") != null);
}

test "fieldset legend fragments" {
    const allocator = testing.allocator;

    const fieldset_fragment =
        \\<legend>Contact Information</legend>
        \\<label for="name">Name:</label>
        \\<input type="text" id="name" name="name">
    ;

    const result = try parseFragment(allocator, fieldset_fragment, .fieldset);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 3); // legend + label + input
    try testing.expectEqualStrings("LEGEND", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("LABEL", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("INPUT", z.tagName_zc(elements[2]));
}

test "details summary fragments" {
    const allocator = testing.allocator;

    const details_fragment =
        \\<summary>Click to expand</summary>
        \\<p>This content is hidden by default</p>
        \\<ul>
        \\  <li>Item 1</li>
        \\  <li>Item 2</li>
        \\</ul>
    ;

    const result = try parseFragment(allocator, details_fragment, .details);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 3); // summary + p + ul
    try testing.expectEqualStrings("SUMMARY", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("P", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("UL", z.tagName_zc(elements[2]));
}

test "optgroup nested options" {
    const allocator = testing.allocator;

    const optgroup_fragment =
        \\<option value="ny">New York</option>
        \\<option value="ca">California</option>
        \\<option value="tx">Texas</option>
    ;

    const result = try parseFragment(allocator, optgroup_fragment, .optgroup);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 3);
    try testing.expectEqualStrings("OPTION", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("OPTION", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("OPTION", z.tagName_zc(elements[2]));

    const serialized = try result.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "New York") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "California") != null);
}

test "image map area fragments" {
    const allocator = testing.allocator;

    const map_fragment =
        \\<area shape="rect" coords="0,0,100,100" href="/section1" alt="Section 1">
        \\<area shape="circle" coords="150,75,50" href="/section2" alt="Section 2">
        \\<area shape="poly" coords="200,0,250,50,200,100,150,50" href="/section3" alt="Section 3">
    ;

    const result = try parseFragment(allocator, map_fragment, .map);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 3);
    try testing.expectEqualStrings("AREA", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("AREA", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("AREA", z.tagName_zc(elements[2]));
}

test "figure with image and caption" {
    const allocator = testing.allocator;

    const figure_fragment =
        \\<img src="/chart.png" alt="Sales Chart" width="400" height="300">
        \\<figcaption>Monthly sales performance for Q4 2024</figcaption>
    ;

    const result = try parseFragment(allocator, figure_fragment, .figure);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 2); // img + figcaption
    try testing.expectEqualStrings("IMG", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("FIGCAPTION", z.tagName_zc(elements[1]));

    const serialized = try result.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "/chart.png") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "Monthly sales") != null);
}

test "form input fragments" {
    const allocator = testing.allocator;

    const form_fragment =
        \\<label for="email">Email Address:</label>
        \\<input type="email" id="email" name="email" required>
        \\<label for="password">Password:</label>
        \\<input type="password" id="password" name="password" required>
        \\<button type="submit">Login</button>
    ;

    const result = try parseFragment(allocator, form_fragment, .form);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 5); // 2 labels + 2 inputs + 1 button
    try testing.expectEqualStrings("LABEL", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("INPUT", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("LABEL", z.tagName_zc(elements[2]));
    try testing.expectEqualStrings("INPUT", z.tagName_zc(elements[3]));
    try testing.expectEqualStrings("BUTTON", z.tagName_zc(elements[4]));

    const serialized = try result.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "Email Address") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "type=\"email\"") != null);
}

test "video with sources" {
    const allocator = testing.allocator;

    const video_fragment =
        \\<source src="/video.webm" type="video/webm">
        \\<source src="/video.mp4" type="video/mp4">
        \\<track kind="captions" src="/captions.vtt" srclang="en" label="English">
        \\<p>Your browser doesn't support HTML5 video.</p>
    ;

    const result = try parseFragment(allocator, video_fragment, .video);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 4); // 2 sources + 1 track + 1 p
    try testing.expectEqualStrings("SOURCE", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("SOURCE", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("TRACK", z.tagName_zc(elements[2]));
    try testing.expectEqualStrings("P", z.tagName_zc(elements[3]));

    const serialized = try result.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "video.webm") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "captions.vtt") != null);
}

test "audio with sources" {
    const allocator = testing.allocator;

    const audio_fragment =
        \\<source src="/audio.ogg" type="audio/ogg">
        \\<source src="/audio.mp3" type="audio/mp3">
        \\<track kind="descriptions" src="/descriptions.vtt" srclang="en">
        \\<p>Your browser doesn't support HTML5 audio.</p>
    ;

    const result = try parseFragment(allocator, audio_fragment, .audio);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 4); // 2 sources + 1 track + 1 p
    try testing.expectEqualStrings("SOURCE", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("SOURCE", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("TRACK", z.tagName_zc(elements[2]));
    try testing.expectEqualStrings("P", z.tagName_zc(elements[3]));
}

test "picture with responsive sources" {
    const allocator = testing.allocator;

    const picture_fragment =
        \\<source media="(min-width: 800px)" srcset="/hero-large.jpg">
        \\<source media="(min-width: 400px)" srcset="/hero-medium.jpg">
        \\<img src="/hero-small.jpg" alt="Hero image">
    ;

    const result = try parseFragment(allocator, picture_fragment, .picture);
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 3); // 2 sources + 1 img
    try testing.expectEqualStrings("SOURCE", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("SOURCE", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("IMG", z.tagName_zc(elements[2]));

    const serialized = try result.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "hero-large.jpg") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "min-width: 800px") != null);
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
    const body = try z.bodyNode(doc);

    const app_div = z.getElementById(body, "app");
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
    try testing.expectEqualStrings("HEADER", z.tagName_zc(app_children[0]));
    try testing.expectEqualStrings("MAIN", z.tagName_zc(app_children[1]));
    try testing.expectEqualStrings("FOOTER", z.tagName_zc(app_children[2]));

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

test "append createDocumentFragment" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<html><body><ul id=\"ul\"></ul></body></html>");
    defer z.destroyDocument(doc);

    const browsers = [_][]const u8{ "Firefox", "Chrome", "Opera", "Safari", "Internet Explorer" };

    const fragment = try z.createDocumentFragment(doc);

    for (browsers) |browser| {
        const li = try z.createElement(doc, "li", &.{});
        const text = try z.createTextNode(doc, browser);
        z.appendChild(z.elementToNode(li), text);
        z.appendChild(z.fragmentToNode(fragment), z.elementToNode(li));
    }

    const fragment_node = z.fragmentToNode(fragment);

    const body_node = try z.bodyNode(doc);
    const ul_element = z.getElementById(body_node, "ul");
    const ul = z.elementToNode(ul_element.?);

    // z.appendChild(ul, fragment_node); // !!!<-- "official" behaviour
    z.appendFragment(ul, fragment_node);

    // try z.printDocumentStructure(doc);

    var p_count: usize = 0;
    var child = z.firstChild(ul);
    while (child != null) : (child = z.nextSibling(child.?)) {
        if (!z.isTypeElement(child.?)) continue;

        if (z.tagFromElement(z.nodeToElement(child.?).?)) |tag| {
            if (tag == .li) {
                p_count += 1;
            }
        }
    }
    try testing.expectEqual(@as(usize, 5), p_count);

    const child_elements = try z.getChildren(allocator, ul_element.?);
    defer allocator.free(child_elements);

    try testing.expect(child_elements.len == 5);
}

test "show" {
    const allocator = testing.allocator;

    const doc = try z.parseFromString("");
    defer z.destroyDocument(doc);

    const main_elt = try z.createElement(
        doc,
        "main",
        &.{},
    );
    const div_elt = try z.createElement(
        doc,
        "div",
        &.{.{ .name = "class", .value = "container-list" }},
    );

    const div = z.elementToNode(div_elt);
    const main = z.elementToNode(main_elt);

    const comment_node = try z.createComment(doc, "a comment");
    z.appendChild(div, z.commentToNode(comment_node));

    const ul_elt = try z.createElement(doc, "ul", &.{});
    const ul = z.elementToNode(ul_elt);

    for (1..4) |i| {
        const inner_content = try std.fmt.allocPrint(
            allocator,
            "<li data-id=\"{d}\">Item {d}</li>",
            .{ i, i },
        );
        defer allocator.free(inner_content);

        const temp_div_elt = try z.createElement(doc, "div", &.{});
        const temp_div = z.elementToNode(temp_div_elt);

        _ = try z.setInnerHTML(
            allocator,
            temp_div_elt,
            inner_content,
            .{},
        );

        // Move the LI element to the UL
        if (z.firstChild(temp_div)) |li| {
            z.appendChild(ul, li);
        }
        z.destroyNode(temp_div);
    }
    z.appendChild(div, ul);
    z.appendChild(main, div);

    const fragment_elt = try z.createDocumentFragment(doc);
    const fragment_node = z.fragmentToNode(fragment_elt);
    try testing.expect(
        z.nodeType(fragment_node) == z.NodeType.fragment,
    ); // #document-fragment

    // z.appendChild(main, fragment_node);
    // batch it into the DOM
    z.appendFragment(main, fragment_node);
    try z.printDocumentStructure(doc);

    const lis = try z.getElementsByTagName(doc, "LI");
    defer if (lis) |collection| {
        z.destroyCollection(collection);
    };
    const li_count = z.collectionLength(lis.?);
    try testing.expect(li_count == 0);

    const fragment_txt = try z.serializeToString(allocator, main);
    // print("\n\n{s}\n\n", .{fragment_txt});

    defer allocator.free(fragment_txt);

    const pretty_expected =
        \\<main>
        \\  <div class="container-list">
        \\      <!--a comment-->
        \\      <ul>
        \\          <li data-id="1">Item 1</li>
        \\          <li data-id="2">Item 2</li>
        \\          <li data-id="3">Item 3</li>
        \\      </ul>
        \\  </div>
        \\</main>
    ;

    const expected = try z.normalizeWhitespace(allocator, pretty_expected, .{});
    defer allocator.free(expected);

    try testing.expectEqualStrings(expected, fragment_txt);
}
