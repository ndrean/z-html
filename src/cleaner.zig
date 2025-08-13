//! DOM tree cleaner
const std = @import("std");
const z = @import("zhtml.zig");

pub const DomCleanOptions = struct {
    remove_comments: bool = false,
    remove_empty_elements: bool = false, // Remove elements with no content (not just text nodes)
};

/// [core] Clean DOM tree according to HTML standards + optional extras
pub fn cleanDomTree(allocator: std.mem.Allocator, root: *z.DomNode, options: DomCleanOptions) !void {
    try cleanNodeRecursive(allocator, root, options);
}

fn cleanNodeRecursive(allocator: std.mem.Allocator, node: *z.DomNode, options: DomCleanOptions) !void {
    const node_type = z.getType(node);
    var node_was_removed = false;

    switch (node_type) {
        .text => {
            if (!shouldPreserveWhitespace(node)) {
                node_was_removed = try maybeCleanOrRemoveTextNode(allocator, node);
            }
        },

        .element => {
            node_was_removed = try cleanElementNode(
                allocator,
                node,
                options,
            );
        },
        .comment => {
            if (options.remove_comments) {
                z.removeNode(node);
                node_was_removed = true;
            }
        },
        else => {},
    }

    // Recursively clean children (if node still exists)
    if (!node_was_removed) {
        var child = z.firstChild(node);
        while (child != null) {
            const next_child = z.nextSibling(child.?);
            try cleanNodeRecursive(allocator, child.?, options);
            child = next_child;
        }
    }
}

fn cleanElementNode(allocator: std.mem.Allocator, node: *z.DomNode, options: DomCleanOptions) !bool {
    const element = z.nodeToElement(node) orelse return false;

    const size = try cleanElementAttributes(allocator, element);

    // Optional: remove empty elements with no attributes
    if (options.remove_empty_elements) {
        if (z.isWhitespaceOnlyNode(node) and size == 0) {
            z.destroyNode(node);
            return true;
        }
    }
    return false;
}

fn cleanElementAttributes(allocator: std.mem.Allocator, element: *z.DomElement) !usize {
    if (!z.hasAttributes(element)) {
        return 0;
    }

    const attr_list = try z.getAttributes(allocator, element);
    defer {
        for (attr_list) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        allocator.free(attr_list);
    }
    const size = attr_list.len;

    if (size == 0) return 0;

    // Remove all existing attributes
    for (attr_list) |attr| {
        try z.removeAttribute(element, attr.name);
    }

    // Re-add with normalized whitespace
    for (attr_list) |attr| {
        const clean_name = std.mem.trim(
            u8,
            attr.name,
            &std.ascii.whitespace,
        );
        const clean_value = std.mem.trim(
            u8,
            attr.value,
            &std.ascii.whitespace,
        );

        // Skip empty attribute names (malformed HTML)
        if (clean_name.len > 0) {
            try z.setAttribute(
                element,
                &.{
                    .{
                        .name = clean_name,
                        .value = clean_value,
                    },
                },
            );
        }
    }
    return attr_list.len;
}

fn maybeCleanOrRemoveTextNode(allocator: std.mem.Allocator, node: *z.DomNode) !bool {
    const text = try z.getNodeTextContentsOpts(
        allocator,
        node,
        .{},
    );
    defer allocator.free(text);
    if (z.isWhitepaceOnlyText(text)) {
        z.removeNode(node);
        return true;
    }

    // Trim and collapse whitespace (mandatory normalization)
    const cleaned = try normalizeWhitespace(allocator, text);
    defer allocator.free(cleaned);

    // Only update if content actually changed
    if (!std.mem.eql(u8, text, cleaned)) {
        // try setTextContent(node, cleaned);
        try z.setOrReplaceText(allocator, node, cleaned);
    }
    return false;
}

