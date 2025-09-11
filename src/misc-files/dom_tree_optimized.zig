const std = @import("std");
const z = @import("../root.zig");

/// Optimized DOM to tuple serialization using Writer interface
fn serializeNodeToWriter(w: anytype, node: *z.DomNode) !void {
    const node_type = z.nodeType(node);

    switch (node_type) {
        .element => {
            const element = z.nodeToElement(node).?;
            const tag_name = z.qualifiedName_zc(element);

            // Use writer.print for efficient formatting - like C++ append()
            try w.z.print("{{\"{s}\", [", .{tag_name});

            // Get attributes efficiently - still need temp allocator for this
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const temp_allocator = gpa.allocator();

            const attrs = z.getAttributes_bf(temp_allocator, element) catch &[_]z.Attribute{};
            defer {
                for (attrs) |attr| {
                    temp_allocator.free(attr.name);
                    temp_allocator.free(attr.value);
                }
                temp_allocator.free(attrs);
            }

            for (attrs, 0..) |attr, i| {
                if (i > 0) try w.writeAll(", ");
                try w.z.print("{{\"{s}\", \"{s}\"}}", .{ attr.name, attr.value });
            }

            try w.writeAll("], [");

            // Serialize children recursively
            var first_child = true;
            var child = z.firstChild(node);
            while (child != null) {
                if (!first_child) try w.writeAll(", ");
                try serializeNodeToWriter(w, child.?);
                first_child = false;
                child = z.nextSibling(child.?);
            }

            try w.writeAll("]}");
        },

        .text => {
            const text_content = z.textContent_zc(node);
            if (text_content.len > 0) {
                try w.writeByte('"');
                // Escape the text content efficiently
                for (text_content) |char| {
                    switch (char) {
                        '"' => try w.writeAll("\\\""),
                        '\\' => try w.writeAll("\\\\"),
                        '\n' => try w.writeAll("\\n"),
                        '\r' => try w.writeAll("\\r"),
                        '\t' => try w.writeAll("\\t"),
                        else => try w.writeByte(char),
                    }
                }
                try w.writeByte('"');
            } else {
                try w.writeAll("\"\"");
            }
        },

        .comment => {
            const comment = z.nodeToComment(node).?;
            const comment_content = z.commentContent_zc(comment);
            try w.writeAll("{\"comment\", \"");
            // Escape comment content efficiently
            for (comment_content) |char| {
                switch (char) {
                    '"' => try w.writeAll("\\\""),
                    '\\' => try w.writeAll("\\\\"),
                    '\n' => try w.writeAll("\\n"),
                    '\r' => try w.writeAll("\\r"),
                    '\t' => try w.writeAll("\\t"),
                    else => try w.writeByte(char),
                }
            }
            try w.writeAll("\"}");
        },

        else => {
            // Skip other node types (document, fragment, etc.)
        },
    }
}

pub fn domToTupleStringOptimized(allocator: std.mem.Allocator, doc: *z.HTMLDocument) ![]u8 {
    // Single buffer approach like C++ std::string
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    // Pre-allocate reasonable capacity to avoid early reallocations
    try result.ensureTotalCapacity(8192);

    const writer = result.writer();

    try writer.writeByte('[');
    const root = z.documentRoot(doc).?;
    var first = true;
    var child = z.firstChild(root);
    while (child != null) {
        if (!first) try writer.writeAll(", ");
        try serializeNodeToWriter(writer, child.?);
        first = false;
        child = z.nextSibling(child.?);
    }
    try writer.writeByte(']');

    return result.toOwnedSlice();
}
