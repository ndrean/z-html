//! Fragments and Template module for handling HTML templates and document fragments.
//!
//! Document fragments are _nodes_ that have the type `.fragment` whilst templates are _elements_ with tag name `template`.
//!
//! You can append only programmatically nodes to a document fragment.
//!
//! Templates store their content in a document fragment.
//!
//! You can create templates programmatically, and append children to their content. You grab the content via the template's document fragment.
//!
//! Templates content can be populated from a parsed string.
//! This option is available in the Parser engine. This content is cloned into the given document.
//!
//! Templates are most probably already present in the DOM.
//!
//! You can retrieve their content and clone it to the document with `useTemplateElement` (via an instance of a parser engine or directly).

const std = @import("std");
const z = @import("../root.zig");
const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;

// ===
extern "c" fn lexbor_html_create_template_element_wrapper(doc: *z.HTMLDocument) ?*z.HTMLTemplateElement;
extern "c" fn lxb_html_template_element_interface_destroy(template_elt: *z.HTMLTemplateElement) *z.HTMLTemplateElement;

extern "c" fn lexbor_html_template_to_element_wrapper(template: *z.HTMLTemplateElement) *z.HTMLElement;
extern "c" fn lexbor_node_to_template_wrapper(node: *z.DomNode) ?*z.HTMLTemplateElement;
extern "c" fn lexbor_element_to_template_wrapper(element: *z.HTMLElement) ?*z.HTMLTemplateElement;

extern "c" fn lexbor_html_template_content_wrapper(template: *z.HTMLTemplateElement) *z.DocumentFragment;
extern "c" fn lexbor_html_template_to_node_wrapper(template: *z.HTMLTemplateElement) *z.DomNode;
extern "c" fn lexbor_html_tree_node_is_wrapper(node: *z.DomNode, tag_id: u32) bool;

extern "c" fn lxb_dom_document_create_document_fragment(doc: *z.HTMLDocument) ?*z.DocumentFragment;
extern "c" fn lxb_dom_document_fragment_interface_destroy(document_fragment: *z.DocumentFragment) *z.DocumentFragment;

// Extern declaration for lexbor master function
extern "c" fn lxb_dom_node_append_child(parent: *z.DomNode, child: *z.DomNode) c_int;

// === FragmentContext Html tags

