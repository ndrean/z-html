const std = @import("std");
const z = @import("../root.zig");

const testing = std.testing;
const print = std.debug.print;

/// Node types enum for easy comparison
pub const NodeType = enum(u8) {
    element = z.LXB_DOM_NODE_TYPE_ELEMENT,
    text = z.LXB_DOM_NODE_TYPE_TEXT,
    comment = z.LXB_DOM_NODE_TYPE_COMMENT,
    document = z.LXB_DOM_NODE_TYPE_DOCUMENT,
    fragment = z.LXB_DOM_NODE_TYPE_FRAGMENT,
    unknown = z.LXB_DOM_NODE_TYPE_UNKNOWN,
};

/// [node_types] Get node type for enum comparison (Inlined)
///
/// Values are: `.text`, `.comment`, `.document`, `.fragment`, `.element`, `.unknown`.
pub inline fn nodeType(node: *z.DomNode) NodeType {
    const node_name = z.nodeName_zc(node);

    // Fast string comparison - most common cases first
    if (std.mem.eql(u8, node_name, "#text")) {
        return .text;
    } else if (std.mem.eql(u8, node_name, "#comment")) {
        return .comment;
    } else if (std.mem.eql(u8, node_name, "#document")) {
        return .document;
    } else if (std.mem.eql(u8, node_name, "#document-fragment")) {
        return .fragment;
    } else if (node_name.len > 0 and node_name[0] != '#') {
        // Regular node names (DIV, P, SPAN, STRONG, EM...)
        return .element;
    } else {
        return .unknown;
    }
}

/// [node_types] human-readable type name (Inlined )
///
/// Returns the actual node name (`#text`, `#comment`, `#document-fragment`) for special nodes, `#element` for regular HTML tags.
pub inline fn nodeTypeName(node: *z.DomNode) []const u8 {
    // const node_name = z.nodeName_zc(node);

    // Direct string comparison for maximum performance - return actual names for special nodes
    if (z.nodeType(node) == .text) {
        return "#text";
    } else if (z.nodeType(node) == .comment) {
        return "#comment";
    } else if (z.nodeType(node) == .document) {
        return "#document";
    } else if (z.nodeType(node) == .fragment) {
        return "#document-fragment";
    } else if (z.nodeType(node) == .element) {
        // Regular HTML tag names (DIV, P, SPAN, STRONG, EM...)
        return "#element";
    } else {
        return "#unknown";
    }
}

/// [node_types] Check if node is an HTMLElement
pub inline fn isTypeElement(node: *z.DomNode) bool {
    return nodeType(node) == .element;
}

/// [node_types] Check if node is a TEXT node
pub inline fn isTypeText(node: *z.DomNode) bool {
    return nodeType(node) == .text;
}

/// [node_types] Check if node is a COMMENT node
pub inline fn isTypeComment(node: *z.DomNode) bool {
    return nodeType(node) == .comment;
}

/// [node_types] Check if node is a DOCUMENT node
pub inline fn isTypeDocument(node: *z.DomNode) bool {
    return nodeType(node) == .document;
}

/// [node_types] Check if node is a FRAGMENT node
pub inline fn isTypeFragment(node: *z.DomNode) bool {
    return nodeType(node) == .fragment;
}

test "type / name checking" {
    const frag =
        \\<div>
        \\<!-- This is a comment -->
        \\  Some text content
        \\  <span>nested element</span>
        \\  More text
        \\  <!-- comment -->
        \\  <em> Emphasis </em>
        \\</div>
    ;

    const doc = try z.createDocFromString(frag);
    defer z.destroyDocument(doc);

    const body_node = z.bodyNode(doc).?;
    const fragment = try z.createDocumentFragment(doc);
    const p_elt = try z.createElement(doc, "p");
    const frag_node = z.fragmentToNode(fragment);
    z.appendChild(frag_node, z.elementToNode(p_elt));

    const div = z.firstChild(body_node);
    z.appendChild(div.?, frag_node);

    var element_count: usize = 0;
    var text_count: usize = 0;
    var comment_count: usize = 0;
    var fragment_count: usize = 0;

    var child = z.firstChild(div.?);
    while (child != null) {
        const node_name = z.nodeName_zc(child.?);
        const node_type = z.nodeType(child.?);
        const node_type_name = z.nodeTypeName(child.?);

        if (std.mem.eql(u8, node_name, "DIV")) {
            try testing.expect(@intFromEnum(node_type) == 1);
            try testing.expect(node_type == .element);
            try testing.expectEqualStrings(
                "#element",
                node_type_name,
            );
            try testing.expect(isTypeElement(child.?));
        }

        if (node_type == .element) {
            element_count += 1;
            try testing.expect(isTypeElement(child.?));
            try testing.expect(@intFromEnum(node_type) == 1);
            try testing.expectEqualStrings(
                "#element",
                node_type_name,
            );
        }

        if (std.mem.eql(u8, node_name, "#text")) {
            text_count += 1;
            try testing.expect(@intFromEnum(node_type) == 3);
            try testing.expect(node_type == .text);
            try testing.expectEqualStrings(
                "#text",
                node_type_name,
            );
            try testing.expect(isTypeText(child.?));
        }

        if (std.mem.eql(u8, node_name, "#comment")) {
            comment_count += 1;
            try testing.expect(@intFromEnum(node_type) == 8);
            try testing.expect(node_type == .comment);
            try testing.expectEqualStrings(
                "#comment",
                node_type_name,
            );
            try testing.expect(isTypeComment(child.?));
        }

        if (std.mem.eql(u8, node_name, "#document-fragment")) {
            fragment_count += 1;
            try testing.expect(@intFromEnum(node_type) == 11);
            try testing.expect(node_type == .fragment);
            try testing.expectEqualStrings(
                "#document-fragment",
                node_type_name,
            );
            try testing.expect(isTypeFragment(child.?));
            const p = z.firstChild(child.?);
            try testing.expect(isTypeElement(p.?));
        }

        child = z.nextSibling(child.?);
    }
    try testing.expect(element_count == 2);
    try testing.expect(text_count == 5);
    try testing.expect(comment_count == 2);
    try testing.expect(fragment_count == 1);

    // documenet structure is:
    // DIV
    //     #text
    //     #comment
    //     #text
    //     SPAN
    //         #text
    //     #text
    //     #comment
    //     #text
    //     EM
    //         #text
    //     #text
    //     #document-fragment
    //         P
}
