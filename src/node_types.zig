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

/// [node_types] Get node type by parsing the node name
pub fn getType(node: *z.DomNode) NodeType {
    const node_name = z.getNodeName(node);

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
pub fn getTypeName(node: *z.DomNode) []const u8 {
    return switch (getType(node)) {
        .element => "element",
        .text => "text",
        .comment => "comment",
        .document => "document",
        .fragment => "fragment",
        else => "unknown",
    };
}

/// [node_types] Check if node is of a specific type
pub fn isTypeElement(node: *z.DomNode) bool {
    return getType(node) == .element;
}

/// [node_types] Check if node is a text node
pub fn isTypeText(node: *z.DomNode) bool {
    print("{any}\t", .{getType(node)});
    return getType(node) == .text;
}

/// [node_types] Check if node is a comment node
pub fn isTypeComment(node: *z.DomNode) bool {
    return getType(node) == .comment;
}

/// [node_types] Check if node is a document node
pub fn isTypeDocument(node: *z.DomNode) bool {
    return getType(node) == .document;
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
    // z.printDocumentStructure(doc);

    // print("\n--- NODE TYPE ANALYSIS ---\n", .{});

    const body_node = try z.getBodyNode(doc);

    var child = z.firstChild(body_node);
    while (child != null) {
        const node_name = z.getNodeName(child.?);
        const node_type = z.getType(child.?);
        const type_name = z.getTypeName(child.?);

        if (std.mem.eql(u8, node_name, "DIV")) {
            try testing.expect(@intFromEnum(node_type) == 1);
            try testing.expectEqualStrings(type_name, "element");
        }
        if (std.mem.eql(u8, node_name, "#text")) {
            try testing.expect(@intFromEnum(node_type) == 3);
            try testing.expectEqualStrings(type_name, "text");
        }

        if (std.mem.eql(u8, node_name, "#comment")) {
            try testing.expect(@intFromEnum(node_type) == 8);
            try testing.expectEqualStrings(type_name, "comment");
        }

        child = z.firstChild(child.?);
    }
}
