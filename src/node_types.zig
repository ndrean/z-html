const std = @import("std");
const testing = std.testing;
const print = std.debug.print;

const zhtml = @import("zhtml.zig");

pub const NodeType = enum(u32) {
    element = 1,
    text = 3,
    comment = 8,
    document = 9,
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

/// Get node type by parsing the node name
pub fn getNodeType(node: *zhtml.DomNode) NodeType {
    const node_name = zhtml.getNodeName(node);

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

/// human-readable type name
pub fn getNodeTypeName(node: *zhtml.DomNode) []const u8 {
    return switch (getNodeType(node)) {
        .element => "element",
        .text => "text",
        .comment => "comment",
        .document => "document",
        else => "unknown",
    };
}

pub fn isElementNode(node: *zhtml.DomNode) bool {
    return getNodeType(node) == .element;
}

pub fn isTextNode(node: *zhtml.DomNode) bool {
    return getNodeType(node) == .text;
}

pub fn isCommentNode(node: *zhtml.DomNode) bool {
    return getNodeType(node) == .comment;
}

pub fn isDocumentNode(node: *zhtml.DomNode) bool {
    return getNodeType(node) == .document;
}

pub fn walkTreeWithTypes(node: *zhtml.DomNode, depth: u32) void {
    var child = zhtml.getNodeFirstChildNode(node);
    while (child != null) {
        const name = zhtml.getNodeName(child.?);
        const node_type = zhtml.getNodeType(child.?);
        const type_name = zhtml.getNodeTypeName(child.?);

        // Create indentation
        var i: u32 = 0;
        while (i < @min(depth, 10)) : (i += 1) {
            print("  ", .{});
        }

        print("{s} ({s})\n", .{ name, type_name });

        // Only recurse into elements
        if (node_type == .element) {
            walkTreeWithTypes(child.?, depth + 1);
        }

        child = zhtml.getNodeFirstChildNode(child.?);
    }
}

test "node type detection using getNodeName" {
    const fragment =
        \\<!-- This is a comment -->
        \\<div>
        \\  Some text content
        \\  <span>nested element</span>
        \\  More text
        \\  <em>  </em>
        \\</div>
    ;

    const doc = try zhtml.parseFragmentAsDocument(fragment);
    defer zhtml.destroyDocument(doc);
    zhtml.printDocumentStructure(doc);

    std.debug.print("\n--- NODE TYPE ANALYSIS ---\n", .{});

    const body = zhtml.getBodyElement(doc).?;
    const body_node = zhtml.elementToNode(body);

    var child = zhtml.getNodeFirstChildNode(body_node);
    while (child != null) {
        const node_name = zhtml.getNodeName(child.?);
        const node_type = zhtml.getNodeType(child.?);
        const type_name = zhtml.getNodeTypeName(child.?);

        print("Node: '{s}' -> Type: {d} ({s})\n", .{ node_name, @intFromEnum(node_type), type_name });

        // // Test helper functions
        print("  isElement: {}, isText: {}, isComment: {}\n", .{ zhtml.isElementNode(child.?), zhtml.isTextNode(child.?), zhtml.isCommentNode(child.?) });

        child = zhtml.getNodeFirstChildNode(child.?);
    }

    print("\n-- TREE WITH TYPES --\n", .{});
    walkTreeWithTypes(body_node, 0);
}
