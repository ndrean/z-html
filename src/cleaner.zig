//! DOM tree cleaner
const std = @import("std");
const z = @import("zhtml.zig");

pub const DomCleanOptions = struct {
    remove_comments: bool = false,
    // Remove elements with no content (not just text nodes)
    remove_empty_elements: bool = false,
    keep_new_lines: bool = false,
};

/// [core] Clean DOM tree according to HTML standards + optional extras
pub fn cleanDomTree(allocator: std.mem.Allocator, root: *z.DomNode, options: DomCleanOptions) !void {
    try cleanNodeRecursive(allocator, root, options);
}

fn cleanNodeRecursive(allocator: std.mem.Allocator, node: *z.DomNode, options: DomCleanOptions) !void {
    const node_type = z.getType(node);

    var node_was_removed = false;
    switch (node_type) {
        .comment => {
            if (options.remove_comments) {
                try removeCommentWithSpacing(allocator, node);
                node_was_removed = true;
            }
        },

        .text => {
            if (!shouldPreserveWhitespace(node)) {
                node_was_removed = try maybeCleanOrRemoveTextNode(
                    allocator,
                    node,
                    options,
                );
            }
        },

        .element => {
            node_was_removed = try cleanElementNode(
                allocator,
                node,
                options,
            );
        },

        else => {},
    }

    // Recursively clean children (if node still exists)
    if (!node_was_removed) {
        var child = z.firstChild(node);
        while (child != null) {
            const next_child = z.nextSibling(child.?);
            try cleanNodeRecursive(
                allocator,
                child.?,
                options,
            );
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

// List all attributes, remove them, and re-add with trimmed whitespace
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

fn maybeCleanOrRemoveTextNode(allocator: std.mem.Allocator, node: *z.DomNode, options: DomCleanOptions) !bool {
    const text = try z.getTextContentsOpts(
        allocator,
        node,
        .{},
    );
    defer allocator.free(text);

    if (z.isWhitepaceOnlyText(text) and options.remove_empty_elements) { //<-------- CHANGED ???
        z.removeNode(node);
        return true;
    }

    // Trim and collapse whitespace (mandatory normalization)
    const cleaned = try normalizeWhitespace(
        allocator,
        text,
        options.keep_new_lines,
    );
    defer allocator.free(cleaned);

    // Only update if content actually changed
    if (!std.mem.eql(u8, text, cleaned)) {
        // try setTextContent(node, cleaned);
        try z.setOrReplaceText(allocator, node, cleaned);
    }
    return false;
}

fn shouldPreserveWhitespace(node: *z.DomNode) bool {
    const parent = z.parentNode(node) orelse return false;
    if (z.nodeToElement(parent)) |parent_element| {
        const tag_name = z.getElementName(parent_element);

        // TODO: change this to enum comparison <----------------------------
        // leave these elements unchanged
        return std.mem.eql(u8, tag_name, "PRE") or
            std.mem.eql(u8, tag_name, "CODE") or
            std.mem.eql(u8, tag_name, "SCRIPT") or
            std.mem.eql(u8, tag_name, "STYLE") or
            std.mem.eql(u8, tag_name, "TEXTAREA");
    }
    return false;
}

/// [cleaner] Alternative approach: Replace comment with a space text node
///
/// Simpler approach: just remove the comment and add space to previous text node if needed
fn removeCommentWithSpacing(allocator: std.mem.Allocator, comment_node: *z.DomNode) !void {
    if (z.previousSibling(comment_node)) |prev| {
        if (z.isTypeText(prev)) {
            // Handle the case where the text node might be empty
            const txt = z.getTextContentsOpts(allocator, prev, .{}) catch |err| switch (err) {
                z.Err.EmptyTextContent => {
                    // Empty text node - nothing to add space to
                    z.removeNode(comment_node);
                    z.destroyNode(comment_node);
                    return;
                },
                else => return err,
            };
            defer allocator.free(txt);

            if (txt.len > 0) {
                const result = try std.fmt.allocPrint(
                    allocator,
                    "{s} ",
                    .{txt},
                );

                // Set the text content (this function handles memory management)
                try z.setOrReplaceText(
                    allocator,
                    prev,
                    result,
                );

                // Free our temporary string since setOrReplaceText copies it
                allocator.free(result);
            }
        }
    }

    // Remove the comment
    z.removeNode(comment_node);
    z.destroyNode(comment_node);
}

/// New approach using insertBefore function
/// Strategy: Always add space between text nodes when removing comments
// fn removeCommentWithSpacing3(_: std.mem.Allocator, comment_node: *z.DomNode) !void {
//     // Helper function to find previous sibling (since it's not exported)
//     const getPreviousSibling = struct {
//         fn call(node: *z.DomNode) ?*z.DomNode {
//             const parent = z.parentNode(node) orelse return null;
//             var child = z.firstChild(parent);
//             var prev: ?*z.DomNode = null;

//             while (child != null) {
//                 if (child.? == node) return prev;
//                 prev = child;
//                 child = z.nextSibling(child.?);
//             }
//             return null;
//         }
//     }.call;

//     const prev_sibling = getPreviousSibling(comment_node);
//     const next_sibling = z.nextSibling(comment_node);

//     // Check if we have text nodes on both sides that will get concatenated
//     const prev_is_text = prev_sibling != null and z.isTypeText(prev_sibling.?);
//     const next_is_text = next_sibling != null and z.isTypeText(next_sibling.?);

//     // Only add space if removing the comment will cause text concatenation
//     if (prev_is_text and next_is_text) {
//         // Create a space text node
//         const doc = z.ownerDocument(comment_node);
//         const space_text_node = try z.createTextNode(doc, " ");

//         // Insert space after the previous text node (this puts it right between the text nodes)
//         z.insertAfter(prev_sibling.?, space_text_node);
//     }

//     // Remove the comment
//     z.removeNode(comment_node);
//     z.destroyNode(comment_node);
// }

/// [cleaner] Remove excessive whitespace from HTML text to match serialized output.
///
/// Removes whitespace between HTML elements but preserves whitespace within text content.
/// If keep_new_lines is true, preserves newline characters in text content.
///
/// Caller needs to free the slice
pub fn normalizeWhitespace(allocator: std.mem.Allocator, text: []const u8, keep_new_lines: bool) ![]u8 {
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
                // Handle newlines based on keep_new_lines option
                if (keep_new_lines and std.mem.indexOfScalar(u8, trimmed[whitespace_start..i], '\n') != null) {
                    // Preserve newline if keep_new_lines is true and there was a newline in the whitespace
                    try result.append('\n');
                } else {
                    // Preserve single space for text content
                    try result.append(' ');
                }
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
    // Default to not keeping new lines for backward compatibility
    return try normalizeWhitespace(allocator, serialized, false);
}

// ========================================================================
// === TESTS ===
// ========================================================================

const testing = std.testing;
const print = std.debug.print;

test "normalizeTextWhitespace" {
    const allocator = testing.allocator;

    const messy_text = "  Hello   \t  World!  \n\n  ";
    const normalized = try normalizeWhitespace(allocator, messy_text, false);
    defer allocator.free(normalized);

    try testing.expectEqualStrings("Hello World!", normalized);
    // print("Normalized: {s}\n", .{normalized});
}

test "normalizeWhitespace with keep_new_lines option" {
    const allocator = testing.allocator;

    const text_with_newlines = "Hello\n\nWorld\nTest";

    // Test with keep_new_lines = false (default behavior)
    const normalized_collapsed = try normalizeWhitespace(allocator, text_with_newlines, false);
    defer allocator.free(normalized_collapsed);
    try testing.expectEqualStrings("Hello World Test", normalized_collapsed);

    // Test with keep_new_lines = true (preserve newlines)
    const normalized_preserved = try normalizeWhitespace(allocator, text_with_newlines, true);
    defer allocator.free(normalized_preserved);
    try testing.expectEqualStrings("Hello\nWorld\nTest", normalized_preserved);

    // print("Collapsed: '{s}'\n", .{normalized_collapsed});
    // print("Preserved: '{s}'\n", .{normalized_preserved});
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

test "comprehensive cleaning options coverage" {
    const allocator = testing.allocator;

    // Test case with truly empty elements (no attributes, no content)
    const html =
        \\<div>
        \\    <p>Content</p>
        \\    <span></span>
        \\    <!-- This is a comment -->
        \\    <div>   </div>
        \\    <em></em>
        \\    <article id="1"></article>
        \\    line1
        \\
        \\    line2
        \\
        \\    <strong>Text</strong>
        \\</div>
    ;

    var opts = DomCleanOptions{};
    try testing.expect(!opts.remove_comments);
    try testing.expect(!opts.remove_empty_elements);
    try testing.expect(!opts.keep_new_lines);

    // Test 1: No options === default options
    {
        const doc = try z.parseFromString(html);
        defer z.destroyDocument(doc);
        const body_node = try z.getBodyNode(doc);

        try cleanDomTree(allocator, body_node, .{});
        const result = try z.serializeTree(allocator, body_node);
        defer allocator.free(result);

        // Should preserve comments and empty elements
        // Comments preserved
        try testing.expect(
            std.mem.indexOf(u8, result, "<!--") != null,
        );

        // Empty elements preserved
        try testing.expect(
            std.mem.indexOf(u8, result, "<span></span>") != null,
        );

        // Empty elements preserved
        try testing.expect(
            std.mem.indexOf(u8, result, "<em></em>") != null,
        );

        // Empty elements preserved
        try testing.expect(std.mem.indexOf(u8, result, "<article") != null);

        // textnodes are concatenated are separated by a whitespace by default
        try testing.expect(std.mem.indexOf(u8, result, "line1 line2") != null);
    }

    // Test 2: Remove comments only
    {
        opts.remove_comments = true;
        try testing.expect(opts.remove_comments);
        try testing.expect(!opts.remove_empty_elements);
        try testing.expect(!opts.keep_new_lines);

        const doc = try z.parseFromString(html);
        defer z.destroyDocument(doc);
        const body_node = try z.getBodyNode(doc);

        try cleanDomTree(allocator, body_node, opts);

        const result = try z.serializeTree(allocator, body_node);
        defer allocator.free(result);

        // Debug: print the actual result to see what we're getting
        print("Test 2 result: '{s}'\n", .{result});

        // Should remove comments but preserve empty elements
        try testing.expect(std.mem.indexOf(u8, result, "<!--") == null);

        try testing.expect(std.mem.indexOf(u8, result, "<span></span>") != null); // Empty elements preserved

        // textnodes are concatenated are separated by a whitespace by default
        try testing.expect(
            std.mem.indexOf(u8, result, "line1 line2") != null,
        );
    }

    // Test 3: Remove empty elements only
    {
        opts.remove_comments = false;
        opts.remove_empty_elements = true;
        try testing.expect(!opts.remove_comments);
        try testing.expect(opts.remove_empty_elements);
        try testing.expect(!opts.keep_new_lines);

        const doc = try z.parseFromString(html);
        defer z.destroyDocument(doc);
        const body_node = try z.getBodyNode(doc);

        const before_empty = try z.serializeTree(allocator, body_node);
        defer allocator.free(before_empty);

        try cleanDomTree(allocator, body_node, opts);

        const result = try z.serializeTree(allocator, body_node);
        defer allocator.free(result);
        // print("After empty element removal: {s}\n", .{result});
        print("T3: {s}\n", .{result});

        // Should remove empty elements but preserve comments
        try testing.expect(
            std.mem.indexOf(u8, result, "<!--") != null,
        ); // Comments preserved

        try testing.expect(
            std.mem.indexOf(u8, result, "<span></span>") == null,
        ); // Empty elements removed

        // Empty elements removed
        try testing.expect(
            std.mem.indexOf(u8, result, "<em></em>") == null,
        );

        // Content preserved
        try testing.expect(std.mem.indexOf(u8, result, "<p>Content</p>") != null);

        // Content preserved
        try testing.expect(
            std.mem.indexOf(u8, result, "<strong>Text</strong>") != null,
        );

        // article has empty innerText but has an attribute so preserved
        try testing.expect(
            std.mem.indexOf(u8, result, "<article id=\"1\"></article>") != null,
        );

        // textnodes are concatenated are separated by a whitespace by default
        try testing.expect(
            std.mem.indexOf(u8, result, "line1 line2") != null,
        );
    }

    // Test 4: All cleaning options
    {
        opts = .{
            .remove_comments = true,
            .remove_empty_elements = true,
            .keep_new_lines = true,
        };
        try testing.expect(opts.remove_comments);
        try testing.expect(opts.remove_empty_elements);
        try testing.expect(opts.keep_new_lines);

        const doc = try z.parseFromString(html);
        defer z.destroyDocument(doc);
        const body_node = try z.getBodyNode(doc);

        try cleanDomTree(allocator, body_node, opts);

        const result = try z.serializeTree(allocator, body_node);
        defer allocator.free(result);
        print("T4: {s}\n", .{result});

        // Comments removed
        try testing.expect(
            std.mem.indexOf(u8, result, "<!--") == null,
        );

        //  Empty elements removed
        try testing.expect(
            std.mem.indexOf(u8, result, "<span></span>") == null,
        );

        // Empty elements removed
        try testing.expect(
            std.mem.indexOf(u8, result, "<em></em>") == null,
        );

        // Content preserved
        try testing.expect(
            std.mem.indexOf(u8, result, "<p>Content</p>") != null,
        );

        // Content preserved
        try testing.expect(
            std.mem.indexOf(u8, result, "<strong>Text</strong>") != null,
        );

        // text ndos are NOT concatenated
        try testing.expect(
            std.mem.indexOf(u8, result, "line1 line2") == null,
        );
    }

    {
        opts = .{
            .remove_comments = true,
            .remove_empty_elements = true,
            .keep_new_lines = true,
        };
    }
}

test "keep_new_lines option comprehensive test" {
    const allocator = testing.allocator;

    const html_with_newlines =
        \\<div>
        \\    <p>Line 1
        \\Line 2
        \\
        \\<!-- comment -->
        \\Line 3<article></article>
        \\    <span>Text with
        \\newlines</span>
        \\Line 4<span id="1"></span>
        \\</div>
    ;

    // Test 1: new_lines are removed by default (keep_new_lines = false (default))
    {
        const doc = try z.parseFromString(html_with_newlines);
        defer z.destroyDocument(doc);
        const body_node = try z.getBodyNode(doc);

        const child_nodes = try z.getChildNodes(allocator, body_node);
        defer allocator.free(child_nodes);

        for (child_nodes) |child| {
            const txt = try z.getTextContent(allocator, child);
            defer allocator.free(txt);
            print("Child node: {s}, \n", .{txt});
        }

        try cleanDomTree(
            allocator,
            body_node,
            .{
                .keep_new_lines = false,
                .remove_comments = true,
            },
        );

        const result = try z.serializeTree(allocator, body_node);
        defer allocator.free(result);
        print("{s}\n", .{result});

        // Newlines should be collapsed to spaces and comment is removed with proper spacing
        try testing.expect(
            std.mem.indexOf(u8, result, "Line 1 Line 2 Line 3") != null,
        );

        try testing.expect(
            std.mem.indexOf(u8, result, "Text with newlines") != null,
        );
    }

    // Test 2: keep_new_lines = true
    {
        const doc = try z.parseFromString(html_with_newlines);
        defer z.destroyDocument(doc);
        const body = try z.getBodyElement(doc);
        const body_node = z.elementToNode(body);

        const before_newlines = try z.serializeTree(allocator, body_node);
        defer allocator.free(before_newlines);
        // print("Before newlines cleaning: {s}\n", .{before_newlines});

        try cleanDomTree(
            allocator,
            body_node,
            .{
                .keep_new_lines = true,
                .remove_comments = true,
            },
        );

        const result = try z.serializeTree(allocator, body_node);
        defer allocator.free(result);
        // print("After newlines cleaning (keep=true): {s}\n", .{result});

        // Newlines should be preserved, and comment removal should add proper spacing
        try testing.expect(
            std.mem.indexOf(u8, result, "Line 1\nLine 2 Line 3") != null,
        );

        try testing.expect(
            std.mem.indexOf(u8, result, "Text with\nnewlines") != null,
        );
    }
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
            .keep_new_lines = false, // Collapse newlines by default
        },
    );

    const after = try z.serializeTree(allocator, body_node);
    defer allocator.free(after);
    // print("\n\nAfter cleaning:=============\n{s}\n\n", .{after});

    // Verify results
    try testing.expect(
        std.mem.indexOf(u8, after, "<!--") == null,
    ); // Comments removed
    try testing.expect(
        std.mem.indexOf(u8, after, "Hello World") != null,
    ); // Text normalized
    try testing.expect(
        std.mem.indexOf(u8, after, "<span></span>") == null,
    ); // Empty elements removed
    try testing.expect(
        std.mem.indexOf(u8, after, "class=\"container test\"") != null,
    ); // Attributes cleaned
    try testing.expect(
        std.mem.indexOf(u8, after, "    preserve    ") != null,
    ); // <pre> preserved

    // printDocumentStructure(doc);

    // print("✅ Complete DOM cleaning works perfectly!\n", .{});
}

test "comment removal between text nodes concatenation issue" {
    const allocator = testing.allocator;

    // This is the problematic case: text nodes separated by comments
    const html_with_text_comment_text =
        \\<p>Hello<!-- comment -->World</p>
        \\<p>First sentence.<!-- Remove this -->Second sentence.</p>
        \\<div>Start<!-- space needed -->End</div>
    ;

    const doc = try z.parseFromString(html_with_text_comment_text);
    defer z.destroyDocument(doc);
    const body = try z.getBodyElement(doc);
    const body_node = z.elementToNode(body);

    const before = try z.serializeTree(allocator, body_node);
    defer allocator.free(before);
    print("Before comment removal: {s}\n", .{before});

    try cleanDomTree(allocator, body_node, .{ .remove_comments = true });

    const after = try z.serializeTree(allocator, body_node);
    defer allocator.free(after);
    print("After comment removal: {s}\n", .{after});

    // This demonstrates the problem:
    // "Hello<!-- comment -->World" becomes "HelloWorld" (should be "Hello World")
    // "First sentence.<!-- Remove this -->Second sentence." becomes "First sentence.Second sentence." (should add space)
    // "Start<!-- space needed -->End" becomes "StartEnd" (should be "Start End")
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
    const body_node = try z.getBodyNode(doc);
    const div_node = z.firstChild(body_node).?;
    const txt = try z.getTextContentsOpts(allocator, div_node, .{});
    defer allocator.free(txt);
    print("-------------{s}\n", .{txt});

    var child = z.firstChild(div_node);
    var comment_count: usize = 0;

    print("\n=== Testing isWhitespaceOnlyNode on comments ===\n", .{});

    while (child != null) {
        const node_type = z.getType(child.?);
        if (node_type == .comment) {
            comment_count += 1;
            const is_whitespace_only = z.isWhitespaceOnlyNode(child.?);

            // Get comment content for debugging (handle empty comments)
            const comment_text = z.getTextContentsOpts(allocator, child.?, .{}) catch |err| switch (err) {
                error.EmptyTextContent => try allocator.dupe(u8, ""),
                else => return err,
            };
            defer allocator.free(comment_text);

            print("Comment {d}: '{s}' -> isWhitespaceOnlyNode: {}\n", .{ comment_count, comment_text, is_whitespace_only });
        }
        child = z.nextSibling(child.?);
    }

    print("=== End comment test ===\n", .{});

    try testing.expect(comment_count > 0); // Make sure we found comments
}

test "comment removal with proper spacing" {
    const allocator = testing.allocator;

    // Test cases for comment removal spacing
    const test_cases = [_]struct {
        html: []const u8,
        expected: []const u8,
        description: []const u8,
    }{
        .{
            .html = "<p>Hello<!-- comment -->World</p>",
            .expected = "Hello World",
            .description = "Basic comment between words",
        },
        .{
            .html = "<p>First sentence.<!-- Remove this -->Second sentence.</p>",
            .expected = "First sentence. Second sentence.",
            .description = "Comment after punctuation",
        },
        .{
            .html = "<div>Start<!-- space needed -->End</div>",
            .expected = "Start End",
            .description = "Comment between words in div",
        },
        .{
            .html = "<p>Word1<!---->Word2</p>",
            .expected = "Word1 Word2",
            .description = "Empty comment between words",
        },
        // .{
        //     .html = "<p>Already spaced <!-- comment --> text</p>",
        //     .expected = "Already spaced text",
        //     .description = "Comment with existing spaces (should preserve existing spacing)",
        // },
        .{
            .html = "<p>Text<!-- comment --></p>",
            .expected = "Text",
            .description = "Comment at end (no spacing needed)",
        },
        .{
            .html = "<p><!-- comment -->Text</p>",
            .expected = "Text",
            .description = "Comment at start (no spacing needed)",
        },
    };

    print("\n=== Testing comment removal with spacing ===\n", .{});

    for (test_cases, 0..) |test_case, i| {
        const doc = try z.parseFromString(test_case.html);
        defer z.destroyDocument(doc);

        const body = try z.getBodyElement(doc);
        const body_node = z.elementToNode(body);

        const before = try z.serializeTree(allocator, body_node);
        defer allocator.free(before);

        try cleanDomTree(allocator, body_node, .{ .remove_comments = true });

        const after = try z.serializeTree(allocator, body_node);
        defer allocator.free(after);

        print("Test {d}: {s}\n", .{ i + 1, test_case.description });
        print("  Before: {s}\n", .{before});
        print("  After:  {s}\n", .{after});
        print("  Expected text: '{s}'\n", .{test_case.expected});

        // Check if the expected text is in the result
        const found = std.mem.indexOf(u8, after, test_case.expected) != null;
        print("  Result: {s}\n\n", .{if (found) "✅ PASS" else "❌ FAIL"});

        try testing.expect(found);
    }

    print("=== All comment spacing tests completed ===\n", .{});
}
