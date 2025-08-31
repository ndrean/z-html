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

// ===============================================================================================
extern "c" fn lxb_dom_document_create_document_fragment(doc: *z.HTMLDocument) ?*z.DocumentFragment;

extern "c" fn lxb_dom_document_fragment_interface_destroy(fragment: *z.DocumentFragment) *z.DocumentFragment;

// Cross-document node cloning
// extern "c" fn lexbor_clone_node_deep(node: *z.DomNode, target_doc: *z.HTMLDocument) ?*z.DomNode;
// ================================================================================================

/// [fragment] Create a document fragment and returns a !Fragment
///
/// Document fragments are lightweight containers that can hold multiple nodes. Useful for batch DOM operations.
/// Official browser spec: when you append a fragment to the DOM, only its children are added, not the fragment itself which is destroyed.
///
/// Use:
/// - `appendChild()` to the `fragmentNode()` to build the fragment
/// - `parseFragmentSimple()` to parse HTML into a fragment within a context
/// - `appendFragment()` to insert the fragment inner content into the DOM.
pub fn createDocumentFragment(doc: *z.HTMLDocument) !*z.DocumentFragment {
    return lxb_dom_document_create_document_fragment(doc) orelse Err.FragmentParseFailed;
}

pub fn destroyDocumentFragment(fragment: *z.DocumentFragment) void {
    _ = lxb_dom_document_fragment_interface_destroy(fragment);
}

/// [fragment] Get the underlying DOM node from a fragment (type `.fragment`)
pub fn fragmentNode(fragment: *z.DocumentFragment) *z.DomNode {
    return z.objectToNode(fragment);
}

test "create fragmentDocument, fragmentNode and context" {
    const allocator = testing.allocator;
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const frag_doc = try z.createDocumentFragment(doc);
    defer destroyDocumentFragment(frag_doc);

    const frag_node = z.fragmentNode(frag_doc);
    try testing.expect(.fragment == z.nodeType(frag_node));

    // --- context: body
    const frag_root_context_body = try z.parseFragmentSimple(frag_node, "<p id=\"1\">Hello<i></i>world</p>", .body);

    try testing.expect(.element == z.nodeType(frag_root_context_body));

    const frag_elt_ctx_body = z.nodeToElement(frag_root_context_body);
    try testing.expect(z.tagFromElement(frag_elt_ctx_body.?) == .html);

    const frag_ctx_body_outer_html = try z.outerNodeHTML(allocator, frag_root_context_body);
    defer allocator.free(frag_ctx_body_outer_html);
    try testing.expectEqualStrings(
        "<html><p id=\"1\">Hello<i></i>world</p></html>",
        frag_ctx_body_outer_html,
    );

    // --- context: html
    const frag_root_context_fragment = try z.parseFragmentSimple(frag_node, "<p id=\"1\">Hello<i></i>world</p>", .fragment);
    try testing.expect(.element == z.nodeType(frag_root_context_fragment));

    const frag_elt_ctx_fragment = z.nodeToElement(frag_root_context_fragment);
    try testing.expect(z.tagFromElement(frag_elt_ctx_fragment.?) == .html);

    const frag_root_context_fragment_outer_html = try z.outerNodeHTML(allocator, frag_root_context_fragment);
    defer allocator.free(frag_root_context_fragment_outer_html);
    try testing.expectEqualStrings(
        "<html><head></head><body><p id=\"1\">Hello<i></i>world</p></body></html>",
        frag_root_context_fragment_outer_html,
    );
}

test "append with createDocumentFragment: attach programmatically to fragment_node" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const frag_doc = try z.createDocumentFragment(doc);
    defer destroyDocumentFragment(frag_doc); // not needed, linked to doc

    const frag_node = z.fragmentNode(frag_doc);

    const p = try z.createElement(doc, "p");
    z.appendChild(frag_node, z.elementToNode(p));

    const maybe_p = z.firstChild(frag_node);
    try testing.expect(z.tagFromElement(z.nodeToElement(maybe_p.?).?) == .p);
}

