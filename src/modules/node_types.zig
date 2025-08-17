const std = @import("std");
const z = @import("../zhtml.zig");

const testing = std.testing;
const print = std.debug.print;

pub const NodeType = enum(u16) {
    element = 1,
    text = 3,
    comment = 8,
    document = 9,
    fragment = 11,
    unknown = 0,

    tag_template = 0x31,
    tag_style = 0x2d,
    tag_script = 0x29,
};

pub const LXB_DOM_NODE_TYPE_ELEMENT: u32 = 1;
pub const LXB_DOM_NODE_TYPE_TEXT: u32 = 3;
pub const LXB_DOM_NODE_TYPE_COMMENT: u32 = 8;

pub const LXB_TAG_TEMPLATE: u32 = 0x31; // From lexbor source
pub const LXB_TAG_STYLE: u32 = 0x2d;
pub const LXB_TAG_SCRIPT: u32 = 0x29;

/// [node_types] Get node type for enum comparison (Inlined)
///
/// Values are: `.text`, `.element`, `.comment`, `.document`, `.unknown`.
pub inline fn nodeType(node: *z.DomNode) NodeType {
    const node_name = z.nodeName_zc(node);

    // Fast string comparison - most common cases first
    if (std.mem.eql(u8, node_name, "#text")) {
        return .text;
    } else if (std.mem.eql(u8, node_name, "#comment")) {
        return .comment;
    } else if (std.mem.eql(u8, node_name, "#document")) {
        return .document;
    } else if (std.mem.eql(u8, node_name, "#fragment")) {
        return .fragment;
    } else if (node_name.len > 0 and node_name[0] != '#') {
        // Regular HTML tag names (div, p, span, strong, em...)
        return .element;
    } else {
        return .unknown;
    }
}

/// [node_types] human-readable type name (Inlined )
///
/// Returns the actual node name for special nodes, "#element" for regular HTML tags.
pub inline fn nodeTypeName(node: *z.DomNode) []const u8 {
    const node_name = z.nodeName_zc(node);

    // Direct string comparison for maximum performance - return actual names for special nodes
    if (std.mem.eql(u8, node_name, "#text")) {
        return "#text";
    } else if (std.mem.eql(u8, node_name, "#comment")) {
        return "#comment";
    } else if (std.mem.eql(u8, node_name, "#document")) {
        return "#document";
    } else if (std.mem.eql(u8, node_name, "#fragment")) {
        return "#fragment";
    } else if (node_name.len > 0 and node_name[0] != '#') {
        // Regular HTML tag names (div, p, span, strong, em...)
        return "#element";
    } else {
        return "#unknown";
    }
}

/// [node_types] Check if node is of a specific type (Inline)
pub inline fn isTypeElement(node: *z.DomNode) bool {
    return nodeType(node) == .element;
}

/// [node_types] Check if node is a text node (Inline)
pub inline fn isTypeText(node: *z.DomNode) bool {
    return nodeType(node) == .text;
}

/// [node_types] Check if node is a comment node (Inline)
pub inline fn isTypeComment(node: *z.DomNode) bool {
    return nodeType(node) == .comment;
}

/// [node_types] Check if node is a document node (Inline)
pub inline fn isTypeDocument(node: *z.DomNode) bool {
    return nodeType(node) == .document;
}

/// [node_types] Check if node is a fragment node (Inline)
pub inline fn isTypeFragment(node: *z.DomNode) bool {
    return nodeType(node) == .fragment;
}

test "node type detection using getNodeName" {
    const frag =
        \\<!-- This is a comment -->
        \\<div>
        \\  Some text content
        \\  <span>nested element</span>
        \\  More text
        \\  <!-- comment --x
        \\  <em>  </em>
        \\</div>
    ;

    const doc = try z.parseFromString(frag);
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);
    const fragment = try z.createDocumentFragment(doc);
    z.appendFragment(body_node, fragment);

    var child = z.firstChild(body_node);
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
        if (std.mem.eql(u8, node_name, "#text")) {
            try testing.expect(@intFromEnum(node_type) == 3);
            try testing.expect(node_type == .text);
            try testing.expectEqualStrings(
                "#text",
                node_type_name,
            );
            try testing.expect(isTypeText(child.?));
        }

        if (std.mem.eql(u8, node_name, "#comment")) {
            try testing.expect(@intFromEnum(node_type) == 8);
            try testing.expect(node_type == .comment);
            try testing.expectEqualStrings(
                "#comment",
                node_type_name,
            );
            try testing.expect(isTypeFragment(child.?));
        }

        if (std.mem.eql(u8, node_name, "#fragment")) {
            try testing.expect(@intFromEnum(node_type) == 11);
            try testing.expect(node_type == .fragment);
            try testing.expectEqualStrings(
                "#fragment",
                node_type_name,
            );
            try testing.expect(isTypeFragment(child.?));
        }

        child = z.firstChild(child.?);
    }
}