/// [fragment] Fragment parsing context - defines how the fragment should be interpreted
pub const FragmentContext = enum {
    fragment,
    body,
    div,
    template,
    table,
    tbody,
    tr,
    select,
    ul,
    ol,
    dl,
    fieldset,
    details,
    optgroup,
    map,
    figure,
    form,
    video,
    audio,
    picture,
    head,
    custom,
    /// Convert context enum to HTML tag name string
    pub inline fn toTagName(self: FragmentContext) []const u8 {
        return switch (self) {
            .fragment => "html", // default root
            .body => "body",
            .div => "div",
            .template => "template",
            .table => "table",
            .tbody => "tbody",
            .tr => "tr",
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
    pub inline fn toTag(name: []const u8) ?FragmentContext {
        return z.stringToEnum(FragmentContext, name);
    }
};

test "FragmentContext" {
    try testing.expectEqualStrings(FragmentContext.toTagName(.body), "body");
    try testing.expectEqualStrings(FragmentContext.toTagName(.table), "table");
    try testing.expect(FragmentContext.toTag("div").? == .div);
}

test "fragment creation and destruction" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Test createDocumentFragment and fragmentToNode
    const fragment = try createDocumentFragment(doc);
    const fragment_node = fragmentToNode(fragment);

    try testing.expectEqualStrings("#document-fragment", z.nodeName_zc(fragment_node));
    try testing.expect(z.nodeType(fragment_node) == .fragment);
    try testing.expect(z.isNodeEmpty(fragment_node));

    // Test destroyDocumentFragment
    destroyDocumentFragment(fragment);
    // Note: After destruction, we can't safely test the fragment anymore
}

// === Document Fragment =============================================

/// [fragment] Get the underlying DOM node from a fragment
pub fn fragmentToNode(fragment: *z.DocumentFragment) *z.DomNode {
    return z.objectToNode(fragment);
}

/// [fragment] Create a document fragment and returns a DocumentFragment
///
/// Document fragments are lightweight containers that can hold multiple nodes. Useful for batch DOM operations. You can only append programmatically nodes to the fragment, no parsing into.
///
/// Browser spec: when you append a fragment to the DOM, only its children are added, not the fragment itself which is destroyed.
///
/// Use `appendFragment()` at insert the fragment into the DOM.
pub fn createDocumentFragment(doc: *z.HTMLDocument) !*z.DocumentFragment {
    return lxb_dom_document_create_document_fragment(doc) orelse Err.FragmentCreateFailed;
}

/// [fragment] Destroys a document fragment
pub fn destroyDocumentFragment(fragment: *z.DocumentFragment) void {
    _ = lxb_dom_document_fragment_interface_destroy(fragment);
    return;
}

/// [fragment] Append DocumentFragment children to parent (DOM-spec compliant)
///
/// The fragment is emptied: the fragment children are moved into the DOM, not copied.
/// This uses the new `lxb_dom_node_append_child` from lexbor master which handles
/// DocumentFragments according to DOM specification. For true DocumentFragments,
/// it moves all children and empties the fragment. For other nodes, falls back
/// to manual method.
pub fn appendFragment(parent: *z.DomNode, fragment: ?*z.DomNode) !void {
    if (fragment == null) return;

    // Check if this is a true DocumentFragment
    if (z.isTypeFragment(fragment.?)) {
        // Use the lexbor DOM-spec function for true DocumentFragments
        const result = lxb_dom_node_append_child(parent, fragment.?);
        // LXB_DOM_EXCEPTION_OK = -1, all other values are errors
        if (result != -1) {
            return Err.DomException;
        }
    } else {
        print("OLD-----\n", .{});
        // Manual method for non-DocumentFragment nodes - iterate and move each child individually
        var fragment_child = z.firstChild(fragment.?);
        while (fragment_child != null) {
            const next_sibling = z.nextSibling(fragment_child.?);
            z.removeNode(fragment_child.?);
            z.appendChild(parent, fragment_child.?);
            fragment_child = next_sibling;
        }
    }
}

test "DocumentFragment  - append programmatically only" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("");
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;

    const fragment = try createDocumentFragment(doc);
    const fragment_root = z.fragmentToNode(fragment);

    try testing.expectEqualStrings(
        "#document-fragment",
        z.nodeName_zc(fragment_root),
    );
    try testing.expect(z.isNodeEmpty(fragment_root));
    try testing.expect(z.nodeType(fragment_root) == .fragment);

    const p: *z.DomNode = @ptrCast(try z.createElement(doc, "p"));
    const div_elt = try z.createElement(doc, "div");

    // insert programmatically into the document-fragment
    z.appendChild(fragment_root, p);
    z.appendChild(fragment_root, z.elementToNode(div_elt));

    try testing.expect(!z.isNodeEmpty(fragment_root));
    try testing.expect(z.firstChild(fragment_root) == p);

    // move (not copy) the document-fragment children to the body element of the document
    try z.appendFragment(body, fragment_root);

    // fragment is now empty
    try testing.expect(z.isNodeEmpty(fragment_root));

    const body_nodes = try z.childNodes(allocator, body);
    defer allocator.free(body_nodes);
    try testing.expect(body_nodes.len == 2);

    // The nodes should now be in the body, not the fragment
    try testing.expect(z.firstChild(body) == p);
    try testing.expect(z.nextSibling(p) == z.elementToNode(div_elt));

    // Second call to appendFragment should be safe (fragment is now empty)
    try z.appendFragment(body, fragment_root);

    // Verify body still has the same 2 nodes after the second (no-op) call
    const nodes_after = try z.childNodes(allocator, body);
    defer allocator.free(nodes_after);
    try testing.expect(nodes_after.len == 2);

    z.destroyNode(fragment_root);

    // no-op handled gracefully
    try z.appendFragment(body, fragment_root);
}

