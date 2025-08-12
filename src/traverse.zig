//! Experimental helper module to traverse DOM

const std = @import("std");
const z = @import("zhtml.zig");

const print = std.debug.print;
const testing = std.testing;

/// Callback function type for node traversal
///
/// Return `f`alse to stop traversal early
pub const NodeCallback = *const fn (node: *z.DomNode) bool;

/// Callback function type for element traversal
///
/// Return false to stop traversal early
pub const ElementCallback = *const fn (element: *z.DomElement) bool;

/// [traversal] Traverse child __nodes__ (including text, comments) calling callback for each node.
///
/// `break` early if callback returns false
pub fn forEachChildNode(parent_node: *z.DomNode, callback: NodeCallback) void {
    var child = z.firstChild(parent_node);
    while (child != null) {
        const current = child.?;
        child = z.nextSibling(current);

        if (!callback(current)) {
            break;
        }
    }
}

/// [traversal] Traverse child __elements__ calling callback for each element.
///
/// Returns false  if callback returns `false`, else `true`.
pub fn forEachChildElement(parent_element: *z.DomElement, callback: ElementCallback) bool {
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

/// [traversal] Traverse child __nodes__ and collect results into an ArrayList
///
/// Argument function determines what to collect.
///
/// Caller must ensure the returned slice is freed.
pub fn collectChildNodes(allocator: std.mem.Allocator, parent_node: *z.DomNode, comptime T: type, collectFn: *const fn (node: *z.DomNode) ?T) ![]T {
    var results = std.ArrayList(T).init(allocator);

    var child = z.firstChild(parent_node);
    while (child != null) {
        if (collectFn(child.?)) |item| {
            try results.append(item);
        }
        child = z.nextSibling(child.?);
    }

    return results.toOwnedSlice();
}

/// [traversal] Traverse child __elements__ and collect results into an ArrayList
///
/// Argument function determines what to collect
///
/// Caller must ensure the returned slice is freed.
pub fn collectChildElements(allocator: std.mem.Allocator, parent_element: *z.DomElement, comptime T: type, collectFn: *const fn (element: *z.DomElement) ?T) ![]T {
    var results = std.ArrayList(T).init(allocator);
    defer results.deinit();

    var child_element = z.firstElementChild(parent_element);
    while (child_element) |child| {
        if (collectFn(child)) |item| {
            try results.append(item);
        }
        child_element = z.nextElementSibling(child);
    }

    return results.toOwnedSlice();
}

// returns true if element is a `P`
fn areAllPs(element: *z.DomElement) bool {
    return z.matchesTagName(element, "P");
}

// collect `P` elements
fn matchCollector(element: *z.DomElement) ?*z.DomElement {
    if (z.matchesTagName(element, "P")) {
        return element;
    }
    return null;
}

test "DOM traversal utilities" {
    const allocator = std.testing.allocator;

    // Parse some HTML
    const html = "<div><p>Hello</p><span>World</span><p>Again</p></div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.getBodyElement(doc);
    const div = z.firstElementChild(body).?;

    const allPs = z.forEachChildElement(div, areAllPs);
    try testing.expect(!allPs);

    const p_elements = try z.collectChildElements(
        allocator,
        div,
        *z.DomElement,
        matchCollector,
    );
    defer allocator.free(p_elements);

    try testing.expect(p_elements.len == 2);
}