/// [fragment] Append all children from a document fragment to a parent node
///
/// The fragment is emptied: the fragment children are moved into the DOM, not copied
pub fn appendFragment(parent: *z.DomNode, fragment_node: *z.DomNode) void {
    var fragment_child = z.firstChild(fragment_node);
    while (fragment_child != null) {
        const next_sibling = z.nextSibling(fragment_child.?);
        z.appendChild(parent, fragment_child.?);
        fragment_child = next_sibling;
    }
}

test "appendFragment to fragment_node" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<html><body><ul id=\"ul\"></ul></body></html>");
    defer z.destroyDocument(doc);

    const fragment = try z.createDocumentFragment(doc);
    const fragment_node = z.fragmentNode(fragment);

    const browsers = [_][]const u8{ "Firefox", "Chrome", "Opera", "Safari", "Internet Explorer" };

    for (browsers) |browser| {
        // Create elements directly in the same document as the fragment
        const li = try z.createElement(doc, "li");
        const text = try z.createTextNode(doc, browser);
        z.appendChild(z.elementToNode(li), text);
        z.appendChild(fragment_node, z.elementToNode(li));
    }

    // Append the fragment to the ul of the real document
    const body_node = try z.bodyNode(doc);
    const ul_element = z.getElementById(body_node, "ul");
    const ul = z.elementToNode(ul_element.?);

    z.appendFragment(ul, fragment_node);

    // Verify that all 5 li elements were added to the ul
    const child_elements = try z.children(allocator, ul_element.?);
    defer allocator.free(child_elements);

    try testing.expect(child_elements.len == 5);
}

/// Creates a new a #document-fragment, and returns a reference node containing the parsed HTML, given a context.
///
/// To append to a DOM node, use `appendFragment()` to move the fragment inner nodes.
///
/// You can this fragment node destruction.
///
/// This fragment has a single usage.
/// ## Example
/// ```
/// const doc = try z.parseFromString(<html><body></body></html>);
/// const body = try z.bodyNode(doc);
/// const fragment_root = try parseFragmentSimple(body, "<li>Hello</li>", .ul);
/// z.appendFragment(body, fragment_root);
/// ```
/// ## Signature
pub fn parseFragmentSimple(
    target: *z.DomNode,
    html_fragment: []const u8,
    context: z.FragmentContext,
) !*z.DomNode {
    const target_doc = z.ownerDocument(target);
    const context_html_tag = context.toTagName();

    const context_element = try z.createElement(
        target_doc,
        context_html_tag,
    );
    defer z.destroyElement(context_element);

    return lxb_html_document_parse_fragment(
        target_doc,
        context_element,
        html_fragment.ptr,
        html_fragment.len,
    ) orelse {
        z.destroyElement(context_element);
        return Err.ParseFailed;
    };
}

test "simple fragment parse" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);

    const fragment_root = try parseFragmentSimple(body, "<p></p>", .body);
    defer z.destroyNode(fragment_root);

    const outer_fragment = try z.outerNodeHTML(allocator, fragment_root);
    defer allocator.free(outer_fragment);
    try testing.expectEqualStrings("<html><p></p></html>", outer_fragment);

    try testing.expect(z.isNodeEmpty(body));

    z.appendFragment(body, fragment_root); // moves

    const outer_body = try z.outerNodeHTML(allocator, body);
    defer allocator.free(outer_body);
    try testing.expectEqualStrings("<body><p></p></body>", outer_body);

    z.appendFragment(body, fragment_root); // fragment_root is now empty!

    // check that nothing changed in thee document
    const children = try z.children(allocator, z.nodeToElement(body).?);
    defer allocator.free(children);
    try testing.expect(children.len == 1);
}

test "second simple fragment parsing" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("");
    defer z.destroyDocument(doc);

    const body = try z.bodyNode(doc);

    const fragment_html =
        \\<div class="card">
        \\  <h3>Product Title</h3>
        \\  <p class="price">$99.99</p>
        \\  <button>Add to Cart</button>
        \\</div>
    ;

    const parse_root = try parseFragmentSimple(
        body,
        fragment_html,
        .body,
    );
    defer z.destroyNode(parse_root);

    // insert fragment into the body
    z.appendFragment(body, parse_root);
    try z.normalize(allocator, z.nodeToElement(body).?);
    const html = try z.innerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html);

    try testing.expectEqualStrings("<div class=\"card\"><h3>Product Title</h3><p class=\"price\">$99.99</p><button>Add to Cart</button></div>", html);
}