test "appendFragment - regular DocumentFragment (createDocumentFragment)" {
    const allocator = testing.allocator;
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Create target container
    try z.parseString(doc, "<div id='container'></div>");
    const container_elt = z.getElementById(z.bodyNode(doc).?, "container").?;
    const container_node = z.elementToNode(container_elt);

    // Create a regular DocumentFragment (not from template)
    const fragment = try createDocumentFragment(doc);
    const fragment_root = fragmentToNode(fragment);

    // Add some elements to the fragment
    const p_elt = try z.createElement(doc, "p");
    const p_text = try z.createTextNode(doc, "First paragraph");
    z.appendChild(z.elementToNode(p_elt), p_text);
    z.appendChild(fragment_root, z.elementToNode(p_elt));

    const div_elt = try z.createElement(doc, "div");
    const div_text = try z.createTextNode(doc, "Second div");
    z.appendChild(z.elementToNode(div_elt), div_text);
    z.appendChild(fragment_root, z.elementToNode(div_elt));

    const span_elt = try z.createElement(doc, "span");
    const span_text = try z.createTextNode(doc, "Third span");
    z.appendChild(z.elementToNode(span_elt), span_text);
    z.appendChild(fragment_root, z.elementToNode(span_elt));

    // Verify fragment has 3 children before appending
    const children_before = try z.childNodes(allocator, fragment_root);
    defer allocator.free(children_before);
    try testing.expect(children_before.len == 3);

    // Verify container is empty before appending
    const container_children_before = try z.childNodes(allocator, container_node);
    defer allocator.free(container_children_before);
    try testing.expect(container_children_before.len == 0);

    // Use appendFragment to move children from fragment to container
    try z.appendFragment(container_node, fragment_root);

    // Verify fragment is now empty (children were moved)
    try testing.expect(z.isNodeEmpty(fragment_root));

    // Verify container now has the 3 children in correct order
    const container_children_after = try z.childNodes(allocator, container_node);
    defer allocator.free(container_children_after);
    try testing.expect(container_children_after.len == 3);

    // Check the order and content
    const first_child = container_children_after[0];
    const second_child = container_children_after[1];
    const third_child = container_children_after[2];

    try testing.expect(z.nodeToElement(first_child) != null);
    try testing.expect(z.nodeToElement(second_child) != null);
    try testing.expect(z.nodeToElement(third_child) != null);

    const first_elt = z.nodeToElement(first_child).?;
    const second_elt = z.nodeToElement(second_child).?;
    const third_elt = z.nodeToElement(third_child).?;

    const first_tag = try z.tagName(allocator, first_elt);
    defer allocator.free(first_tag);
    const second_tag = try z.tagName(allocator, second_elt);
    defer allocator.free(second_tag);
    const third_tag = try z.tagName(allocator, third_elt);
    defer allocator.free(third_tag);

    try testing.expectEqualStrings("P", first_tag);
    try testing.expectEqualStrings("DIV", second_tag);
    try testing.expectEqualStrings("SPAN", third_tag);

    // Verify content
    const result = try z.innerHTML(allocator, container_elt);
    defer allocator.free(result);
    try testing.expectEqualStrings("<p>First paragraph</p><div>Second div</div><span>Third span</span>", result);

    // Clean up
    z.destroyNode(fragment_root);
}

