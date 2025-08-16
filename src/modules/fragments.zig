const std = @import("std");
const z = @import("../zhtml.zig");

const Err = z.Err;
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
    try testing.expectEqualStrings("DIV", z.tagNameBorrow(elements[0]));
    try testing.expectEqualStrings("div", z.qualifiedNameBorrow(elements[0]));
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
    //     print("Element {}: {s}\n", .{ i, z.tagNameBorrow(element) });
    // }

    const serialized = try result.serialize(allocator);
    defer allocator.free(serialized);
    // print("Table serialized: {s}\n", .{serialized});

    // lexbor might auto-wrap TR elements in TBODY
    try testing.expect(elements.len >= 1);

    // Check if we got TBODY wrapper or direct TR elements
    const first_tag = z.parseTag(z.qualifiedNameBorrow(elements[0]));
    if (first_tag == .tbody) {
        // lexbor auto-wrapped in TBODY, check its children
        const tbody_children = try z.getChildren(allocator, elements[0]);
        defer allocator.free(tbody_children);
        try testing.expect(tbody_children.len == 2); // Two TR elements
        try testing.expectEqualStrings("tr", z.qualifiedNameBorrow(tbody_children[0]));
        try testing.expectEqualStrings("TR", z.tagNameBorrow(tbody_children[1]));
    } else {
        // Direct TR elements
        try testing.expect(elements.len == 2); // Two <tr> elements
        try testing.expectEqualStrings("TR", z.tagNameBorrow(elements[0]));
        try testing.expectEqualStrings("TR", z.tagNameBorrow(elements[1]));
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
    try testing.expectEqualStrings("OPTION", z.tagNameBorrow(elements[0]));
    try testing.expectEqualStrings("optgroup", z.qualifiedNameBorrow(elements[3]));
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
    try testing.expectEqualStrings("LI", z.tagNameBorrow(ul_elements[0]));
    try testing.expectEqualStrings("LI", z.tagNameBorrow(ul_elements[1]));
    try testing.expectEqualStrings("LI", z.tagNameBorrow(ul_elements[2]));

    // Test with ordered list context
    const ol_result = try parseFragment(allocator, list_items_fragment, .ol);
    defer ol_result.deinit();

    const ol_elements = try ol_result.getElements(allocator);
    defer allocator.free(ol_elements);

    try testing.expect(ol_elements.len == 3);
    try testing.expectEqualStrings("LI", z.tagNameBorrow(ol_elements[0]));

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
    try testing.expectEqualStrings("DT", z.tagNameBorrow(elements[0]));
    try testing.expectEqualStrings("DD", z.tagNameBorrow(elements[1]));
    try testing.expectEqualStrings("DT", z.tagNameBorrow(elements[2]));
    try testing.expectEqualStrings("DD", z.tagNameBorrow(elements[3]));

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
    try testing.expectEqualStrings("LEGEND", z.tagNameBorrow(elements[0]));
    try testing.expectEqualStrings("LABEL", z.tagNameBorrow(elements[1]));
    try testing.expectEqualStrings("INPUT", z.tagNameBorrow(elements[2]));
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
    try testing.expectEqualStrings("SUMMARY", z.tagNameBorrow(elements[0]));
    try testing.expectEqualStrings("P", z.tagNameBorrow(elements[1]));
    try testing.expectEqualStrings("UL", z.tagNameBorrow(elements[2]));
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
    try testing.expectEqualStrings("OPTION", z.tagNameBorrow(elements[0]));
    try testing.expectEqualStrings("OPTION", z.tagNameBorrow(elements[1]));
    try testing.expectEqualStrings("OPTION", z.tagNameBorrow(elements[2]));

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
    try testing.expectEqualStrings("AREA", z.tagNameBorrow(elements[0]));
    try testing.expectEqualStrings("AREA", z.tagNameBorrow(elements[1]));
    try testing.expectEqualStrings("AREA", z.tagNameBorrow(elements[2]));
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
    try testing.expectEqualStrings("IMG", z.tagNameBorrow(elements[0]));
    try testing.expectEqualStrings("FIGCAPTION", z.tagNameBorrow(elements[1]));

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
    try testing.expectEqualStrings("LABEL", z.tagNameBorrow(elements[0]));
    try testing.expectEqualStrings("INPUT", z.tagNameBorrow(elements[1]));
    try testing.expectEqualStrings("LABEL", z.tagNameBorrow(elements[2]));
    try testing.expectEqualStrings("INPUT", z.tagNameBorrow(elements[3]));
    try testing.expectEqualStrings("BUTTON", z.tagNameBorrow(elements[4]));

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
    try testing.expectEqualStrings("SOURCE", z.tagNameBorrow(elements[0]));
    try testing.expectEqualStrings("SOURCE", z.tagNameBorrow(elements[1]));
    try testing.expectEqualStrings("TRACK", z.tagNameBorrow(elements[2]));
    try testing.expectEqualStrings("P", z.tagNameBorrow(elements[3]));

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
    try testing.expectEqualStrings("SOURCE", z.tagNameBorrow(elements[0]));
    try testing.expectEqualStrings("SOURCE", z.tagNameBorrow(elements[1]));
    try testing.expectEqualStrings("TRACK", z.tagNameBorrow(elements[2]));
    try testing.expectEqualStrings("P", z.tagNameBorrow(elements[3]));
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
    try testing.expectEqualStrings("SOURCE", z.tagNameBorrow(elements[0]));
    try testing.expectEqualStrings("SOURCE", z.tagNameBorrow(elements[1]));
    try testing.expectEqualStrings("IMG", z.tagNameBorrow(elements[2]));

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
    try testing.expectEqualStrings("HEADER", z.tagNameBorrow(app_children[0]));
    try testing.expectEqualStrings("MAIN", z.tagNameBorrow(app_children[1]));
    try testing.expectEqualStrings("FOOTER", z.tagNameBorrow(app_children[2]));

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