test "interpolated simple fragment parsing" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<html><body><ul id=\"ul\"></ul></body></html>");
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);
    const ul_element = z.getElementById(body_node, "ul");
    const ul = z.elementToNode(ul_element.?);

    const browsers = [_][]const u8{ "Firefox", "Chrome", "Opera", "Safari", "Internet Explorer" };
    var len: usize = 0;
    for (browsers) |b| len += b.len;
    var result = try allocator.alloc(u8, len + 5 * 9);
    defer allocator.free(result);

    var offset: usize = 0;
    for (browsers) |browser| {
        const li_text = try std.fmt.allocPrint(allocator, "<li>{s}</li>", .{browser});
        defer allocator.free(li_text);
        @memcpy(result[offset .. offset + li_text.len], li_text);
        offset += li_text.len;
    }

    const fragment_root = try parseFragmentSimple(ul, result, .ul);
    defer z.destroyNode(fragment_root);

    z.appendFragment(ul, fragment_root);
    try z.normalize(allocator, ul_element.?);
    const html = try z.outerHTML(allocator, z.nodeToElement(ul).?);
    defer allocator.free(html);
    try testing.expectEqualStrings("<ul id=\"ul\"><li>Firefox</li><li>Chrome</li><li>Opera</li><li>Safari</li><li>Internet Explorer</li></ul>", html);
}

/// Cross document fragment parsing and appending into a document
///
/// The fragment nodes are cloned into an existing document
pub fn parseFragmentInto(
    allocator: std.mem.Allocator,
    target_doc: *z.HTMLDocument,
    target_parent: *z.DomNode,
    html_fragment: []const u8,
    context: z.FragmentContext,
) !void {
    const fragment_result = try parseFragment(
        allocator,
        target_parent,
        html_fragment,
        context,
    );
    defer fragment_result.deinit();

    const children = try fragment_result.getNodes(allocator);
    defer allocator.free(children);

    // Clone each node into the target document and append
    for (children) |child| {
        // const imported_node = z.importNode(child, target_doc);
        const cloned_node = z.cloneNode(child, target_doc);
        z.appendChild(target_parent, cloned_node.?);
    }
}

test "parseFragmentInto: multiple fragment composition" {
    const allocator = testing.allocator;

    // Create a target document to compose fragments into
    const doc = try z.parseFromString("<html><body><div id='app'></div></body></html>");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);

    const app_div = z.getElementById(body, "app");
    const app_node = z.elementToNode(app_div.?);

    // Parse and add header fragment
    const header_fragment = "<header><h1>My App</h1><nav>Navigation</nav></header>";

    try parseFragmentInto(
        allocator,
        doc,
        app_node,
        header_fragment,
        .body,
    );

    // Parse and add main content fragment
    const main_fragment =
        \\<main>
        \\  <section class="content">
        \\    <p>Main content here</p>
        \\  </section>
        \\</main>
    ;
    try parseFragmentInto(
        allocator,
        doc,
        app_node,
        main_fragment,
        .body,
    );

    // Parse and add footer fragment
    const footer_fragment = "<footer><p>&copy; 2024 My Company</p></footer>";

    try parseFragmentInto(
        allocator,
        doc,
        app_node,
        footer_fragment,
        .body,
    );

    // Verify the composition
    const app_children = try z.children(allocator, app_div.?);
    defer allocator.free(app_children);

    try testing.expect(app_children.len == 3); // header, main, footer
    try testing.expectEqualStrings(
        "HEADER",
        z.tagName_zc(app_children[0]),
    );
    try testing.expect(
        .main == z.tagFromElement(app_children[1]),
    );
    try testing.expect(z.matchesTagName(
        app_children[2],
        "footer",
    ));

    const final_html = try z.innerHTML(allocator, app_div.?);
    defer allocator.free(final_html);

    try testing.expect(std.mem.indexOf(u8, final_html, "<header>") != null);
    try testing.expect(std.mem.indexOf(u8, final_html, "<main>") != null);
    try testing.expect(std.mem.indexOf(u8, final_html, "<footer>") != null);
}