test "appendFragment - unified fragment handling" {
    const allocator = testing.allocator;

    // Test 1: Using unified appendFragment method
    {
        const doc = try z.createDocument();
        defer z.destroyDocument(doc);

        // Create target body element
        try z.parseString(doc, "");
        const body = z.bodyNode(doc).?;

        // Create a regular DocumentFragment
        const fragment1 = try createDocumentFragment(doc);
        const fragment_root1 = fragmentToNode(fragment1);

        // Add elements to fragment
        const p_elt = try z.createElement(doc, "p");
        const p_text = try z.createTextNode(doc, "Paragraph content");
        z.appendChild(z.elementToNode(p_elt), p_text);
        z.appendChild(fragment_root1, z.elementToNode(p_elt));

        const div_elt = try z.createElement(doc, "div");
        const div_text = try z.createTextNode(doc, "Div content");
        z.appendChild(z.elementToNode(div_elt), div_text);
        z.appendChild(fragment_root1, z.elementToNode(div_elt));

        const children = try z.childNodes(allocator, fragment_root1);
        defer allocator.free(children);

        // Test the new lexbor function
        try z.appendFragment(body, fragment_root1);

        const children_after = try z.childNodes(allocator, fragment_root1);
        defer allocator.free(children_after);

        // Check what actually got inserted into body
        const body_html = try z.innerHTML(allocator, z.nodeToElement(body).?);
        defer allocator.free(body_html);

        z.destroyNode(fragment_root1);
    }

    // Test 2: Using manual method (appendFragment) for comparison
    {
        const doc = try z.createDocument();
        defer z.destroyDocument(doc);

        // Create target body element
        try z.parseString(doc, "");
        const body = z.bodyNode(doc).?;

        // Create a regular DocumentFragment
        const fragment2 = try createDocumentFragment(doc);
        const fragment_root2 = fragmentToNode(fragment2);

        // Add identical elements to fragment
        const p_elt = try z.createElement(doc, "p");
        const p_text = try z.createTextNode(doc, "Paragraph content");
        z.appendChild(z.elementToNode(p_elt), p_text);
        z.appendChild(fragment_root2, z.elementToNode(p_elt));

        const div_elt = try z.createElement(doc, "div");
        const div_text = try z.createTextNode(doc, "Div content");
        z.appendChild(z.elementToNode(div_elt), div_text);
        z.appendChild(fragment_root2, z.elementToNode(div_elt));

        const children = (try z.childNodes(allocator, fragment_root2));
        defer allocator.free(children);

        // Test the manual method
        try z.appendFragment(body, fragment_root2);

        const children_after2 = try z.childNodes(allocator, fragment_root2);
        defer allocator.free(children_after2);

        // Check what actually got inserted into body
        const body_html2 = try z.innerHTML(allocator, z.nodeToElement(body).?);
        defer allocator.free(body_html2);

        z.destroyNode(fragment_root2);
    }
}

test "appendFragment with template DocumentFragment" {
    const allocator = testing.allocator;
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Create a template with content
    const template = try createTemplate(doc);
    const template_content = templateContent(template);

    // Add some elements to template content
    const template_content_node = fragmentToNode(template_content);
    const p_elt = try z.createElement(doc, "p");
    const text = try z.createTextNode(doc, "Template content");
    z.appendChild(z.elementToNode(p_elt), text);
    z.appendChild(template_content_node, z.elementToNode(p_elt));

    const div_elt = try z.createElement(doc, "div");
    const div_text = try z.createTextNode(doc, "More content");
    z.appendChild(z.elementToNode(div_elt), div_text);
    z.appendChild(template_content_node, z.elementToNode(div_elt));

    // Verify template content is a true DocumentFragment
    try testing.expect(z.isTypeFragment(template_content_node));

    const children_before = try z.childNodes(allocator, template_content_node);
    defer allocator.free(children_before);
    try testing.expectEqual(@as(usize, 2), children_before.len);

    // Clone the template content (as per DOM spec)
    const cloned_content = z.cloneNode(template_content_node) orelse return error.CloneFailed;
    defer z.destroyNode(cloned_content);

    // Verify clone is also a DocumentFragment
    try testing.expect(z.isTypeFragment(cloned_content));

    // Create target element
    try z.parseString(doc, "<div id='target'></div>");
    const target = z.getElementById(z.bodyNode(doc).?, "target").?;
    const target_node = z.elementToNode(target);

    // Test appendFragment with true DocumentFragment
    try appendFragment(target_node, cloned_content);

    // Verify fragment was emptied and target got the content
    const cloned_children_after = try z.childNodes(allocator, cloned_content);
    defer allocator.free(cloned_children_after);
    try testing.expectEqual(@as(usize, 0), cloned_children_after.len);

    const target_children_after = try z.childNodes(allocator, target_node);
    defer allocator.free(target_children_after);
    try testing.expectEqual(@as(usize, 2), target_children_after.len);

    // Verify the content
    const result_html = try z.innerHTML(allocator, target);
    defer allocator.free(result_html);
    try testing.expectEqualStrings("<p>Template content</p><div>More content</div>", result_html);

    z.destroyTemplate(template);
}

// === TEMPLATES ======================

