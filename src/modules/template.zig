//! Template module for handling HTML templates

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

pub const Template = z.Template;

const testing = std.testing;
const print = std.debug.print;

extern "c" fn lxb_html_create_template_element_wrapper(doc: *z.HTMLDocument) ?*z.HTMLTemplateElement;
extern "c" fn lxb_html_template_element_interface_destroy(template_elt: *z.HTMLTemplateElement) *z.HTMLTemplateElement;

extern "c" fn lxb_html_template_to_element(template: *z.HTMLTemplateElement) *z.HTMLElement;
extern "c" fn lxb_node_to_template_wrapper(node: *z.DomNode) ?*z.HTMLTemplateElement;
extern "c" fn lxb_element_to_template_wrapper(element: *z.HTMLElement) ?*z.HTMLTemplateElement;

extern "c" fn lxb_html_template_content_wrapper(template: *z.HTMLTemplateElement) *z.DocumentFragment;
extern "c" fn lxb_html_template_to_node(template: *z.HTMLTemplateElement) *z.DomNode;
extern "c" fn lxb_html_tree_node_is_wrapper(node: *z.DomNode, tag_id: u32) bool;

/// [template] Create a template
pub fn createTemplate(doc: *z.HTMLDocument) !*z.HTMLTemplateElement {
    return lxb_html_create_template_element_wrapper(doc) orelse Err.CreateTemplateFailed;
}

/// [template] Destroy a template in the document
pub fn destroyTemplate(template: *z.HTMLTemplateElement) void {
    _ = lxb_html_template_element_interface_destroy(template);
}

/// [template] Check if a node is a template element
pub fn isTemplate(node: *z.DomNode) bool {
    return lxb_html_tree_node_is_wrapper(node, z.LXB_TAG_TEMPLATE);
}

/// [template] Cast template to node
pub fn templateToNode(template: *z.HTMLTemplateElement) *z.DomNode {
    return lxb_html_template_to_node(template);
}

/// [template] Cast template to element
pub fn templateToElement(template: *z.HTMLTemplateElement) *z.HTMLElement {
    return lxb_html_template_to_element(template);
}

/// [template] Get the template element from a node
pub fn nodeToTemplate(node: *z.DomNode) ?*z.HTMLTemplateElement {
    return lxb_node_to_template_wrapper(node);
}

/// [template] Get the template element from an element
pub fn elementToTemplate(element: *z.HTMLElement) ?*z.HTMLTemplateElement {
    return lxb_element_to_template_wrapper(element);
}

/// [template] Get the content of a template as a #document-fragment
pub fn templateContent(template: *z.HTMLTemplateElement) *z.DocumentFragment {
    return lxb_html_template_content_wrapper(template);
}

/// [template] Clone then content of a template element into a target node
pub fn useTemplateElement(template: *z.HTMLTemplateElement, target: *z.DomNode) !void {
    const template_content = templateContent(template);
    const content_node = z.fragmentToNode(template_content);

    const template_doc = z.ownerDocument(z.templateToNode(template));
    // same document => cloneNode()
    const cloned_content = z.cloneNode(content_node, template_doc);

    if (cloned_content) |content| {
        z.appendFragment(target, content);
    }
}

test "use template string" {
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
        .{},
    );
    defer allocator.free(initial_html);

    const doc = try z.createDocFromString(initial_html);
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;

    const txt = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(txt);

    // check body serialization (remove whitespaces and empty text nodes)
    try testing.expectEqualStrings(
        "<body><table id=\"producttable\"><thead><tr><td>UPC_Code</td><td>Product_Name</td></tr></thead><tbody><!-- existing data could optionally be included here --></tbody></table><template id=\"productrow\"><tr><td class=\"record\">Code: 1</td><td>Name: 1</td></tr></template></body>",
        txt,
    );

    const template_elt = z.getElementById(body, "productrow");
    defer z.destroyNode(z.elementToNode(template_elt.?));
    try testing.expect(isTemplate(z.elementToNode(template_elt.?)));
    try testing.expect(z.isNodeEmpty(z.elementToNode(template_elt.?)));

    const temp_html = try z.outerHTML(allocator, template_elt.?);
    defer allocator.free(temp_html);

    // check template serialization
    try testing.expectEqualStrings(
        "<template id=\"productrow\"><tr><td class=\"record\">Code: 1</td><td>Name: 1</td></tr></template>",
        temp_html,
    );

    const template = z.elementToTemplate(template_elt.?).?;
    const tbody = z.getElementByTag(body, .tbody);
    const tbody_node = z.elementToNode(tbody.?);

    // add twice the template
    try useTemplateElement(template, tbody_node);
    try useTemplateElement(template, tbody_node);

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

    const expected_serialized_html = try z.normalizeText(
        allocator,
        expected_pretty_html,
        .{},
    );
    defer allocator.free(expected_serialized_html);

    // check resulting HTML
    try testing.expectEqualStrings(expected_serialized_html, resulting_html);

    // try z.printDocumentStructure(doc);
}