/// [fragment] Fragment parsing result
///
/// Caller must use `deinit()` to free the underlying document.
///
/// Methods exposed: `appendFragment()`,`getNodes()`, `getElements()`, `serializeFlat()`, `deinit()`
pub const FragmentResult = struct {
    allocator: std.mem.Allocator,
    working_document: *z.HTMLDocument,
    target_node: *z.DomNode,
    fragment_root: *z.DomNode,

    pub fn deinit(self: FragmentResult) void {
        // z.destroyNode(self.fragment_root);
        z.destroyDocument(self.working_document);
    }

    pub fn appendFragment(self: FragmentResult, target_node: *z.DomNode) !void {
        const children = try self.getNodes(self.allocator);
        defer self.allocator.free(children);
        const target_doc = z.ownerDocument(target_node);

        // Clone each node into the target document and append
        for (children) |child| {
            const imported_node = z.importNode(child, target_doc);
            // const cloned_node = z.cloneNode(child, target_doc);
            z.appendChild(target_node, imported_node);
        }
    }
    /// Get all top-level nodes from the fragment
    pub fn getNodes(self: FragmentResult, allocator: std.mem.Allocator) ![]*z.DomNode {
        return z.childNodes(allocator, self.fragment_root);
    }

    /// Get all top-level elements from the fragment (skipping text nodes)
    ///
    /// Caller must free the allocated slice
    pub fn getElements(self: FragmentResult, allocator: std.mem.Allocator) ![]*z.HTMLElement {
        const all_nodes = try self.getNodes(allocator);
        defer allocator.free(all_nodes);

        var elements: std.ArrayList(*z.HTMLElement) = .empty;
        for (all_nodes) |node| {
            if (z.nodeToElement(node)) |element| {
                try elements.append(allocator, element);
            }
        }
        return elements.toOwnedSlice(allocator);
    }

    /// Serialize the fragment back to HTML
    ///
    /// Caller must free the allocated slice
    pub fn serializeFlat(self: FragmentResult, allocator: std.mem.Allocator) ![]u8 {
        try z.normalize(
            allocator,
            z.nodeToElement(self.fragment_root).?,
        );
        // Serialize the fragment_root's innerHTML
        return z.innerHTML(
            allocator,
            z.nodeToElement(self.fragment_root).?,
        );
    }
};

/// [fragment] Parse an HTML fragment with specified context
///
/// Caller must call `result.deinit()` to free the underlying document.
///
/// You have access to:
/// - the child elements with the allocated `result.getElements()`
/// - the child nodes with the allocated `result.getNodes()`
/// - the serialized normalized HTML with the allocated `result.serializeFlat()`.
/// ## Example
/// ```
/// const body = try bodyNode(doc);
/// const result = try parseFragment(allocator, fragment, context);
/// defer result.deinit();
/// result.appendFragment(body);
/// ```
pub fn parseFragment(
    allocator: std.mem.Allocator,
    target_node: *z.DomNode,
    html_fragment: []const u8,
    context: z.FragmentContext,
) !FragmentResult {

    // Create a new document for the fragment
    const doc = try z.createDocument();

    // Create context element that determines parsing rules
    const tag_name = context.toTagName();
    const context_element = z.createElement(doc, tag_name) catch {
        z.destroyDocument(doc);
        return Err.CreateElementFailed;
    };

    // Parse the fragment within the context into a new #document-fragment
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
        .allocator = allocator,
        .working_document = doc,
        .target_node = target_node,
        .fragment_root = parse_root,
    };
}

// ============================================================================
// TESTS AND EXAMPLES
// ============================================================================

