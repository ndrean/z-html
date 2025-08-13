const std = @import("std");
const z = @import("src/zhtml.zig");

// External declarations for the lexbor functions
extern "c" fn lxb_dom_node_insert_before(to: *z.DomNode, node: *z.DomNode) void;
extern "c" fn lxb_dom_node_insert_after(to: *z.DomNode, node: *z.DomNode) void;

test "experiment with lexbor insert_before and insert_after functions" {
    std.debug.print("\n=== Testing lexbor insert_before and insert_after functions ===\n", .{});

    // Create a simple HTML structure: <body><p>Hello</p><!-- comment --><p>World</p></body>
    const html = "<body><p>Hello</p><!-- comment --><p>World</p></body>";
    const doc = try z.parseFromString(html);
    defer z.deinitDoc(doc);

    const body = z.getBody(doc).?;
    std.debug.print("Original HTML: {s}\n", .{try z.innerHTML(body)});

    // Find the comment node
    var comment_node: ?*z.DomNode = null;
    var current = z.firstChild(body);
    while (current) |node| {
        if (z.nodeType(node) == z.NodeType.comment) {
            comment_node = node;
            break;
        }
        current = z.nextSibling(node);
    }

    if (comment_node == null) {
        std.debug.print("ERROR: Could not find comment node\n", .{});
        return;
    }

    std.debug.print("Found comment node\n", .{});

    // Create a text node with a space
    const space_node = z.createTextNode(doc, " ");

    // Test 1: Try insert_before
    std.debug.print("\n--- Test 1: insert_before ---\n", .{});
    lxb_dom_node_insert_before(comment_node.?, space_node);
    std.debug.print("After insert_before: {s}\n", .{try z.innerHTML(body)});

    // Remove the space node for next test
    z.removeChild(space_node);

    // Test 2: Try insert_after
    std.debug.print("\n--- Test 2: insert_after ---\n", .{});
    const space_node2 = z.createTextNode(doc, " ");
    lxb_dom_node_insert_after(comment_node.?, space_node2);
    std.debug.print("After insert_after: {s}\n", .{try z.innerHTML(body)});

    // Test 3: Remove comment and see the result
    std.debug.print("\n--- Test 3: After removing comment ---\n", .{});
    z.removeChild(comment_node.?);
    std.debug.print("After removing comment: {s}\n", .{try z.innerHTML(body)});
}
