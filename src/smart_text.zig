//! Advanced text processing - the key improvements over basic cleaning
//! Focus: LazyHTML-level smart whitespace handling and context-aware escaping

const std = @import("std");
const z = @import("zhtml.zig");

/// Calculate leading whitespace size in text content
/// This is the core LazyHTML improvement for whitespace handling
pub fn leadingWhitespaceSize(data: []const u8) usize {
    var size: usize = 0;

    for (data) |ch| {
        switch (ch) {
            ' ', '\t', '\n', '\r' => size += 1,
            else => return size,
        }
    }

    return size;
}

/// Check if a text node should not be escaped (inside script, style, etc.)
/// This provides LazyHTML's context-aware escaping
pub fn isNoEscapeTextNode(node: *z.DomNode) bool {
    const parent = z.parentNode(node) orelse return false;

    if (z.nodeToElement(parent)) |parent_element| {
        const tag_name = z.tagName(parent_element);

        // Elements where text content should not be escaped
        const no_escape_tags = [_][]const u8{ "SCRIPT", "STYLE", "XMP", "IFRAME", "NOEMBED", "NOFRAMES", "PLAINTEXT" };

        for (no_escape_tags) |tag| {
            if (std.mem.eql(u8, tag_name, tag)) {
                return true;
            }
        }
    }

    return false;
}

/// Smart text escaping that preserves meaningful whitespace
/// This is the key improvement over basic HTML escaping
pub fn escapeHtmlSmart(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    const whitespace_size = leadingWhitespaceSize(content);

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    // Preserve leading whitespace as-is (LazyHTML does this)
    if (whitespace_size > 0) {
        try result.appendSlice(content[0..whitespace_size]);
    }

    // Escape the rest
    for (content[whitespace_size..]) |ch| {
        switch (ch) {
            '<' => try result.appendSlice("&lt;"),
            '>' => try result.appendSlice("&gt;"),
            '&' => try result.appendSlice("&amp;"),
            '"' => try result.appendSlice("&quot;"),
            '\'' => try result.appendSlice("&#39;"),
            else => try result.append(ch),
        }
    }

    return result.toOwnedSlice();
}

/// Context-aware text processing for serialization
/// This combines whitespace detection + context-aware escaping
pub fn processTextContentSmart(allocator: std.mem.Allocator, node: *z.DomNode, skip_whitespace_only: bool) !?[]u8 {
    const text_content = try z.getTextContent(allocator, node);
    defer allocator.free(text_content);

    if (skip_whitespace_only) {
        const whitespace_size = leadingWhitespaceSize(text_content);
        if (whitespace_size == text_content.len) {
            // Skip whitespace-only text nodes
            return null;
        }
    }

    if (isNoEscapeTextNode(node)) {
        // No escaping for script/style content (LazyHTML behavior)
        return try allocator.dupe(u8, text_content);
    } else {
        // Smart escaping with whitespace preservation
        return try escapeHtmlSmart(allocator, text_content);
    }
}

const testing = std.testing;

test "leading whitespace detection" {
    try testing.expectEqual(@as(usize, 0), leadingWhitespaceSize("hello"));
    try testing.expectEqual(@as(usize, 2), leadingWhitespaceSize("  hello"));
    try testing.expectEqual(@as(usize, 3), leadingWhitespaceSize("\t\n hello"));
    try testing.expectEqual(@as(usize, 5), leadingWhitespaceSize("     "));
}

test "context-aware escaping detection" {
    const html = "<div><script>alert('test');</script><p>normal text</p></div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const div = z.firstChild(z.elementToNode(body)).?;
    const script = z.firstChild(div).?;
    const script_text = z.firstChild(script);

    // Script text should not be escaped (if it exists)
    if (script_text) |text| {
        try testing.expect(isNoEscapeTextNode(text));
    }

    const p = z.nextSibling(script).?;
    const p_text = z.firstChild(p);

    // Regular text should be escaped (if it exists)
    if (p_text) |text| {
        try testing.expect(!isNoEscapeTextNode(text));
    }
}

test "smart HTML escaping with whitespace preservation" {
    const allocator = testing.allocator;

    // Test basic escaping
    const basic = try escapeHtmlSmart(allocator, "Hello <world>");
    defer allocator.free(basic);
    try testing.expectEqualStrings("Hello &lt;world&gt;", basic);

    // Test whitespace preservation (the key LazyHTML improvement)
    const with_whitespace = try escapeHtmlSmart(allocator, "  \t  <script>alert('xss')</script>");
    defer allocator.free(with_whitespace);
    try testing.expectEqualStrings("  \t  &lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;", with_whitespace);

    // Leading whitespace should be preserved, content escaped
    try testing.expect(std.mem.startsWith(u8, with_whitespace, "  \t  "));
}

test "context-aware text processing integration" {
    const allocator = testing.allocator;

    const html = "<div><script>alert('hello');</script><p>  <em>Hello</em> & world!</p></div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const div = z.firstChild(z.elementToNode(body)).?;
    const script = z.firstChild(div).?;
    const script_text = z.firstChild(script);

    if (script_text) |text| {
        // Script content should not be escaped
        const script_result = try processTextContentSmart(allocator, text, false);
        if (script_result) |result| {
            defer allocator.free(result);
            // Should contain unescaped content
            try testing.expect(std.mem.indexOf(u8, result, "alert('hello');") != null);
        }
    }

    const p = z.nextSibling(script).?;
    const p_text = z.firstChild(p);

    if (p_text) |text| {
        // Regular text should be escaped with whitespace preservation
        const p_result = try processTextContentSmart(allocator, text, false);
        if (p_result) |result| {
            defer allocator.free(result);
            // Should start with preserved whitespace
            try testing.expect(std.mem.startsWith(u8, result, "  "));
        }
    }
}