test "parseFragment: template component parsing" {
    const allocator = testing.allocator;
    // insert into a new document
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const body_elt = try z.createElement(doc, "body");

    const component_template =
        \\<div class="user-card" data-user-id="{{id}}">
        \\  <img src="{@avatar}" alt="{{name}}" class="avatar">
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

    const expected = "<div class=\"user-card\" data-user-id=\"{{id}}\"><img src=\"{@avatar}\" alt=\"{{name}}\" class=\"avatar\"><div class=\"user-info\"><h4>{{name}}</h4><p class=\"role\">{{role}}</p><span class=\"status {{status_class}}\">{{status}}</span></div><div class=\"actions\"><button data-action=\"message\">Message</button><button data-action=\"follow\">Follow</button></div></div>";

    const result = try parseFragment(
        allocator,
        z.elementToNode(body_elt),
        component_template,
        .template,
    );
    defer result.deinit();

    try testing.expect(!z.isNodeEmpty(result.fragment_root));

    // Check serialization
    const serializedFlatFragment = try result.serializeFlat(allocator);
    defer allocator.free(serializedFlatFragment);
    try testing.expectEqualStrings(expected, serializedFlatFragment);
    // try testing.expect(std.mem.indexOf(u8, serializedFlatFragment, "{{name}}") != null);
    // try testing.expect(std.mem.indexOf(u8, serializedFlatFragment, "{@avatar}") != null);
    // try testing.expect(std.mem.indexOf(u8, serializedFlatFragment, "user-card") != null);

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);
    try testing.expect(elements.len == 1);

    try result.appendFragment(z.elementToNode(body_elt));

    const new_html = try z.innerHTML(allocator, body_elt);
    defer allocator.free(new_html);
    try testing.expectEqualStrings(expected, new_html);
}

test "parseFragment parsing table" {
    const allocator = testing.allocator;
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);
    const body_elt = try z.createElement(doc, "body");

    const table_fragment =
        \\<tbody>
        \\<tr>
        \\  <td>John</td>
        \\  <td>Designer</td>
        \\  <td>$85,000</td>
        \\</tr>
        \\<tr>
        \\  <td>Jane</td>
        \\  <td>Dev</td>
        \\  <td>$85,000</td>
        \\</tr>
        \\</tbody>
    ;

    // Parse in the context of a table
    const result = try parseFragment(
        allocator,
        z.elementToNode(body_elt),
        table_fragment,
        .tbody,
    );
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    // print("Table elements found: {}\n", .{elements.len});
    // for (elements, 0..) |element, i| {
    //     print("Element {}: {s}\n", .{ i, z.tagName_zc(element) });
    // }

    const serialized = try result.serializeFlat(allocator);
    defer allocator.free(serialized);
    const expected = "<tr><td>John</td><td>Designer</td><td>$85,000</td></tr><tr><td>Jane</td><td>Dev</td><td>$85,000</td></tr>";
    try testing.expectEqualStrings(expected, serialized);
}

test "select options fragment" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);

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
        body,
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
    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);

    const list_items_fragment =
        \\<li>First item</li>
        \\<li>Second item</li>
        \\<li>Third item</li>
    ;

    // Test with unordered list context
    const ul_result = try parseFragment(
        allocator,
        body,
        list_items_fragment,
        .ul,
    );
    defer ul_result.deinit();

    const ul_elements = try ul_result.getElements(allocator);
    defer allocator.free(ul_elements);

    try testing.expect(ul_elements.len == 3);
    try testing.expectEqualStrings("LI", z.tagName_zc(ul_elements[0]));
    try testing.expectEqualStrings("LI", z.tagName_zc(ul_elements[1]));
    try testing.expectEqualStrings("LI", z.tagName_zc(ul_elements[2]));

    // Test with ordered list context
    const ol_result = try parseFragment(
        allocator,
        body,
        list_items_fragment,
        .ol,
    );
    defer ol_result.deinit();

    const ol_elements = try ol_result.getElements(allocator);
    defer allocator.free(ol_elements);

    try testing.expect(ol_elements.len == 3);
    try testing.expectEqualStrings("LI", z.tagName_zc(ol_elements[0]));

    const ol_serialized = try ol_result.serializeFlat(allocator);
    defer allocator.free(ol_serialized);

    // Verify content is preserved
    try testing.expect(std.mem.indexOf(u8, ol_serialized, "First item") != null);
    try testing.expect(std.mem.indexOf(u8, ol_serialized, "Second item") != null);
    try testing.expect(std.mem.indexOf(u8, ol_serialized, "Third item") != null);
}

test "definition list fragments" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);

    const dl_fragment =
        \\<dt>Term 1</dt>
        \\<dd>Definition for term 1</dd>
        \\<dt>Term 2</dt>  
        \\<dd>Definition for term 2</dd>
    ;

    const result = try parseFragment(
        allocator,
        body,
        dl_fragment,
        .dl,
    );
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 4); // 2 dt + 2 dd elements
    try testing.expectEqualStrings("DT", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("DD", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("DT", z.tagName_zc(elements[2]));
    try testing.expectEqualStrings("DD", z.tagName_zc(elements[3]));

    const serialized = try result.serializeFlat(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "Term 1") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "Definition for term 1") != null);
}