/// [template] Create a template
pub fn createTemplate(doc: *z.HTMLDocument) !*z.HTMLTemplateElement {
    return lexbor_html_create_template_element_wrapper(doc) orelse Err.CreateTemplateFailed;
}

/// [template] Destroy a template in the document
pub fn destroyTemplate(template: *z.HTMLTemplateElement) void {
    _ = lxb_html_template_element_interface_destroy(template);
}

/// [template] Check if a node is a template element
pub fn isTemplate(node: *z.DomNode) bool {
    return lexbor_html_tree_node_is_wrapper(node, z.LXB_TAG_TEMPLATE);
}

/// [template] Cast template to node
///
/// Do not append nodes to this node but reach for the document fragment node
///
/// check test "create templates programmatically"
pub fn templateToNode(template: *z.HTMLTemplateElement) *z.DomNode {
    return lexbor_html_template_to_node_wrapper(template);
}

/// [template] Cast template to element
pub fn templateToElement(template: *z.HTMLTemplateElement) *z.HTMLElement {
    return lexbor_html_template_to_element_wrapper(template);
}

/// [template] Get the template element from a node that is a template
pub fn nodeToTemplate(node: *z.DomNode) ?*z.HTMLTemplateElement {
    return lexbor_node_to_template_wrapper(node);
}

/// [template] Get the template element from an element that is a template
pub fn elementToTemplate(element: *z.HTMLElement) ?*z.HTMLTemplateElement {
    return lexbor_element_to_template_wrapper(element);
}

/// [template] Get the content of a template as a #document-fragment
///
/// You can append nodes to `z.fragmentNode(template_content)`
pub fn templateContent(template: *z.HTMLTemplateElement) *z.DocumentFragment {
    return lexbor_html_template_content_wrapper(template);
}

/// [template] Clone the content of a template element into a target node with optional sanitization
///
/// @param allocator: Memory allocator for sanitization operations
/// @param template_elt: HTML template element to clone content from
/// @param target: Target node to append cloned content to
/// @param sanitizer: Sanitization options to apply to cloned content
pub fn useTemplateElement(
    allocator: std.mem.Allocator,
    template_elt: *z.HTMLElement,
    target: *z.DomNode,
    sanitizer: z.SanitizeOptions,
) !void {
    if (!z.isTemplate(z.elementToNode(template_elt))) return Err.NotATemplateElement;
    const template = z.elementToTemplate(template_elt).?;
    const template_content = templateContent(template);
    const content_node = z.fragmentToNode(template_content);

    const cloned_content = z.cloneNode(content_node);

    if (cloned_content) |content| {
        // Apply sanitization to cloned content before appending
        switch (sanitizer) {
            .none => {}, // No sanitization
            .minimum => try z.sanitizeWithOptions(allocator, content, .minimum),
            .strict => try z.sanitizeStrict(allocator, content),
            .permissive => try z.sanitizePermissive(allocator, content),
            .custom => |opts| try z.sanitizeWithOptions(allocator, content, .{ .custom = opts }),
        }
        // z.appendFragment(target, content);
        try appendFragment(target, content);
    } else {
        return Err.FragmentCloneFailed;
    }
}

/// [template] Get the inner HTML of the first child of a template's content
///
/// Caller needs to free the returned string
pub fn innerTemplateHTML(allocator: std.mem.Allocator, template_node: *z.DomNode) ![]const u8 {
    const template = z.elementToTemplate(z.nodeToElement(template_node).?).?;
    const template_content = templateContent(template);
    const content_node = fragmentToNode(template_content);
    const first_child = z.firstChild(content_node);
    std.debug.assert(first_child != null);
    if (first_child == null) return error.NoChildInTemplate;
    const html = try z.outerHTML(
        allocator,
        z.nodeToElement(first_child.?).?,
    );
    return html;
}

