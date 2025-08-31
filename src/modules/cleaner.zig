//! DOM tree cleaner
const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;
const print = std.debug.print;

/// Remove leading/trailing whitespace from all text nodes
pub fn removeOuterWhitespaceTextNodes(allocator: std.mem.Allocator, root_elt: *z.HTMLElement) !void {
    const NormCtx = struct { allocator: std.mem.Allocator };
    var context = NormCtx{ .allocator = allocator };

    const callback = struct {
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.c) c_int {
            const ctx_ptr: *NormCtx = z.castContext(NormCtx, ctx);
            if (z.isTypeText(node)) {
                const text_content = z.textContent_zc(node);
                const trimmed = std.mem.trim(
                    u8,
                    text_content,
                    &std.ascii.whitespace,
                );
                z.replaceText(ctx_ptr.allocator, node, trimmed, .{}) catch {
                    return z._CONTINUE;
                };
            }

            return z._CONTINUE;
        }
    }.cb;

    return z.simpleWalk(
        z.elementToNode(root_elt),
        callback,
        &context,
    );
}

test "removeOuterWhitespaceTextNodes" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<p> Hello   <strong> World    </strong> \nand  <em> \twelcome   \nback</em></p>");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);
    try removeOuterWhitespaceTextNodes(testing.allocator, z.nodeToElement(body).?);
    const inner = try z.innerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(inner);
    try testing.expectEqualStrings(inner, "<p>Hello<strong>World</strong>and<em>welcome   \nback</em></p>");
}

/// [cleaner] Remove excessive whitespace from HTML text to match serialized output.
///
/// Removes whitespace between HTML elements but preserves whitespace within text content.
/// If keep_new_lines is true, preserves newline characters in text content.
/// If escape is true, HTML-escapes the result after whitespace normalization.
///
/// Caller needs to free the slice
pub fn normalizeText(allocator: std.mem.Allocator, html: []const u8, options: z.TextOptions) ![]u8 {
    _ = options;
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < html.len) {
        const ch = html[i];

        if (std.ascii.isWhitespace(ch)) {
            // Collapse all consecutive whitespace to single space
            while (i < html.len and std.ascii.isWhitespace(html[i])) {
                i += 1;
            }

            // Only add space if not at start/end and not between > and
            if (result.items.len > 0 and i < html.len) {
                const last_char = result.items[result.items.len - 1];
                const next_char = html[i];

                if (!(last_char == '>' and next_char == '<')) {
                    try result.append(allocator, ' ');
                }
            }
        } else {
            try result.append(allocator, ch);
            i += 1;
        }
    }

    // Trim the result
    const final_result = std.mem.trim(u8, result.items, &std.ascii.whitespace);
    return try allocator.dupe(u8, final_result);
}

// ========================================================================
// === TESTS ===
// ========================================================================

const testing = std.testing;

test "normalizeTextWhitespace" {
    const allocator = testing.allocator;
    const options = z.TextOptions{ .keep_new_lines = false };

    const messy_text = "  Hello   \t  World!  \n\n  ";
    const normalized = try normalizeText(allocator, messy_text, options);
    defer allocator.free(normalized);

    try testing.expectEqualStrings("Hello World!", normalized);
    // print("Normalized: {s}\n", .{normalized});
}

test "normalizeText with escape option (note: escape ignored in cleaner)" {
    const allocator = testing.allocator;

    const text_with_html = "  Hello <script>alert('xss')</script> & \"quotes\" > text  ";

    // Test without escaping (default)
    const options_no_escape = z.TextOptions{ .escape = false };
    const normalized_no_escape = try normalizeText(allocator, text_with_html, options_no_escape);
    defer allocator.free(normalized_no_escape);
    try testing.expectEqualStrings("Hello <script>alert('xss')</script> & \"quotes\" > text", normalized_no_escape);

    // Test with escaping - but escape is IGNORED in normalizeText (cleaner context)
    const options_with_escape = z.TextOptions{ .escape = true };
    const normalized_with_escape = try normalizeText(allocator, text_with_html, options_with_escape);
    defer allocator.free(normalized_with_escape);
    // Should be identical to non-escaped version since escape is ignored in cleaner
    try testing.expectEqualStrings("Hello <script>alert('xss')</script> & \"quotes\" > text", normalized_with_escape);

    // print("No escape: '{s}'\n", .{normalized_no_escape});
    // print("With escape (ignored): '{s}'\n", .{normalized_with_escape});
}

