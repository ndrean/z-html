const std = @import("std");
const z = @import("src/zhtml.zig");
const dom_tree = @import("src/dom_tree.zig");
const html_tags = @import("src/html_tags.zig");

test "typed nodes with HtmlTag enum" {
    const allocator = std.testing.allocator;

    const html =
        \\<div class="container">
        \\  <p>Hello world</p>
        \\  <br>
        \\  <custom-element id="test">Custom content</custom-element>
        \\</div>
    ;

    const doc = try z.parseHtml(allocator, html);
    defer z.destroyDocument(doc);

    const body = z.bodyElement(doc).?;
    const div_element = z.firstChildElement(z.elementToNode(body)).?;

    // Test typed tree conversion
    const typed_tree = try dom_tree.domNodeToTypedTree(allocator, z.elementToNode(div_element));
    defer freeTypedHtmlNode(allocator, typed_tree);

    // Test typed JSON conversion
    const typed_json = try dom_tree.domNodeToTypedJson(allocator, z.elementToNode(div_element));
    defer freeTypedJsonNode(allocator, typed_json);

    // Verify the conversions worked
    switch (typed_tree) {
        .element => |elem| {
            // The div should be recognized as HtmlTag.div
            switch (elem.tag) {
                .tag => |html_tag| {
                    try std.testing.expect(html_tag == html_tags.HtmlTag.div);
                    std.debug.print("✓ div tag recognized as HtmlTag enum\n", .{});
                },
                .custom => {
                    return std.testing.expectEqual(@as(u32, 0), @as(u32, 1)); // Should not be custom
                },
            }

            // Should have 3 children: p, br, custom-element
            try std.testing.expect(elem.children.len == 3);

            // Check the p element
            switch (elem.children[0]) {
                .element => |p_elem| {
                    switch (p_elem.tag) {
                        .tag => |html_tag| {
                            try std.testing.expect(html_tag == html_tags.HtmlTag.p);
                            std.debug.print("✓ p tag recognized as HtmlTag enum\n", .{});
                        },
                        .custom => return std.testing.expectEqual(@as(u32, 0), @as(u32, 1)),
                    }
                },
                else => return std.testing.expectEqual(@as(u32, 0), @as(u32, 1)),
            }

            // Check the br element
            switch (elem.children[1]) {
                .element => |br_elem| {
                    switch (br_elem.tag) {
                        .tag => |html_tag| {
                            try std.testing.expect(html_tag == html_tags.HtmlTag.br);
                            try std.testing.expect(html_tag.isVoid());
                            std.debug.print("✓ br tag recognized as HtmlTag enum and is void\n", .{});
                        },
                        .custom => return std.testing.expectEqual(@as(u32, 0), @as(u32, 1)),
                    }
                },
                else => return std.testing.expectEqual(@as(u32, 0), @as(u32, 1)),
            }

            // Check the custom element
            switch (elem.children[2]) {
                .element => |custom_elem| {
                    switch (custom_elem.tag) {
                        .tag => return std.testing.expectEqual(@as(u32, 0), @as(u32, 1)), // Should be custom
                        .custom => |tag_name| {
                            try std.testing.expect(std.mem.eql(u8, tag_name, "custom-element"));
                            std.debug.print("✓ custom-element recognized as custom tag\n", .{});
                        },
                    }
                },
                else => return std.testing.expectEqual(@as(u32, 0), @as(u32, 1)),
            }
        },
        else => return std.testing.expectEqual(@as(u32, 0), @as(u32, 1)),
    }

    std.debug.print("All typed node tests passed! 🎉\n", .{});
}

// Helper functions for memory management (simplified versions)
fn freeTypedHtmlNode(allocator: std.mem.Allocator, node: dom_tree.TypedHtmlNode) void {
    switch (node) {
        .element => |elem| {
            // Free tag string if it's custom
            switch (elem.tag) {
                .custom => |tag_name| allocator.free(tag_name),
                .tag => {}, // Enum tags don't need freeing
            }

            // Free attributes
            for (elem.attributes) |attr| {
                allocator.free(attr.name);
                allocator.free(attr.value);
            }
            allocator.free(elem.attributes);

            // Free children recursively
            for (elem.children) |child| {
                freeTypedHtmlNode(allocator, child);
            }
            allocator.free(elem.children);
        },
        .text => |text| allocator.free(text),
        .comment => |comment| {
            allocator.free(comment.tag);
            allocator.free(comment.text);
        },
    }
}

fn freeTypedJsonNode(allocator: std.mem.Allocator, node: dom_tree.TypedJsonNode) void {
    switch (node) {
        .element => |*elem| {
            // Free tag string if it's custom
            switch (elem.tag) {
                .custom => |tag_name| allocator.free(tag_name),
                .tag => {}, // Enum tags don't need freeing
            }

            // Free attributes HashMap
            var iterator = elem.attributes.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            @constCast(&elem.attributes).deinit();

            // Free children recursively
            for (elem.children) |child| {
                freeTypedJsonNode(allocator, child);
            }
            allocator.free(elem.children);
        },
        .text => |text_node| allocator.free(text_node.text),
        .comment => |comment_node| allocator.free(comment_node.comment),
    }
}