fn shouldPreserveWhitespace(node: *z.DomNode) bool {
    // // debug -->
    // const allocator = testing.allocator;
    // const text = getNodeAllTextContent(allocator, node) catch return false;
    // defer allocator.free(text);
    // print("maybe preserving {s}, {s}\n", .{ getNodeName(node), text });
    // //  <-- debug

    const parent = z.parentNode(node) orelse return false;
    if (z.nodeToElement(parent)) |parent_element| {
        const tag_name = z.getElementName(parent_element);

        // leave these elements unchanged
        return std.mem.eql(u8, tag_name, "PRE") or
            std.mem.eql(u8, tag_name, "CODE") or
            std.mem.eql(u8, tag_name, "SCRIPT") or
            std.mem.eql(u8, tag_name, "STYLE") or
            std.mem.eql(u8, tag_name, "TEXTAREA");
    }
    return false;
}

/// [cleaner] Remove excessive whitespace from HTML text to match serialized output
///
/// Removes whitespace between HTML elements but preserves whitespace within text content
/// Caller needs to free the slice
pub fn normalizeWhitespace(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    // Trim leading and trailing whitespace
    const trimmed = std.mem.trim(
        u8,
        text,
        &std.ascii.whitespace,
    );

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < trimmed.len) {
        const ch = trimmed[i];

        if (std.ascii.isWhitespace(ch)) {
            // Look ahead to see if we're between HTML elements (> ... <)
            const whitespace_start = i;
            while (i < trimmed.len and std.ascii.isWhitespace(trimmed[i])) {
                i += 1;
            }

            // Check if whitespace is between HTML elements
            var prev_char: u8 = 0;
            if (whitespace_start > 0) prev_char = trimmed[whitespace_start - 1];
            var next_char: u8 = 0;
            if (i < trimmed.len) next_char = trimmed[i];

            // If whitespace is between > and < (between HTML elements), skip it
            // Otherwise, collapse to single space (within text content)
            if (prev_char == '>' and next_char == '<') {
                // Skip whitespace between elements completely
                continue;
            } else {
                // Preserve single space for text content
                try result.append(' ');
            }
        } else {
            try result.append(ch);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

// ORIGINAL VERSION - for text node content only:
// [cleaner] Remove excessive whitespace from text content (original version)
//
// This was the original function designed for normalizing whitespace within text nodes,
// not for processing full HTML markup.
//
// Caller needs to free the slice
// pub fn normalizeTextWhitespace_original(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
//     // Trim leading and trailing whitespace
//     const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
//
//     // Collapse internal whitespace sequences to single spaces
//     var result = std.ArrayList(u8).init(allocator);
//     defer result.deinit();
//
//     var prev_was_whitespace = false;
//     for (trimmed) |ch| {
//         if (std.ascii.isWhitespace(ch)) {
//             if (!prev_was_whitespace) {
//                 try result.append(' '); // Normalize all whitespace to spaces
//                 prev_was_whitespace = true;
//             }
//         } else {
//             try result.append(ch);
//             prev_was_whitespace = false;
//         }
//     }
//
//     return result.toOwnedSlice();
// }

/// [cleaner] Parse HTML and serialize it back compactly (lexbor-based approach)
///
/// This approach combines the best of both worlds:
/// 1. Parse the HTML string into a DOM tree (lexbor handles correctness)
/// 2. Handle both full documents and fragments
/// 3. Serialize it back using lexbor's serialization
/// 4. Apply whitespace normalization to get compact output
/// 5. Much more robust than character-by-character processing alone
///
/// Caller needs to free the slice
pub fn normalizeHtmlWithLexbor(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    const zhtml = @import("zhtml.zig");

    // Parse the HTML into a DOM tree
    const doc = try zhtml.parseFromString(html);
    defer zhtml.destroyDocument(doc);

    // Check if this looks like a full document (has doctype or html tag)
    const is_full_document = std.mem.indexOf(u8, html, "<!DOCTYPE") != null or
        std.mem.indexOf(u8, html, "<html") != null or
        std.mem.indexOf(u8, html, "<HTML") != null;

    const serialized = if (is_full_document) blk: {
        // For full documents, serialize the entire document
        const root = zhtml.documentRoot(doc) orelse return allocator.dupe(u8, "");
        break :blk try zhtml.serializeTree(allocator, root);
    } else blk: {
        // For fragments, get content from body
        const body_element = try zhtml.getBodyElement(doc);
        const body_node = zhtml.elementToNode(body_element);

        const first_child = zhtml.firstChild(body_node);
        if (first_child == null) {
            return allocator.dupe(u8, "");
        }

        break :blk try zhtml.serializeTree(allocator, first_child.?);
    };

    defer allocator.free(serialized);

    // Apply our existing HTML-aware whitespace normalization to make it compact
    return try normalizeWhitespace(allocator, serialized);
}

// ========================================================================
// === TESTS ===
// ========================================================================

const testing = std.testing;

test "normalizeTextWhitespace" {
    const allocator = testing.allocator;

    const messy_text = "  Hello   \t  World!  \n\n  ";
    const normalized = try normalizeWhitespace(allocator, messy_text);
    defer allocator.free(normalized);

    try testing.expectEqualStrings("Hello World!", normalized);
    // print("Normalized: {s}\n", .{normalized});
}

test "cleanElementAttributes" {
    const allocator = testing.allocator;

    const doc = try z.parseFromString("<div><p>No attrs</p><span id='test' class='demo'>With attrs</span></div>");
    defer z.destroyDocument(doc);

    const body = try z.getBodyElement(doc);
    const body_node = z.elementToNode(body);
    const div_node = z.firstChild(body_node).?;

    var child = z.firstChild(div_node);
    var elements_processed: usize = 0;
    var elements_with_attrs: usize = 0;

    while (child != null) {
        if (z.nodeToElement(child.?)) |element| {
            elements_processed += 1;

            // Test the fast path optimization
            if (z.hasAttributes(element)) {
                elements_with_attrs += 1;
            }

            // This should now use the optimized path
            _ = try cleanElementAttributes(allocator, element);
        }
        child = z.nextSibling(child.?);
    }

    try testing.expect(elements_processed == 2); // <p> and <span>
    try testing.expect(elements_with_attrs == 1); // only <span> has attributes
}

test "complete DOM cleaning with proper node removal" {
    const allocator = testing.allocator;

    const messy_html =
        \\<div   class  =  " container test "   id  = "main"  >
        \\    
        \\    <p>   Hello     World   </p>
        \\    
        \\    <!-- Remove this comment -->
        \\    <span data-id = "123"></span>
        \\    <pre>    preserve    this    </pre>
        \\    
        \\    <p>  </p>
        \\
        \\   <br/> <!-- This should be removed -->
        \\
        \\    <img src = 'http://google.com' alt = 'my-image' data-value=''/> 
        \\
        \\     <script> const div  = document.querySelector('div'); </script>
        \\</div>
    ;

    const doc = try z.parseFromString(messy_html);
    defer z.destroyDocument(doc);

    const body = try z.getBodyElement(doc);
    const body_node = z.elementToNode(body);

    // print("\n=== Complete DOM Cleaning Test ===\n", .{});

    const before = try z.serializeTree(allocator, body_node);
    defer allocator.free(before);

    try cleanDomTree(
        allocator,
        body_node,
        .{
            .remove_comments = true,
            .remove_empty_elements = true,
        },
    );

    const after = try z.serializeTree(allocator, body_node);
    defer allocator.free(after);
    // print("\n\nAfter cleaning:=============\n{s}\n\n", .{after});

    // Verify results
    try testing.expect(std.mem.indexOf(u8, after, "<!--") == null); // Comments removed
    try testing.expect(std.mem.indexOf(u8, after, "Hello World") != null); // Text normalized
    try testing.expect(std.mem.indexOf(u8, after, "<span></span>") == null); // Empty elements removed
    try testing.expect(std.mem.indexOf(u8, after, "class=\"container test\"") != null); // Attributes cleaned
    try testing.expect(std.mem.indexOf(u8, after, "    preserve    ") != null); // <pre> preserved

    // printDocumentStructure(doc);

    // print("✅ Complete DOM cleaning works perfectly!\n", .{});
}