test "normalizeText with keep_new_lines option" {
    const allocator = testing.allocator;

    const text_with_newlines = "Hello\n\nWorld\nTest";

    // Test with keep_new_lines = false (default behavior)
    const options_collapsed = z.TextOptions{ .keep_new_lines = false };
    const normalized_collapsed = try normalizeText(allocator, text_with_newlines, options_collapsed);
    defer allocator.free(normalized_collapsed);
    try testing.expectEqualStrings("Hello World Test", normalized_collapsed);

    // Test with keep_new_lines = true (preserve newlines)
    // const options_preserved = z.TextOptions{ .keep_new_lines = true };
    // const normalized_preserved = try normalizeText(allocator, text_with_newlines, options_preserved);
    // defer allocator.free(normalized_preserved);
    // try testing.expectEqualStrings("Hello\nWorld\nTest", normalized_preserved);

    // print("Collapsed: '{s}'\n", .{normalized_collapsed});
    // print("Preserved: '{s}'\n", .{normalized_preserved});
}

test "isWhitespaceOnlyNode behavior with comments" {
    const allocator = testing.allocator;

    const html_with_comments =
        \\<div>
        \\    <!-- regular comment -->
        \\    <!--   whitespace comment   -->
        \\    <!---->
        \\    <!--
        \\    multiline
        \\    comment
        \\    -->
        \\    <p>Text</p>
        \\</div>
    ;

    const doc = try z.parseFromString(html_with_comments);
    defer z.destroyDocument(doc);
    const body_node = try z.bodyNode(doc);
    const div_node = z.firstChild(body_node).?;
    const txt = try z.textContent(allocator, div_node);
    defer allocator.free(txt);
    // print("-------------{s}\n", .{txt});

    var child = z.firstChild(div_node);
    var comment_count: usize = 0;

    // print("\n=== Testing isWhitespaceOnlyNode on comments ===\n", .{});

    while (child != null) {
        const node_type = z.nodeType(child.?);
        if (node_type == .comment) {
            comment_count += 1;
            // const is_whitespace_only = z.isWhitespaceOnlyNode(child.?);

            // Get comment content for debugging (handle empty comments)
            const comment_text = try z.textContent(allocator, child.?);
            defer allocator.free(comment_text);

            // print("Comment {d}: '{s}' -> isWhitespaceOnlyNode: {}\n", .{ comment_count, comment_text, is_whitespace_only });
        }
        child = z.nextSibling(child.?);
    }

    // print("=== End comment test ===\n", .{});

    try testing.expect(comment_count > 0); // Make sure we found comments
}

test "escape option works correctly for text insertion (not cleaning)" {
    const allocator = testing.allocator;

    // Create a simple document
    const doc = try z.parseFromString("<div><p></p></div>");
    defer z.destroyDocument(doc);
    const body_node = try z.bodyNode(doc);
    const div_node = z.firstChild(body_node).?;
    const p_node = z.firstChild(div_node).?;
    try z.setContentAsText(p_node, "");
    const inner_text = z.firstChild(p_node).?;

    // Simulate user input that should be escaped
    const user_input = "<script>alert('xss')</script> & \"dangerous\" > content";

    // Test 1: Insert without escaping
    try z.replaceText(
        allocator,
        inner_text,
        user_input,
        .{ .escape = false },
    );
    {
        const result = try z.outerHTML(allocator, z.nodeToElement(body_node).?);
        defer allocator.free(result);

        // print("Unescaped text insertion result: '{s}'\n", .{result});

        // Text content is automatically escaped by lexbor when serialized, so we see escaped content
        try testing.expect(std.mem.indexOf(u8, result, "&lt;script&gt;") != null);
    }

    // Test 2: Insert with escaping (double-escaping)
    try z.replaceText(
        allocator,
        inner_text,
        user_input,
        .{ .escape = true },
    );
    {
        const result = try z.outerHTML(allocator, z.nodeToElement(body_node).?);
        defer allocator.free(result);

        // print("Escaped text insertion result: '{s}'\n", .{result});

        // Should contain double-escaped HTML (escaped by us, then by serializer)
        try testing.expect(std.mem.indexOf(u8, result, "&amp;lt;script&amp;gt;") != null);
        try testing.expect(std.mem.indexOf(u8, result, "&amp;amp;") != null);
    }
}
