//! String based HTML string comment or whitespace only text nodes cleaner
const std = @import("std");
const z = @import("../root.zig");
const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;

/// String-based HTML normalization options
pub const StringNormalizeOptions = struct {
    remove_comments: bool = false,
    remove_whitespace_text_nodes: bool = true,
};

/// [cleaner] String-based HTML normalization - removes whitespace-only text nodes
///
/// Skips content between preserve tags: <pre>, <textarea>, <script>, <style>, <code>
/// Caller needs to free the returned slice
pub fn normalizeHtmlString(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    return normalizeHtmlStringWithOptions(allocator, html, .{});
}

/// [cleaner] String-based HTML normalization with options
///
/// Provides control over comment removal and whitespace text node removal.
/// Preserves content within special tags: <pre>, <textarea>, <script>, <style>, <code>
/// Caller needs to free the returned slice
pub fn normalizeHtmlStringWithOptions(allocator: std.mem.Allocator, html: []const u8, options: StringNormalizeOptions) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    // Pre-allocate based on input size (normalized HTML is typically smaller)
    try result.ensureTotalCapacity(allocator, html.len);

    var pos: usize = 0;

    while (pos < html.len) {
        // Check if we're at the start of a tag or comment
        if (html[pos] == '<') {
            const tag_start = pos;

            // Check if this is a comment
            if (pos + 4 < html.len and std.mem.startsWith(u8, html[pos..], "<!--")) {
                // Find the end of the comment
                const comment_end = std.mem.indexOf(u8, html[pos + 4 ..], "-->") orelse {
                    // Malformed comment, copy rest as-is
                    try result.appendSlice(allocator, html[pos..]);
                    break;
                };

                const full_comment = html[pos .. pos + 4 + comment_end + 3];

                if (!options.remove_comments) {
                    // Keep the comment
                    try result.appendSlice(allocator, full_comment);
                }
                // Skip comment either way
                pos = pos + 4 + comment_end + 3;
                continue;
            }

            // Find the end of the opening tag
            const tag_end = std.mem.indexOfScalarPos(u8, html, pos, '>') orelse {
                // Malformed HTML, copy rest as-is
                try result.appendSlice(allocator, html[pos..]);
                break;
            };

            const tag_content = html[tag_start .. tag_end + 1];

            // Check if this is a whitespace-preserving tag
            const preserve_tags = [_][]const u8{ "<pre", "<textarea", "<script", "<style", "<code" };
            var is_preserve_tag = false;
            var preserve_tag_name: []const u8 = "";

            for (preserve_tags) |preserve_tag| {
                if (std.mem.startsWith(u8, tag_content, preserve_tag) and
                    (tag_content.len == preserve_tag.len or
                        tag_content[preserve_tag.len] == ' ' or
                        tag_content[preserve_tag.len] == '>'))
                {
                    is_preserve_tag = true;
                    preserve_tag_name = preserve_tag[1..]; // Remove '<' for closing tag
                    break;
                }
            }

            if (is_preserve_tag) {
                // Copy the opening tag
                try result.appendSlice(allocator, tag_content);
                pos = tag_end + 1;

                // Find the matching closing tag
                const closing_tag = try std.fmt.allocPrint(allocator, "</{s}>", .{preserve_tag_name});
                defer allocator.free(closing_tag);

                const closing_pos = std.mem.indexOf(u8, html[pos..], closing_tag);
                if (closing_pos) |close_offset| {
                    const end_pos = pos + close_offset + closing_tag.len;
                    // Copy everything inside preserve tags as-is (no whitespace removal)
                    try result.appendSlice(allocator, html[pos..end_pos]);
                    pos = end_pos;
                } else {
                    // No closing tag found, copy rest as-is
                    try result.appendSlice(allocator, html[pos..]);
                    break;
                }
            } else {
                // Regular tag, copy as-is
                try result.appendSlice(allocator, tag_content);
                pos = tag_end + 1;
            }
        } else {
            // We're in text content - check if it's whitespace-only
            const text_start = pos;
            var text_end = pos;

            // Find the end of this text segment (until next '<' or end of string)
            while (text_end < html.len and html[text_end] != '<') {
                text_end += 1;
            }

            const text_segment = html[text_start..text_end];

            if (options.remove_whitespace_text_nodes and z.isWhitespaceOnly(text_segment)) {
                // Skip whitespace-only text segments (this is the normalization)
            } else {
                // Keep non-whitespace text as-is (or all text if option is disabled)
                try result.appendSlice(allocator, text_segment);
            }

            pos = text_end;
        }
    }

    return result.toOwnedSlice(allocator);
}