test "create template programmatically" {
    const doc = try z.createDocFromString("");
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;

    const template = try z.createTemplate(doc);
    const template_elt = z.templateToElement(template);
    try testing.expectEqualStrings("template", z.qualifiedName_zc(template_elt));

    const template_node = z.templateToNode(template);
    try testing.expectEqualStrings("TEMPLATE", z.nodeName_zc(template_node));
    try testing.expect(z.nodeType(template_node) == .element);

    const p = try z.createElement(doc, "p");

    const innerContent = templateContent(template);
    const content_node = z.fragmentToNode(innerContent);

    try testing.expectEqualStrings("#document-fragment", z.nodeName_zc(content_node));

    z.appendChild(content_node, z.elementToNode(p));

    try testing.expect(z.isNodeEmpty(body));

    // clone twice the template content into the DOM
    try useTemplateElement(testing.allocator, template_elt, body, .none);
    try useTemplateElement(testing.allocator, template_elt, body, .none);

    const child_nodes = try z.childNodes(
        testing.allocator,
        body,
    );
    defer testing.allocator.free(child_nodes);

    try testing.expect(child_nodes.len == 2);

    z.destroyTemplate(template);
}

test "use template element" {
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
        \\
        \\<template id="productrow">
        \\  <tr>
        \\    <td class="record">Code: 1</td>
        \\    <td>Name: 1</td>
        \\  </tr>
        \\</template>
    ;

    const initial_html = try z.normalizeText(
        allocator,
        pretty_html,
    );
    defer allocator.free(initial_html);

    const doc = try z.createDocFromString(initial_html);
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;

    const txt = try z.outerNodeHTML(allocator, body);
    defer allocator.free(txt);

    // check body serialization (remove whitespaces and empty text nodes)
    try testing.expectEqualStrings(
        "<body><table id=\"producttable\"><thead><tr><td>UPC_Code</td><td>Product_Name</td></tr></thead><tbody><!-- existing data could optionally be included here --></tbody></table><template id=\"productrow\"><tr><td class=\"record\">Code: 1</td><td>Name: 1</td></tr></template></body>",
        txt,
    );

    const template_elt = z.getElementById(body, "productrow").?;
    defer z.destroyNode(z.elementToNode(template_elt));
    try testing.expect(isTemplate(z.elementToNode(template_elt)));
    try testing.expect(z.isNodeEmpty(z.elementToNode(template_elt)));

    const temp_html = try z.outerHTML(allocator, template_elt);
    defer allocator.free(temp_html);

    // check template serialization
    try testing.expectEqualStrings(
        "<template id=\"productrow\"><tr><td class=\"record\">Code: 1</td><td>Name: 1</td></tr></template>",
        temp_html,
    );

    // const template = z.elementToTemplate(template_elt.?).?;
    const tbody = z.getElementByTag(body, .tbody);
    const tbody_node = z.elementToNode(tbody.?);

    const failure = useTemplateElement(allocator, tbody.?, tbody_node, .none);
    try testing.expectError(Err.NotATemplateElement, failure);

    // add twice the template
    try useTemplateElement(allocator, template_elt, tbody_node, .none);
    try useTemplateElement(allocator, template_elt, tbody_node, .none);

    const resulting_html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(resulting_html);

    const expected_pretty_html =
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
        \\        <td class="record">Code: 1</td>
        \\        <td>Name: 1</td>
        \\      </tr>
        \\    </tbody>
        \\  </table>
        \\  <template id="productrow">
        \\    <tr>
        \\      <td class="record">Code: 1</td>
        \\      <td>Name: 1</td>
        \\    </tr>
        \\  </template>
        \\</body>
    ;

    const expected_serialized_html = try z.normalizeText(allocator, expected_pretty_html);
    defer allocator.free(expected_serialized_html);

    // check resulting HTML
    try testing.expectEqualStrings(expected_serialized_html, resulting_html);

    // try z.printDocumentStructure(doc);
}

