//! DOM tree cleaner
const std = @import("std");
const z = @import("../root.zig");
const Err = z.Err;
const print = std.debug.print;

/// [cleaner] Remove excessive whitespace from HTML text to match serialized output.
///
/// Removes whitespace between HTML elements but preserves whitespace within text content.
/// If keep_new_lines is true, preserves newline characters in text content.
/// If escape is true, HTML-escapes the result after whitespace normalization.
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

// ========================================================================
// === TESTS ===
// ========================================================================

const testing = std.testing;

test "normalizeText and nomalize" {
    const allocator = testing.allocator;

    {
        const messy_text = "  Hello   \t  World!  \n\n  ";
        const normalized = try normalizeText(allocator, messy_text);
        defer allocator.free(normalized);

        try testing.expectEqualStrings("Hello World!", normalized);
    }
    {
        const html =
            \\<div> \n
            \\  <p>
            \\      Some \t
            \\    <i>  text  \n\n  </i>
            \\  </p> \t
            \\</div>
        ;

        const doc = try z.createDocFromString(html);
        defer z.destroyDocument(doc);
        const body = z.bodyElement(doc).?;

        try z.normalizeDOM(allocator, body);
        const normalized = try z.innerHTML(allocator, body);
        defer allocator.free(normalized);
        // print("{s}\n", .{normalized});

        // const expected = "<div><p> Some \t <i>  text  \n\n. </i></p></div>";

        // try testing.expectEqualStrings(expected, normalized);
    }
}
