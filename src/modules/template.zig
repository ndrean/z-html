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
// extern "c" fn lexbor_clone_node_deep(node: *z.DomNode, target_doc: *z.HTMLDocument) *z.DomNode;
// extern "c" fn lxb_dom_document_import_node(doc: *z.HTMLDocument, node: *z.DomNode, deep: bool) *z.DomNode;

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

/// Populate template content by parsing HTML fragment
pub fn appendParsedContent(
    allocator: std.mem.Allocator,
    target_node: *z.DomNode,
    html_fragment: []const u8,
    context: z.FragmentContext,
) !void {
    print("html_fragment: {s}\n", .{html_fragment});
    const fragment_result = try z.parseFragment(
        allocator,
        html_fragment,
        context,
    );
    defer fragment_result.deinit();

    const res = try fragment_result.getElements(allocator);
    defer allocator.free(res);
    print("Elements len:{d}\n", .{res.len});

    const target_doc = z.ownerDocument(target_node);
    const parsed_nodes = try fragment_result.getNodes(allocator);
    print("parsed_nodes len: {d}\n", .{parsed_nodes.len});
    defer allocator.free(parsed_nodes);

    for (parsed_nodes) |node| {
        if (z.nodeToElement(node)) |element| {
            print("  Tag: {s}\n", .{z.tagName_zc(element)});
        }
        const cloned_node = z.importNode(node, target_doc);
        z.appendChild(target_node, cloned_node);
    }
}

// pub fn insertHTML(
//     allocator: std.mem.Allocator,
//     target: *z.DomNode,
//     html: []const u8,
//     context: z.FragmentContext,
// ) !void {
//     const target_doc = z.ownerDocument(target); // Use existing document

//     const tag_name = context.toTagName();
//     const context_element = try z.createElement(
//         target_doc,
//         tag_name,
//         &.{},
//     ); // Same doc

//     const parse_root = z.parseFragment(
//         target_doc, // ← Parse in target document directly
//         context_element,
//         html.ptr,
//         html.len,
//     ) catch {
//         return error.ParseFailed;
//     };

//     // No importNode needed - already in same document!
//     const children = try z.getChildNodes(allocator, parse_root);
//     defer allocator.free(children);

//     for (children) |child| {
//         z.appendChild(target, child); // Direct append
//     }
// }

pub fn insertHTML(
    allocator: std.mem.Allocator,
    target: *z.DomNode,
    html: []const u8,
    context: z.FragmentContext,
) !void {
    const target_doc = z.ownerDocument(target); // Use existing document

    const tag_name = context.toTagName();
    const context_element = try z.createElement(
        target_doc,
        tag_name,
        &.{},
    ); // Same doc

    defer z.destroyNode(z.elementToNode(context_element));

    const context_tag = z.FragmentContext.toTag(z.qualifiedName_zc(context_element)).?;

    const parse_root = try z.parseFragmentSimple(
        target, // ← Parse in target document directly
        html,
        context_tag,
    );

    const children = try z.childNodes(allocator, parse_root);
    defer allocator.free(children);

    for (children) |child| {
        z.appendChild(target, child);
    }
}

test "set template" {
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

    try insertHTML(
        allocator,
        z.elementToNode(tbody.?),
        "<tr><td class=\"record\">Code: 1</td><td>Name: 1</td></tr>",
        .tbody,
    );
    try insertHTML(
        allocator,
        z.elementToNode(tbody.?),
        "<tr><td class=\"record\">Code: 2</td><td>Name: 2</td></tr>",
        .tbody,
    );

    // try useTemplate(template, z.elementToNode(tbody.?));
    const resulting_html = try z.serializeToString(allocator, body);
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

    const serialized = try z.serializeToString(allocator, body);
    defer allocator.free(serialized);
    const normalized_expected = try z.normalizeText(allocator, expected_pretty, .{});
    defer allocator.free(normalized_expected);

    try testing.expectEqualStrings(normalized_expected, serialized);

    // try z.printDocumentStructure(doc);
}

pub fn useTemplate(template: *z.HTMLTemplateElement, target: *z.DomNode) !void {
    const template_content = templateContent(template);
    const content_node = z.fragmentToNode(template_content);

    const template_doc = z.ownerDocument(z.templateToNode(template).?);
    // same document => cloneNode()
    const cloned_content = z.cloneNode(content_node, template_doc);

    // Append the clone
    z.appendFragment(target, cloned_content.?);
}

test "use template" {
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
    const children = try z.childNodes(allocator, parse_root);
    defer allocator.free(children);

    for (children) |child| {
        z.appendChild(template_content_node, child);
    }
}