test "fragment and template utility functions" {
    const allocator = testing.allocator;

    const doc = try z.createDocFromString("<html><body></body></html>");
    defer z.destroyDocument(doc);

    // Create template programmatically first
    const template = try createTemplate(doc);
    const template_elt = templateToElement(template);
    _ = z.setAttribute(template_elt, "id", "test");

    // Add content to template
    const template_content = templateContent(template);
    const content_node = fragmentToNode(template_content);
    const p = try z.createElement(doc, "p");
    try z.setContentAsText(z.elementToNode(p), "Content");
    z.appendChild(content_node, z.elementToNode(p));

    // Add template to body for getElementById to work
    const body = z.bodyElement(doc).?;
    z.appendChild(z.elementToNode(body), z.templateToNode(template));

    const template_node = z.elementToNode(template_elt);

    // Test isTemplate
    try testing.expect(isTemplate(template_node));

    // Test nodeToTemplate and elementToTemplate
    const template_from_node = nodeToTemplate(template_node);
    const template_from_element = elementToTemplate(template_elt);
    try testing.expect(template_from_node != null);
    try testing.expect(template_from_element != null);
    try testing.expect(template_from_node.? == template);
    try testing.expect(template_from_element.? == template);

    // Test fragmentToNode with template content (already created above)
    try testing.expectEqualStrings("#document-fragment", z.nodeName_zc(content_node));

    // Test that we can work with the fragment node
    const children = try z.childNodes(allocator, content_node);
    defer allocator.free(children);
    try testing.expect(children.len == 1); // Should have the <p> element

    // Clean up functions are tested implicitly through defer statements in other tests
    destroyTemplate(template);
}

test "useTemplateElement with existing template - multiple uses" {
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
        \\
        \\<template id="productrow">
        \\  <tr>
        \\    <td class="record">Code: 1</td>
        \\    <td>Name: 1</td>
        \\  </tr>
        \\</template>
    ;

    const initial_html = try z.normalizeText(allocator, pretty_html);
    defer allocator.free(initial_html);

    const doc = try z.createDocFromString(initial_html);
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;

    // Get the existing template element from DOM
    const template_elt = z.getElementById(body, "productrow").?;
    const template = z.elementToTemplate(template_elt).?;

    const tbody = z.getElementByTag(body, .tbody).?;
    const tbody_node = z.elementToNode(tbody);

    // Use existing template element twice (HTMLElement and HTMLTemplateElement types)
    try useTemplateElement(allocator, template_elt, tbody_node, .permissive);
    try useTemplateElement(allocator, z.templateToElement(template), tbody_node, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // Should have two rows added
    var tr_count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, result, search_pos, "<tr>")) |pos| {
        tr_count += 1;
        search_pos = pos + 4;
    }
    try testing.expectEqual(@as(usize, 4), tr_count); // 1 header + 2 data rows + 1 in template

    // Verify content
    try testing.expect(std.mem.indexOf(u8, result, "Code: 1") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Name: 1") != null);
}