test "fieldset legend fragments" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);

    const fieldset_fragment =
        \\<legend>Contact Information</legend>
        \\<label for="name">Name:</label>
        \\<input type="text" id="name" name="name">
    ;

    const result = try parseFragment(
        allocator,
        body,
        fieldset_fragment,
        .fieldset,
    );
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
    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);

    const details_fragment =
        \\<summary>Click to expand</summary>
        \\<p>This content is hidden by default</p>
        \\<ul>
        \\  <li>Item 1</li>
        \\  <li>Item 2</li>
        \\</ul>
    ;

    const result = try parseFragment(
        allocator,
        body,
        details_fragment,
        .details,
    );
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
    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);

    const optgroup_fragment =
        \\<option value="ny">New York</option>
        \\<option value="ca">California</option>
        \\<option value="tx">Texas</option>
    ;

    const result = try parseFragment(
        allocator,
        body,
        optgroup_fragment,
        .optgroup,
    );
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 3);
    try testing.expectEqualStrings("OPTION", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("OPTION", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("OPTION", z.tagName_zc(elements[2]));

    const serialized = try result.serializeFlat(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "New York") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "California") != null);
}

test "image map area fragments" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);

    const map_fragment =
        \\<area shape="rect" coords="0,0,100,100" href="/section1" alt="Section 1">
        \\<area shape="circle" coords="150,75,50" href="/section2" alt="Section 2">
        \\<area shape="poly" coords="200,0,250,50,200,100,150,50" href="/section3" alt="Section 3">
    ;

    const result = try parseFragment(
        allocator,
        body,
        map_fragment,
        .map,
    );
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
    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);

    const figure_fragment =
        \\<img src="/chart.png" alt="Sales Chart" width="400" height="300">
        \\<figcaption>Monthly sales performance for Q4 2024</figcaption>
    ;

    const result = try parseFragment(
        allocator,
        body,
        figure_fragment,
        .figure,
    );
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 2); // img + figcaption
    try testing.expectEqualStrings("IMG", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("FIGCAPTION", z.tagName_zc(elements[1]));

    const serialized = try result.serializeFlat(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "/chart.png") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "Monthly sales") != null);
}

test "form input fragments" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);

    const form_fragment =
        \\<label for="email">Email Address:</label>
        \\<input type="email" id="email" name="email" required>
        \\<label for="password">Password:</label>
        \\<input type="password" id="password" name="password" required>
        \\<button type="submit">Login</button>
    ;

    const result = try parseFragment(
        allocator,
        body,
        form_fragment,
        .form,
    );
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 5); // 2 labels + 2 inputs + 1 button
    try testing.expectEqualStrings("LABEL", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("INPUT", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("LABEL", z.tagName_zc(elements[2]));
    try testing.expectEqualStrings("INPUT", z.tagName_zc(elements[3]));
    try testing.expectEqualStrings("BUTTON", z.tagName_zc(elements[4]));

    const serialized = try result.serializeFlat(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "Email Address") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "type=\"email\"") != null);
}

test "video with sources" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);

    const video_fragment =
        \\<source src="/video.webm" type="video/webm">
        \\<source src="/video.mp4" type="video/mp4">
        \\<track kind="captions" src="/captions.vtt" srclang="en" label="English">
        \\<p>Your browser doesn't support HTML5 video.</p>
    ;

    const result = try parseFragment(
        allocator,
        body,
        video_fragment,
        .video,
    );
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 4); // 2 sources + 1 track + 1 p
    try testing.expectEqualStrings("SOURCE", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("SOURCE", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("TRACK", z.tagName_zc(elements[2]));
    try testing.expectEqualStrings("P", z.tagName_zc(elements[3]));

    const serialized = try result.serializeFlat(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "video.webm") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "captions.vtt") != null);
}

