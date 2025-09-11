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

/// [fragment] Append all children from a document fragment to a parent node
///
/// The fragment is emptied: the fragment children are moved into the DOM, not copied
pub fn appendFragment(parent: *z.DomNode, fragment: ?*z.DomNode) void {
    if (fragment == null) return;
    var fragment_child = z.firstChild(fragment.?);
    while (fragment_child != null) {
        // capture next_sibling before moving it!!
        const next_sibling = z.nextSibling(fragment_child.?);
        // Remove from fragment first, then append to parent: this moves the node
        z.removeNode(fragment_child.?);
        z.appendChild(parent, fragment_child.?);
        fragment_child = next_sibling;
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
    z.appendFragment(body, fragment_root);

    // fragment is now empty
    try testing.expect(z.isNodeEmpty(fragment_root));

    const body_nodes = try z.childNodes(allocator, body);
    defer allocator.free(body_nodes);
    try testing.expect(body_nodes.len == 2);

    // The nodes should now be in the body, not the fragment
    try testing.expect(z.firstChild(body) == p);
    try testing.expect(z.nextSibling(p) == z.elementToNode(div_elt));

    // Second call to appendFragment should be safe (fragment is now empty)
    z.appendFragment(body, fragment_root);

    // Verify body still has the same 2 nodes after the second (no-op) call
    const nodes_after = try z.childNodes(allocator, body);
    defer allocator.free(nodes_after);
    try testing.expect(nodes_after.len == 2);

    z.destroyNode(fragment_root);

    // no-op handled gracefully
    z.appendFragment(body, fragment_root);
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
        z.appendFragment(target, content);
    } else {
        return Err.FragmentCloneFailed;
    }
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