test "HTMX template" {
    const allocator = testing.allocator;

    // This file contains the complete HTML template for the HTMX application,
    // formatted as a Zig multiline string to use by the backend.

    const index_html =
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\<meta charset="UTF-8" />
        \\<meta name="viewport" content="width=device-width, initial-scale=1.0" />
        \\<title>HTMX + TailwindCSS Demo App</title>
        \\<script src="https://cdn.tailwindcss.com"></script>
        \\<script src="https://unpkg.com/htmx.org@1.9.10"></script>
        \\<link rel="preconnect" href="https://fonts.googleapis.com" />
        \\<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
        \\<link
        \\  href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet"/>
        \\</head>
        \\<body class="bg-gray-50 min-h-screen flex flex-col items-center p-6 font-inter">
        \\<header class="mb-8 text-center">
        \\<h1 class="text-5xl font-extrabold text-blue-600">Welcome to Demo App</h1>
        \\<p class="text-xl text-gray-700 mt-2">HTMX & TailwindCSS Frontend</p>
        \\</header>
        \\<main class="w-full max-w-6xl p-8 bg-white rounded-2xl shadow-xl">
        \\<!-- Navigation -->
        \\<nav class="flex justify-center mb-8 bg-gray-100 rounded-lg p-3 shadow-inner">
        \\<a class="px-6 py-3 font-semibold text-blue-600 rounded-lg transition-colors duration-200 hover:bg-blue-100 mr-4"
        \\          hx-get="/groceries"
        \\          hx-target="#content"
        \\          hx-push-url="true"
        \\          hx-trigger="click"
        \\          >Grocery List</a>
        \\<a class="px-6 py-3 font-semibold text-blue-600 rounded-lg transition-colors duration-200 hover:bg-blue-100"
        \\          hx-get="/shopping-list"
        \\          hx-target="#content"
        \\          hx-push-url="true"
        \\          hx-trigger="click"
        \\          >Shopping List</a>
        \\</nav>
        \\<!-- Main content area will be loaded here -->
        \\<div id="content" class="min-h-[500px] p-6 bg-gray-50 rounded-lg shadow-inner">
        \\<!-- Default content loads on initial page load -->
        \\<div class="flex items-center justify-center h-full text-center text-gray-500">
        \\<p class="text-2xl font-semibold">Select an option from the navigation menu to get started.</p>
        \\</div>
        \\</div>
        \\</main>
        \\<!-- The HTMX content for the grocery list and item details card. -->
        \\<!-- This would normally be returned by the '/groceries' backend endpoint. -->
        \\<template id="groceries-page-template">
        \\<div class="flex flex-col md:flex-row gap-8 p-4">
        \\<!-- Grocery Items List -->
        \\<div class="md:w-1/2">
        \\<h2 class="text-3xl font-bold text-gray-800 mb-6">Grocery Items</h2>
        \\<div class="space-y-4 max-h-[400px] overflow-y-auto pr-2"
        \\            hx-get="/api/items"
        \\            hx-trigger="load, every 60s"
        \\            hx-target="this"
        \\            hx-swap="innerHTML">
        \\<!-- HTMX will load the list of available items here -->
        \\<p class="text-gray-500">Loading items...</p>
        \\</div>
        \\</div>
        \\<!-- Item Details Card -->
        \\<div id="item-details-card"
        \\          class="md:w-1/2 bg-gray-100 rounded-xl p-6 shadow-lg min-h-[300px] flex items-center justify-center transition-all duration-300"
        \\          hx-get="/item-details/default"
        \\          hx-trigger="load"
        \\          hx-target="this"
        \\          hx-swap="innerHTML">
        \\<!-- HTMX will load item details here when an item is clicked -->
        \\</div>
        \\</div>
        \\</template>
        \\<!-- The HTMX content for the dedicated shopping list page. -->
        \\<!-- This would be returned by the '/shopping-list' backend endpoint. -->
        \\<template id="shopping-list-template">
        \\<div class="flex flex-col items-center">
        \\<h2 class="text-3xl font-bold text-gray-800 mb-6">Shopping List</h2>
        \\<div id="cart-content"
        \\          class="w-full max-w-xl bg-white rounded-lg p-6 shadow-md max-h-[500px] overflow-y-auto"
        \\          hx-get="/api/cart"
        \\          hx-trigger="load, every 30s"
        \\          hx-target="this"
        \\          hx-swap="innerHTML">
        \\<!-- HTMX will populate this area with the cart items -->
        \\<p class="text-gray-600 text-center">Your cart is empty.</p>
        \\</div>
        \\</div>
        \\</template>
        \\<footer class="mt-8 text-gray-500 text-sm text-center">&copy; 2025 HTMX-Z</footer>
        \\</body>
        \\</html>
    ;

    var parser = try z.Parser.init(allocator);
    defer parser.deinit();
    const doc = try parser.parse(index_html, .none);
    defer z.destroyDocument(doc);
    const html_node = z.documentRoot(doc).?;
    try z.normalizeDOMwithOptions(allocator, z.nodeToElement(html_node).?, .{ .skip_comments = true });
    var css_engine = try z.CssSelectorEngine.init(allocator);
    defer css_engine.deinit();
    const template_node = try css_engine.querySelector(html_node, "#groceries-page-template");
    try testing.expect(template_node != null);
    try testing.expect(isTemplate(template_node.?));
    const template = z.elementToTemplate(z.nodeToElement(template_node.?).?).?;
    const template_content = templateContent(template);
    const content_node = fragmentToNode(template_content);
    try testing.expectEqualStrings("#document-fragment", z.nodeName_zc(content_node));
    const first_child = z.firstChild(content_node);
    try testing.expect(first_child != null);
    try testing.expectEqualStrings("DIV", z.nodeName_zc(first_child.?));
    const txt = try z.innerHTML(allocator, z.nodeToElement(z.firstChild(content_node).?).?);
    defer allocator.free(txt);
    const res = try innerTemplateHTML(allocator, template_node.?);
    defer allocator.free(res);
}