test "audio with sources" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);

    const audio_fragment =
        \\<source src="/audio.ogg" type="audio/ogg">
        \\<source src="/audio.mp3" type="audio/mp3">
        \\<track kind="descriptions" src="/descriptions.vtt" srclang="en">
        \\<p>Your browser doesn't support HTML5 audio.</p>
    ;

    const result = try parseFragment(
        allocator,
        body,
        audio_fragment,
        .audio,
    );
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
    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);

    const picture_fragment =
        \\<source media="(min-width: 800px)" srcset="/hero-large.jpg">
        \\<source media="(min-width: 400px)" srcset="/hero-medium.jpg">
        \\<img src="/hero-small.jpg" alt="Hero image">
    ;

    const result = try parseFragment(
        allocator,
        body,
        picture_fragment,
        .picture,
    );
    defer result.deinit();

    const elements = try result.getElements(allocator);
    defer allocator.free(elements);

    try testing.expect(elements.len == 3); // 2 sources + 1 img
    try testing.expectEqualStrings("SOURCE", z.tagName_zc(elements[0]));
    try testing.expectEqualStrings("SOURCE", z.tagName_zc(elements[1]));
    try testing.expectEqualStrings("IMG", z.tagName_zc(elements[2]));

    const serialized = try result.serializeFlat(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "hero-large.jpg") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "min-width: 800px") != null);
}

test "malformed fragment part recovery by lexbor" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<html><body></body></html>");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);

    const malformed_fragment =
        \\<div class="card">
        \\  <h3>Title</h3>
        \\  <p>Missing closing tags
        \\      <span>More content
        \\</div>
    ;

    try parseFragmentInto(
        allocator,
        doc,
        body,
        malformed_fragment,
        .body,
    );

    const body_elt = z.nodeToElement(body);

    try z.normalize(allocator, body_elt.?);

    const serialized = try z.outerHTML(allocator, body_elt.?);
    defer allocator.free(serialized);

    // lexbor should auto-fix part of the malformed HTML
    const expected_recovered = "<body><div class=\"card\"><h3>Title</h3><p>Missing closing tags\n      <span>More content\n</span></p></div></body>";
    try testing.expectEqualStrings(expected_recovered, serialized);
}

test "show" {
    const allocator = testing.allocator;

    const doc = try z.parseFromString("");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);

    const main_elt = try z.createElement(doc, "main");
    const div_elt = try z.createElementAttr(
        doc,
        "div",
        &.{.{ .name = "class", .value = "container-list" }},
    );

    const div = z.elementToNode(div_elt);
    const main = z.elementToNode(main_elt);

    const comment_node = try z.createComment(doc, "a comment");
    z.appendChild(div, z.commentToNode(comment_node));

    const ul_elt = try z.createElementAttr(doc, "ul", &.{});
    const ul = z.elementToNode(ul_elt);

    for (1..4) |i| {
        const inner_content = try std.fmt.allocPrint(
            allocator,
            "<li data-id=\"{d}\">Item {d}</li>",
            .{ i, i },
        );
        defer allocator.free(inner_content);

        const temp_div_elt = try z.createElement(doc, "div");
        const temp_div = z.elementToNode(temp_div_elt);

        _ = try z.setInnerHTML(temp_div_elt, inner_content);

        // Move the LI element to the UL
        if (z.firstChild(temp_div)) |li| {
            z.appendChild(ul, li);
        }
        z.destroyNode(temp_div);
    }
    z.appendChild(div, ul);
    z.appendChild(main, div);
    z.appendChild(body, main);

    const fragment_elt = try z.createDocumentFragment(doc);
    const fragment_node = z.fragmentNode(fragment_elt);
    try testing.expect(
        z.nodeType(fragment_node) == z.NodeType.fragment,
    ); // #document-fragment

    z.appendFragment(main, fragment_node);

    // const lis = try z.getElementsByTagName(doc, "LI");
    // defer if (lis) |collection| {
    //     z.destroyCollection(collection);
    // };
    // const li_count = z.collectionLength(lis.?);
    // try testing.expect(li_count == 3);

    const fragment_txt = try z.outerHTML(allocator, z.nodeToElement(main).?);

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

    const expected = try z.normalizeText(allocator, pretty_expected, .{});
    defer allocator.free(expected);

    try testing.expectEqualStrings(expected, fragment_txt);
}