test "string based normalize text behaviour" {
    const allocator = testing.allocator;
    // remove whitespace-only text nodes and preserves inside
    {
        const html =
            \\<div>
            \\  <p>
            \\      Some
            \\    <i>  text   </i>
            \\  </p>
            \\</div>
        ;

        const doc = try z.createDocFromString(html);
        defer z.destroyDocument(doc);
        const body = z.bodyElement(doc).?;

        const outer = try z.outerHTML(allocator, body);
        defer allocator.free(outer);
        const normed = try z.normalizeHtmlString(allocator, outer);
        defer allocator.free(normed);

        const expected =
            \\<body><div><p>
            \\      Some
            \\    <i>  text   </i></p></div></body>
        ;

        try testing.expectEqualStrings(expected, normed);
    }

    // remove whitespace-only text nodes not multiline
    {
        const html1 = "<div>\n  \t  <p>Hello world</p>   \n\t  </div>";
        const normalized1 = try z.normalizeHtmlString(allocator, html1);
        defer allocator.free(normalized1);

        const expected1 = "<div><p>Hello world</p></div>";
        try testing.expectEqualStrings(expected1, normalized1);
    }
    // preserve PRE tag
    {
        const html2 =
            \\<div>
            \\  <pre>  preserve  this  </pre>
            \\  <p>Normal text</p>
            \\</div>
        ;
        const normalized2 = try z.normalizeHtmlString(allocator, html2);
        defer allocator.free(normalized2);

        const expected2 = "<div><pre>  preserve  this  </pre><p>Normal text</p></div>";
        try testing.expectEqualStrings(expected2, normalized2);
    }
    // preserve SCRIPT tags
    {
        const html3 = "<div>\n  <script>\n  console.log('test');\n  </script>\n  <span>Text</span>  \n</div>";
        const normalized3 = try z.normalizeHtmlString(allocator, html3);
        defer allocator.free(normalized3);

        const expected3 = "<div><script>\n  console.log('test');\n  </script><span>Text</span></div>";
        try testing.expectEqualStrings(expected3, normalized3);
    }

    const html_with_comments =
        \\<div>
        \\  <!-- Comment 1 -->
        \\
        \\  <p> Text </p>
        \\
        \\  <!-- Comment 2 -->
        \\
        \\</div>
    ;
    // option keep comment
    {

        // Keep comments
        const normalized_keep = try z.normalizeHtmlStringWithOptions(
            allocator,
            html_with_comments,
            .{
                .remove_comments = false,
                .remove_whitespace_text_nodes = true,
            },
        );
        defer allocator.free(normalized_keep);

        const expected_keep = "<div><!-- Comment 1 --><p> Text </p><!-- Comment 2 --></div>";
        try testing.expectEqualStrings(expected_keep, normalized_keep);
    }
    // option remove comment
    {
        const normalized_remove = try z.normalizeHtmlStringWithOptions(
            allocator,
            html_with_comments,
            .{
                .remove_comments = true,
                .remove_whitespace_text_nodes = true,
            },
        );
        defer allocator.free(normalized_remove);

        const expected_remove = "<div><p> Text </p></div>";
        try testing.expectEqualStrings(expected_remove, normalized_remove);
    }
}

/// [cleaner] Remove excessive whitespace from HTML text to match serialized output.
///
/// Collapses consecutive whitespace to single spaces and removes whitespace between tags.
/// Preserves meaningful spaces within text content.
/// Trims leading and trailing whitespace from the result.
///
/// Caller needs to free the slice
pub fn normalizeText(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
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

test "normalizeText" {
    const allocator = testing.allocator;

    const messy_text = "  Hello   \t  World!  \n\n  ";
    const normalized = try normalizeText(allocator, messy_text);
    defer allocator.free(normalized);

    try testing.expectEqualStrings("Hello World!", normalized);
}
