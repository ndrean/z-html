//! Template module for handling HTML templates

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

pub const Template = z.Template;

const testing = std.testing;
const print = std.debug.print;

extern "c" fn lxb_html_create_template_element_wrapper(doc: *z.HTMLDocument) ?*z.HTMLTemplateElement;
extern "c" fn lxb_html_template_element_interface_destroy(template_elt: *z.HTMLTemplateElement) *z.HTMLTemplateElement;

// extern "c" fn lexbor_dom_interface_node_wrapper(obj: *anyopaque) *z.DomNode;
extern "c" fn lxb_html_template_to_element(template: *z.HTMLTemplateElement) *z.HTMLElement;
extern "c" fn lxb_node_to_template_wrapper(node: *z.DomNode) ?*z.HTMLTemplateElement;
extern "c" fn lxb_element_to_template_wrapper(element: *z.HTMLElement) ?*z.HTMLTemplateElement;

extern "c" fn lxb_html_template_content_wrapper(template: *z.HTMLTemplateElement) *z.DocumentFragment;
extern "c" fn lxb_html_template_to_node(template: *z.HTMLTemplateElement) *z.DomNode;
extern "c" fn lxb_html_tree_node_is_wrapper(node: *z.DomNode, tag_id: u32) bool;
extern "c" fn lexbor_clone_node_deep(node: *z.DomNode, target_doc: *z.HTMLDocument) *z.DomNode;

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
pub fn templateToNode(template: *z.HTMLTemplateElement) ?*z.DomNode {
    return lxb_html_template_to_node(template);
    // return lexbor_dom_interface_node_wrapper(template);
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

/// [template] Get the content of a template
pub fn templateContent(template: *z.HTMLTemplateElement) *z.DocumentFragment {
    return lxb_html_template_content_wrapper(template);
}

/// [template] JS `importNode` equivalent for templates
pub fn importNode(node: *z.DomNode, target_doc: *z.HTMLDocument) *z.DomNode {
    return lexbor_clone_node_deep(node, target_doc);
}

/// Populate template content by parsing HTML fragment
pub fn setTemplateContent(
    allocator: std.mem.Allocator,
    template_elem: *z.HTMLTemplateElement,
    html_fragment: []const u8,
) !void {
    const template_content = templateContent(template_elem);

    const fragment_result = try z.parseFragment(
        allocator,
        html_fragment,
        .template,
    );
    defer fragment_result.deinit();

    // Get all parsed nodes
    const parsed_nodes = try fragment_result.getNodes(allocator);
    defer allocator.free(parsed_nodes);

    // Clone each node into the template's document and append to template content
    const template_doc = z.ownerDocument(z.templateToNode(template_elem).?);
    const template_content_node = z.fragmentToNode(template_content);

    for (parsed_nodes) |node| {
        const cloned_node = importNode(node, template_doc);
        z.appendChild(template_content_node, cloned_node);
    }
}

pub fn useTemplate(template: *z.HTMLTemplateElement, target: *z.DomNode) !void {
    const template_content = templateContent(template);
    const content_node = z.fragmentToNode(template_content);

    const template_doc = z.ownerDocument(z.templateToNode(template).?);
    const cloned_content = importNode(content_node, template_doc);

    // Append the clone
    z.appendFragment(target, cloned_content);
}

test "setTemplateContent" {
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

    const initial_html = try z.normalizeWhitespace(allocator, pretty_html, .{});
    defer allocator.free(initial_html);

    const doc = try z.parseFromString(initial_html);
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);
    const txt = try z.serializeToString(allocator, body);
    defer allocator.free(txt);

    // check body serialization (remove whitespaces and empoty text nodes)
    try testing.expectEqualStrings(
        "<body><table id=\"producttable\"><thead><tr><td>UPC_Code</td><td>Product_Name</td></tr></thead><tbody><!-- existing data could optionally be included here --></tbody></table><template id=\"productrow\"><tr><td class=\"record\">Code: 1</td><td>Name: 1</td></tr></template></body>",
        txt,
    );

    const template_elt = z.getElementById(body, "productrow");
    try testing.expect(isTemplate(z.elementToNode(template_elt.?)));
    try testing.expect(z.isNodeEmpty(z.elementToNode(template_elt.?)));

    const temp_html = try z.serializeElement(allocator, template_elt.?);
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
    try useTemplate(template, tbody_node);
    try useTemplate(template, tbody_node);

    const resulting_html = try z.serializeToString(allocator, body);
    defer allocator.free(resulting_html);

    const target_pretty_html =
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

    const target_serialized_html = try z.normalizeWhitespace(
        allocator,
        target_pretty_html,
        .{},
    );
    defer allocator.free(target_serialized_html);

    // check resulting HTML
    try testing.expectEqualStrings(target_serialized_html, resulting_html);

    try z.printDocumentStructure(doc);
}

pub fn populateTemplateDirect(
    allocator: std.mem.Allocator,
    template_elem: *z.HTMLTemplateElement,
    html_fragment: []const u8,
) !void {
    const template_content = z.templateContent(template_elem) orelse
        return error.NoTemplateContent;

    const template_node = z.templateToNode(template_elem);
    const template_doc = z.nodeOwnerDocument(template_node);

    // Create context element in the same document as the template
    const context_element = try z.createElement(template_doc, "template", &.{}) orelse return error.CreateElementFailed;

    // Parse fragment directly in template's document
    const parse_root = try z.parseFragment(
        template_doc,
        html_fragment,
        context_element,
    ) orelse return error.ParseFailed;

    // Move parsed children to template content (no cloning needed)
    const template_content_node = z.fragmentToNode(template_content);
    const children = try z.getChildNodes(allocator, parse_root);
    defer allocator.free(children);

    for (children) |child| {
        z.appendChild(template_content_node, child);
    }
}
