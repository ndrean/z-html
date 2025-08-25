//! Experimental helper module to traverse DOM

const std = @import("std");
const z = @import("../zhtml.zig");

const print = std.debug.print;
const testing = std.testing;

/// [traversal] Traverse child __elements__ and collect upon the HTMLTag
///
///
/// Argument function determines what to collect, like `z.HtmlTag.p`or `z.HtmlTag.li`.
///
/// Caller must ensure the returned slice is freed.
pub fn collectChildElements(
    allocator: std.mem.Allocator,
    parent_element: *z.HTMLElement,
    comptime T: type,
    target_tag: z.HtmlTag,
    collectFn: *const fn (element: T, tag: z.HtmlTag) ?T,
) ![]T {
    // the reason of using `comptime T: type` is that you can't use HTMLElement instead of the generic T in `std.ArrayList`
    var results = std.ArrayList(T).init(allocator);
    defer results.deinit();

    var child_element = z.firstElementChild(parent_element);
    while (child_element) |child| {
        if (collectFn(child, target_tag)) |item| {
            try results.append(item);
        }
        child_element = z.nextElementSibling(child);
    }

    return results.toOwnedSlice();
}

/// [traversal] Traverse child __nodes__ and collect upon the node type
///
/// Can collect `.text`, `.comment`, `.element`.
///
/// Generic version that works with any node type and matching function.
///
/// Caller must ensure the returned slice is freed.
pub fn collectChildItems(
    allocator: std.mem.Allocator,
    parent_node: *z.DomNode,
    comptime T: type,
    target_node_type: z.NodeType,
    collectFn: *const fn (element: T, node_type: z.NodeType) ?T,
) ![]T {
    // the reason of using `comptime T: type` is that you can't use HTMLElement instead of the generic T in `std.ArrayList`
    var results = std.ArrayList(T).init(allocator);
    defer results.deinit();

    var child = z.firstChild(parent_node);
    while (child) |node| {
        if (collectFn(node, target_node_type)) |item| {
            try results.append(item);
        }
        child = z.nextSibling(node);
    }

    return results.toOwnedSlice();
}

/// [traverse] Callback to collect elements with a given HTML tag
pub fn elementMatchCollector(element: *z.HTMLElement, tag: z.HtmlTag) ?*z.HTMLElement {
    if (z.tagFromQualifiedName(z.qualifiedName_zc(element))) |element_tag| {
        if (element_tag == tag) return element;
    }
    return null;
}

pub fn notOfTypeNodes(node: *z.DomNode, node_type: z.NodeType) ?*z.DomNode {
    if (z.nodeType(node) != node_type) {
        return node;
    }
    return null;
}

/// [traverse] Callback to collect all nodes of a type
pub fn nodeMatchCollector(node: *z.DomNode, node_type: z.NodeType) ?*z.DomNode {
    if (z.nodeType(node) == node_type) {
        return node;
    }
    return null;
}

test "DOM traversal utilities" {
    const allocator = std.testing.allocator;

    // Parse some HTML with various node types
    const html = "<div><!-- comment --> test <p>Hello</p><span>World</span><p>Again</p></div> hi";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const div = z.firstElementChild(body).?;
    const div_node = z.elementToNode(div);

    const p_elements = try collectChildElements(
        allocator,
        div,
        *z.HTMLElement,
        .p,
        elementMatchCollector,
    );
    defer allocator.free(p_elements);

    try testing.expect(p_elements.len == 2);

    const span_elements = try collectChildElements(
        allocator,
        div,
        *z.HTMLElement,
        .span,
        elementMatchCollector,
    );
    defer allocator.free(span_elements);

    try testing.expect(span_elements.len == 1);

    // Collect all element nodes (comment, text, p, span, p = 3 elements)
    const element_nodes = try collectChildItems(
        allocator,
        div_node,
        *z.DomNode,
        .element,
        nodeMatchCollector,
    );
    defer allocator.free(element_nodes);
    try testing.expect(element_nodes.len == 3); // p, span, p

    // Collect all text nodes
    const text_nodes = try collectChildItems(
        allocator,
        div_node,
        *z.DomNode,
        .text, // ignored by textNodeCollector
        nodeMatchCollector,
    );
    defer allocator.free(text_nodes);
    // try testing.expect(text_nodes.len >= 1); // Should have text nodes

    // Collect all comment nodes
    const comment_nodes = try collectChildItems(
        allocator,
        div_node,
        *z.DomNode,
        .comment, // ignored by commentNodeCollector
        nodeMatchCollector,
    );
    defer allocator.free(comment_nodes);
    try testing.expect(comment_nodes.len == 1); // Should have one comment

    const notTextNodes = try collectChildItems(
        allocator,
        z.elementToNode(body),
        *z.DomNode,
        .element,
        notOfTypeNodes,
    );
    defer allocator.free(notTextNodes);
    try testing.expect(notTextNodes.len == 1); // The last text "hi"
}

// ---------------------------------
// Trial fns

// returns true if element is a `P`
fn areAllPs(element: *z.HTMLElement) bool {
    return z.tagFromQualifiedName(z.qualifiedName_zc(element)).? == .p;
}

fn areAllOfType(element: *z.HTMLElement, tag: z.HtmlTag) bool {
    return z.tagFromQualifiedName(z.qualifiedName_zc(element)).? == tag;
}

fn forEachChildNode(
    parent_node: *z.DomNode,
    callback: *const fn (node: *z.DomNode) bool,
) void {
    var child = z.firstChild(parent_node);
    while (child != null) {
        const current = child.?;
        child = z.nextSibling(current);

        if (!callback(current)) {
            break;
        }
    }
}

fn forEachChildElement(
    parent_element: *z.HTMLElement,
    callback: *const fn (elt: *z.HTMLElement) bool,
) bool {
    var child_element = z.firstElementChild(parent_element);
    while (child_element) |child| {
        const current = child;
        child_element = z.nextElementSibling(current);

        if (!callback(current)) {
            return false;
        }
    }
    return true;
}

fn forEachChild(
    comptime T: type, // the type of parent, either DomNode or HTMLElement
    parent: anytype,
    callback: *const fn (child: @TypeOf(parent)) bool,
) bool {
    _ = T;
    if (z.nodeType(z.elementToNode(parent)) == .element) {
        return forEachChildElement(parent, callback);
    } else {
        return false;
    }
}