test "set fragment with order" {
    const allocator = testing.allocator;

    const pretty_html =
        \\<table id="producttable">
        \\  <thead>
        \\    <tr>
        \\      <td>UPC_Code</td>
        \\      <td>Product_Name</td>
        \\    </tr>
        \\  </thead>
        \\  <tbody>
        \\    <!-- existing data could optionally be included here -->
        \\  </tbody>
        \\</table>
    ;
    const initial_html = try z.normalizeText(
        allocator,
        pretty_html,
        .{},
    );
    defer allocator.free(initial_html);

    const doc = try z.parseFromString(initial_html);
    defer z.destroyDocument(doc);

    const body = try z.bodyNode(doc);

    const tbody = z.getElementByTag(body, .tbody);

    try z.parseFragmentInto(
        allocator,
        doc,
        z.elementToNode(tbody.?),
        "<tr><td class=\"record\">Code: 1</td><td>Name: 1</td></tr><tr><td class=\"record\">Code: 2</td><td>Name: 2</td></tr>",
        .tbody,
    );

    // try useTemplate(template, z.elementToNode(tbody.?));
    const resulting_html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(resulting_html);

    const expected_pretty =
        \\<body>
        \\  <table id="producttable">
        \\    <thead>
        \\      <tr>
        \\        <td>UPC_Code</td>
        \\        <td>Product_Name</td>
        \\      </tr>
        \\    </thead>
        \\    <tbody>
        \\      <!-- existing data could optionally be included here -->
        \\      <tr>
        \\        <td class="record">Code: 1</td>
        \\        <td>Name: 1</td>
        \\      </tr>
        \\      <tr>
        \\        <td class="record">Code: 2</td>
        \\        <td>Name: 2</td>
        \\      </tr>
        \\    </tbody>
        \\  </table>
        \\</body>
    ;

    const serialized = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(serialized);
    const normalized_expected = try z.normalizeText(allocator, expected_pretty, .{});
    defer allocator.free(normalized_expected);

    try testing.expectEqualStrings(normalized_expected, serialized);

    // try z.printDocumentStructure(doc);
}

test "yet another insert test" {
    const allocator = testing.allocator;

    const pretty_html =
        \\<table id="producttable">
        \\  <thead>
        \\    <tr>
        \\      <td>UPC_Code</td>
        \\      <td>Product_Name</td>
        \\    </tr>
        \\  </thead>
        \\  <tbody>
        \\    <!-- existing data could optionally be included here -->
        \\  </tbody>
        \\</table>
    ;
    const initial_html = try z.normalizeText(
        allocator,
        pretty_html,
        .{},
    );
    defer allocator.free(initial_html);

    const doc = try z.parseFromString(initial_html);
    defer z.destroyDocument(doc);

    const body = try z.bodyNode(doc);

    const tbody = z.getElementByTag(body, .tbody);

    try z.parseFragmentInto(
        allocator,
        doc,
        z.elementToNode(tbody.?),
        "<tr><td class=\"record\">Code: 1</td><td>Name: 1</td></tr>",
        .tbody,
    );
    try z.parseFragmentInto(
        allocator,
        doc,
        z.elementToNode(tbody.?),
        "<tr><td class=\"record\">Code: 2</td><td>Name: 2</td></tr>",
        .tbody,
    );

    // try useTemplate(template, z.elementToNode(tbody.?));
    const resulting_html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(resulting_html);

    const expected_pretty =
        \\<body>
        \\  <table id="producttable">
        \\    <thead>
        \\      <tr>
        \\        <td>UPC_Code</td>
        \\        <td>Product_Name</td>
        \\      </tr>
        \\    </thead>
        \\    <tbody>
        \\      <!-- existing data could optionally be included here -->
        \\      <tr>
        \\        <td class="record">Code: 1</td>
        \\        <td>Name: 1</td>
        \\      </tr>
        \\      <tr>
        \\        <td class="record">Code: 2</td>
        \\        <td>Name: 2</td>
        \\      </tr>
        \\    </tbody>
        \\  </table>
        \\</body>
    ;

    const serialized = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(serialized);
    const normalized_expected = try z.normalizeText(allocator, expected_pretty, .{});
    defer allocator.free(normalized_expected);

    try testing.expectEqualStrings(normalized_expected, serialized);
}
