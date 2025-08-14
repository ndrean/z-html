const std = @import("std");
const z = @import("zhtml.zig");

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

/// [node_types] Get node type for enum comparison
///
/// Values are: `.text`, `.element`, `.comment`, `.document`, `.unknown`.
pub fn nodeType(node: *z.DomNode) NodeType {
    const node_name = z.nodeName(node);

    // Switch on common node name patterns
    if (std.mem.eql(u8, node_name, "#text")) {
        return .text;
    } else if (std.mem.eql(u8, node_name, "#comment")) {
        return .comment;
    } else if (std.mem.eql(u8, node_name, "#document")) {
        return .document;
    } else if (node_name.len > 0 and node_name[0] != '#') {
        // Regular HTML tag names (div, p, span, strong, em...)
        return .element;
    } else {
        return .unknown;
    }
}

/// [node_types] human-readable type name
pub fn nodeTypeName(node: *z.DomNode) []const u8 {
    return switch (nodeType(node)) {
        .element => "#element",
        .text => "#text",
        .comment => "#comment",
        .document => "#document",
        else => "#unknown",
    };
}

/// [node_types] Check if node is of a specific type
pub fn isTypeElement(node: *z.DomNode) bool {
    return nodeType(node) == .element;
}

/// [node_types] Check if node is a text node
pub fn isTypeText(node: *z.DomNode) bool {
    print("{any}\t", .{nodeType(node)});
    return nodeType(node) == .text;
}

/// [node_types] Check if node is a comment node
pub fn isTypeComment(node: *z.DomNode) bool {
    return nodeType(node) == .comment;
}

/// [node_types] Check if node is a document node
pub fn isTypeDocument(node: *z.DomNode) bool {
    return nodeType(node) == .document;
}

test "node type detection using getNodeName" {
    const fragment =
        \\<!-- This is a comment -->
        \\<div>
        \\  Some text content
        \\  <span>nested element</span>
        \\  More text
        \\  <!-- comment --x
        \\  <em>  </em>
        \\</div>
    ;

    const doc = try z.parseFromString(fragment);
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);

    var child = z.firstChild(body_node);
    while (child != null) {
        const node_name = z.nodeName(child.?);
        const node_type = z.nodeType(child.?);
        const node_type_name = z.nodeTypeName(child.?);

        if (std.mem.eql(u8, node_name, "DIV")) {
            try testing.expect(@intFromEnum(node_type) == 1);
            try testing.expect(node_type == .element);
            try testing.expectEqualStrings(
                "#element",
                node_type_name,
            );
        }
        if (std.mem.eql(u8, node_name, "#text")) {
            try testing.expect(@intFromEnum(node_type) == 3);
            try testing.expect(node_type == .text);
            try testing.expectEqualStrings(
                "#text",
                node_type_name,
            );
        }

        if (std.mem.eql(u8, node_name, "#comment")) {
            try testing.expect(@intFromEnum(node_type) == 8);
            try testing.expect(node_type == .comment);
            try testing.expectEqualStrings(
                "#comment",
                node_type_name,
            );
        }

        child = z.firstChild(child.?);
    }
}
