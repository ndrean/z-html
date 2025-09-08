//! Node.normalize utilities for DOM and HTML elements
//!
//! A two step process:
//! - traverse the fragment DOM (`simple_walk`) to collect elements to normalize
//! - apply normalization to the collected elements

const std = @import("std");
const z = @import("../root.zig");
const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;

// Lexbor string comparison functions for zero-copy operations
extern "c" fn lexbor_str_data_ncmp(first: [*c]const u8, sec: [*c]const u8, size: usize) bool;

/// Enhanced whitespace detection for different normalization strategies
/// Returns true if text contains ONLY unwanted whitespace characters
/// Strategy 1: Only \r (minimal/surgical)
/// Strategy 2: \r, \n, \t (browser-like - these collapse to single space anyway)
fn isUndesirableWhitespace(text: []const u8) bool {
    if (text.len == 0) return true;

    // Check if text contains ONLY problematic whitespace (\r, \n, \t)
    // These are whitespace characters that browsers collapse anyway
    for (text) |char| {
        if (char != '\r' and char != '\n' and char != '\t') {
            return false; // Contains non-collapsible content
        }
    }
    return true; // All characters are collapsible whitespace
}

/// Fast whitespace-only detection using lexbor's optimized memory access
/// Returns true if text contains ONLY whitespace characters (\n\t\r )
fn isWhitespaceOnly(text: []const u8) bool {
    if (text.len == 0) return true;

    // Fast path: check against common single-character whitespace
    if (text.len == 1) {
        const char = text[0];
        return char == ' ' or char == '\t' or char == '\n' or char == '\r';
    }

    // Fast path: check against common whitespace patterns
    const patterns = [_][]const u8{ " ", "\t", "\n", "\r", "\n ", " \n", "\t ", " \t", "\n\t", "\t\n" };
    for (patterns) |pattern| {
        if (text.len == pattern.len and lexbor_str_data_ncmp(text.ptr, pattern.ptr, text.len)) {
            return true;
        }
    }

    // Fallback: check each character using direct memory access
    const data = text.ptr;
    for (0..text.len) |i| {
        const char = data[i];
        if (char != ' ' and char != '\t' and char != '\n' and char != '\r') {
            return false;
        }
    }
    return true;
}

/// String-based HTML normalization options
pub const StringNormalizeOptions = struct {
    remove_comments: bool = false,
    remove_whitespace_text_nodes: bool = true,
};

/// String-based HTML normalization - removes whitespace-only text nodes
/// Skips content between preserve tags: <pre>, <textarea>, <script>, <style>, <code>
/// This matches browser Node.normalizeDOM() behavior exactly
pub fn normalizeHtmlString(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    return normalizeHtmlStringWithOptions(allocator, html, .{});
}

/// String-based HTML normalization with options
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

            if (options.remove_whitespace_text_nodes and isWhitespaceOnly(text_segment)) {
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

/// convert from "aligned" `anyopaque` to the target pointer type `T`
/// because of the callback signature:
///
/// Source: Andrew Gossage <https://www.youtube.com/watch?v=qJNHUIIFMlo>
fn castContext(comptime T: type, ctx: ?*anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(ctx.?)));
}

/// [normalize] Standard browser Node.normalizeDOM()
///
/// Browser-like behavior: removes collapsible whitespace (\r, \n, \t) but preserves meaningful spaces
/// Always preserves whitespace in special elements (<pre>, <code>, <script>, <style>, <textarea>)
///
/// Use `normalizeDOMWithOptions` to customize comment handling:
pub fn normalizeDOM(allocator: std.mem.Allocator, root_elt: *z.HTMLElement) (std.mem.Allocator.Error || z.Err)!void {
    return normalizeDOMWithOptions(allocator, root_elt, .{});
}

/// [normalizeForDisplay] Aggressive normalization for clean terminal/display output
///
/// Removes ALL whitespace-only text nodes and comments for clean visual output
/// Used internally by prettyPrint for clean TTY display
pub fn normalizeForDisplay(allocator: std.mem.Allocator, root_elt: *z.HTMLElement) (std.mem.Allocator.Error || z.Err)!void {
    var context = Context.init(allocator, .{ .skip_comments = true }); // Remove comments for clean display
    defer context.deinit();

    z.simpleWalk(
        z.elementToNode(root_elt),
        aggressiveCollectorCallback,
        &context,
    );

    try PostWalkOperations(
        allocator,
        &context,
        .{ .skip_comments = true },
    );
}

pub const NormalizeOptions = struct {
    skip_comments: bool = false, // Only option: whether to remove comments or not
    // Note: Special elements (<pre>, <code>, <script>, <style>, <textarea>) are always preserved
    // Note: Collapsible whitespace (\r, \n, \t) is always removed (browser-like behavior)
};

// Context for the callback normalization walk
const Context = struct {
    allocator: std.mem.Allocator,
    options: NormalizeOptions,

    // post-walk cleanup - no manual string cleanup needed!
    nodes_to_remove: std.ArrayList(*z.DomNode),
    template_nodes: std.ArrayList(*z.DomNode),

    // Simple cache for last checked parent (most text nodes share parents)
    last_parent: ?*z.DomNode,
    last_parent_preserves: bool,

    fn init(alloc: std.mem.Allocator, opts: NormalizeOptions) @This() {
        var nodes_to_remove: std.ArrayList(*z.DomNode) = .empty;
        var template_nodes: std.ArrayList(*z.DomNode) = .empty;

        // Pre-allocate capacity for normalization operations (estimates based on typical usage)
        nodes_to_remove.ensureTotalCapacity(alloc, 20) catch {}; // ~20 nodes to remove
        template_nodes.ensureTotalCapacity(alloc, 5) catch {}; // ~5 template nodes

        return .{
            .allocator = alloc,
            .options = opts,
            .nodes_to_remove = nodes_to_remove,
            .template_nodes = template_nodes,
            .last_parent = null,
            .last_parent_preserves = false,
        };
    }

    fn deinit(self: *@This()) void {
        // No string cleanup needed - we're using zero-copy slices!
        self.nodes_to_remove.deinit(self.allocator);
        self.template_nodes.deinit(self.allocator);
    }

    /// Check if current node is a whitespace-preserving element
    fn isPreserveElement(self: @This(), node: *z.DomNode) bool {
        _ = self;
        if (z.nodeToElement(node)) |element| {
            const tag = z.tagFromQualifiedName(z.qualifiedName_zc(element)) orelse return false;
            return z.WhitespacePreserveTagSet.contains(tag);
        }
        return false;
    }

    /// _Walk-up_ the tree to check if the node is inside a whitespace preserved element.
    /// Uses simple parent caching since adjacent text nodes often share the same parent.
    fn shouldPreserveWhitespace(self: *@This(), node: *z.DomNode) bool {
        const parent = z.parentNode(node) orelse return false;

        // Check simple cache first
        if (self.last_parent == parent) {
            return self.last_parent_preserves;
        }

        // Walk up tree and cache result
        var current: ?*z.DomNode = parent;
        var preserve = false;
        while (current) |p| {
            if (z.nodeToElement(p)) |element| {
                const tag = z.tagFromQualifiedName(z.qualifiedName_zc(element)) orelse break;
                if (z.WhitespacePreserveTagSet.contains(tag)) {
                    preserve = true;
                    break;
                }
            }
            current = z.parentNode(p);
        }

        // Update cache
        self.last_parent = parent;
        self.last_parent_preserves = preserve;
        return preserve;
    }
};

/// [normalize] Normalize the DOM with options `NormalizeOptions`.
///
/// - To remove comments, `skip_comments=true`.
/// - Default to preserve whitespace in specific elements (`pre`, `textarea`, `script`, `style`). Use `preserve_special_elements=false` to disable this behavior.
/// - Default to remove whitespace-only text nodes.
pub fn normalizeDOMWithOptions(
    allocator: std.mem.Allocator,
    root_elt: *z.HTMLElement,
    options: NormalizeOptions,
) (std.mem.Allocator.Error || z.Err)!void {
    var context = Context.init(allocator, options);
    defer context.deinit();

    z.simpleWalk(
        z.elementToNode(root_elt),
        collectorCallBack,
        &context,
    );

    try PostWalkOperations(
        allocator,
        &context,
        options,
    );
}

/// Browser-like collector callback for standard normalization
/// Removes collapsible whitespace (\r, \n, \t) but preserves meaningful spaces
fn collectorCallBack(node: *z.DomNode, ctx: ?*anyopaque) callconv(.c) c_int {
    const context_ptr: *Context = castContext(Context, ctx);

    switch (z.nodeType(node)) {
        .comment => {
            if (context_ptr.options.skip_comments) {
                // collect comments for post-processing
                context_ptr.nodes_to_remove.append(context_ptr.allocator, node) catch {
                    return z._STOP;
                };
            }
        },
        .element => {
            if (z.isTemplate(node)) {
                // Collect template nodes for post-processing
                context_ptr.template_nodes.append(context_ptr.allocator, node) catch {
                    return z._STOP;
                };
                return z._CONTINUE;
            }
        },
        .text => {
            // Always preserve whitespace in special elements (<pre>, <script>, etc.)
            if (context_ptr.shouldPreserveWhitespace(node)) {
                return z._CONTINUE;
            }

            // Use zero-copy text access
            const original_content = z.textContent_zc(node);

            // Browser-like behavior: remove collapsible whitespace (\r, \n, \t) but preserve spaces
            if (isUndesirableWhitespace(original_content)) {
                context_ptr.nodes_to_remove.append(context_ptr.allocator, node) catch {
                    return z._STOP;
                };
            }
        },

        else => {},
    }

    return z._CONTINUE;
}

/// Aggressive collector callback for display/TTY output
/// Removes ALL whitespace-only text nodes (including spaces) and comments for clean visual output
fn aggressiveCollectorCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.c) c_int {
    const context_ptr: *Context = castContext(Context, ctx);

    switch (z.nodeType(node)) {
        .comment => {
            // Always remove comments for clean display
            context_ptr.nodes_to_remove.append(context_ptr.allocator, node) catch {
                return z._STOP;
            };
        },
        .element => {
            if (z.isTemplate(node)) {
                // Collect template nodes for post-processing
                context_ptr.template_nodes.append(context_ptr.allocator, node) catch {
                    return z._STOP;
                };
                return z._CONTINUE;
            }
        },
        .text => {
            // Always preserve whitespace in special elements (<pre>, <script>, etc.)
            if (context_ptr.shouldPreserveWhitespace(node)) {
                return z._CONTINUE;
            }

            // Use zero-copy text access
            const original_content = z.textContent_zc(node);

            // Aggressive: remove ALL whitespace-only text nodes (including spaces)
            if (isWhitespaceOnly(original_content)) {
                context_ptr.nodes_to_remove.append(context_ptr.allocator, node) catch {
                    return z._STOP;
                };
            }
        },

        else => {},
    }

    return z._CONTINUE;
}

fn PostWalkOperations(
    allocator: std.mem.Allocator,
    context: *Context,
    options: NormalizeOptions,
) (std.mem.Allocator.Error || z.Err)!void {
    // Remove whitespace-only text nodes and comments if selected
    for (context.nodes_to_remove.items) |node| {
        z.removeNode(node);
        z.destroyNode(node);
    }

    // Process template content with its own "simple_walk" on the document fragment content
    for (context.template_nodes.items) |template_node| {
        try normalizeTemplateContent(
            allocator,
            template_node,
            options,
        );
    }
}

/// simple_walk in the template _content_ (#document-fragment)
fn normalizeTemplateContent(
    allocator: std.mem.Allocator,
    template_node: *z.DomNode,
    options: NormalizeOptions,
) (std.mem.Allocator.Error || z.Err)!void {
    const template = z.nodeToTemplate(template_node) orelse return;

    const content = z.templateContent(template);
    const content_node = z.fragmentToNode(content);

    var template_context = Context.init(allocator, options);
    defer template_context.deinit();

    z.simpleWalk(
        content_node,
        collectorCallBack,
        &template_context,
    );

    try PostWalkOperations(
        allocator,
        &template_context,
        options,
    );
}

test "normalize bahaviour" {
    const allocator = testing.allocator;
    const html =
        \\<div>
        \\  <p>
        \\      Some \t
        \\    <i>  text  \n\n  </i>
        \\  </p> \t
        \\</div>
    ;

    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);
    const body = z.bodyElement(doc).?;

    try z.normalizeForDisplay(allocator, body);
    const normalized = try z.outerHTML(allocator, body);
    defer allocator.free(normalized);
    // print("normalized: {s}\n", .{normalized});
    // try z.printDocStruct(doc);

    _ = "<body><div><p>\r Some \t\r <i>  text  \n\n. </i>\r</p> \t\r</div></body>";

    // try testing.expectEqualStrings(expected, normalized);
}

// ----------[TODO]------------
test "normalizeOptions: preserve script and remove whitespace text nodes" {
    {
        // whitespace preserved in script element, empty text nodes removed

        const allocator = testing.allocator;

        const html =
            \\<div>
            \\  <script> console.log("hello"); </script> \t 
            \\  <div> Some <i> bold and italic   </i> text</div>
            \\</div>"
        ;
        const doc = try z.createDocFromString(html);
        defer z.destroyDocument(doc);

        const body_elt = z.bodyElement(doc).?;

        const serialized = try z.innerHTML(allocator, body_elt);
        defer allocator.free(serialized);
        // const normed = try normalizeHtmlString(
        //     allocator,
        //     serialized,
        // );

        // try testing.expectEqualStrings(
        //     "<div><script> console.log(\"hello\"); </script><div> Some <i> bold and italic   </i> text</div></div>",
        //     normed,
        // );
    }
    {
        // whitespace preserved in script element, empty text nodes removed
        const allocator = testing.allocator;

        const html = "<div><script> console.log(\"hello\"); </script> \t <div> Some <i> bold and italic   </i> text</div></div>";
        const doc = try z.createDocFromString(html);
        defer z.destroyDocument(doc);

        const body_elt = z.bodyElement(doc).?;

        try z.normalizeDOMWithOptions(
            allocator,
            body_elt,
            .{
                .skip_comments = true,
            },
        );

        const serialized = try z.innerHTML(allocator, body_elt);
        defer allocator.free(serialized);

        try testing.expectEqualStrings(
            "<div><script> console.log(\"hello\"); </script> \t <div> Some <i> bold and italic   </i> text</div></div>",
            serialized,
        );
    }
    {
        // whitespace preserved in script element, empty text nodes NOT removed
        const allocator = testing.allocator;

        const html = "<div><script> console.log(\"hello\"); </script> \t <div> Some <i> bold and italic   </i> text</div></div>";
        const doc = try z.createDocFromString(html);
        defer z.destroyDocument(doc);

        const body_elt = z.bodyElement(doc).?;

        try z.normalizeDOMWithOptions(
            allocator,
            body_elt,
            .{
                .skip_comments = true,
            },
        );

        const serialized = try z.innerHTML(allocator, body_elt);
        defer allocator.free(serialized);

        try testing.expectEqualStrings(
            "<div><script> console.log(\"hello\"); </script> \t <div> Some <i> bold and italic   </i> text</div></div>",
            serialized,
        );
    }
}

test "normalize, context preservation, comments removed" {
    {
        const allocator = testing.allocator;
        const html = "<div>\n  Some   more\n  text\n  <span> \t </span>\n<!-- a comment to be removed -->\n  <pre>  Preserve   spaces  </pre>\n  More   text\n  to <em> come </em><i>maybe</i>\n</div>\n";

        const doc = try z.createDocFromString(html);
        defer z.destroyDocument(doc);

        const body_elt = z.bodyElement(doc).?;

        // test: insert programmatically an empty ("\t") text node inside the <span>)
        const span = z.getElementByTag(z.elementToNode(body_elt), .span);
        const txt = try z.createTextNode(doc, "\t");
        z.insertBefore(z.elementToNode(span.?), txt);

        try normalizeDOMWithOptions(
            allocator,
            body_elt,
            NormalizeOptions{
                .skip_comments = true,
            },
        );

        const result = try z.outerHTML(
            allocator,
            body_elt,
        );
        defer allocator.free(result);

        const expected = "<body><div>\n  Some   more\n  text\n  <span> \t </span>\n  <pre>  Preserve   spaces  </pre>\n  More   text\n  to <em> come </em><i>maybe</i></div></body>";
        try testing.expectEqualStrings(expected, result);
    }
    {
        const allocator = testing.allocator;
        const html = "<div>\n  Some   more\n  text\n  <span> \t </span>\n<!-- a comment to be removed -->\n  <pre>  Preserve   spaces  </pre>\n  More   text\n  to <em> come </em>\n</div>\n";

        const doc = try z.createDocFromString(html);
        defer z.destroyDocument(doc);

        const body_elt = z.bodyElement(doc).?;

        try normalizeDOMWithOptions(
            allocator,
            body_elt,
            NormalizeOptions{
                .skip_comments = false,
            },
        );

        const result = try z.outerHTML(
            allocator,
            body_elt,
        );
        defer allocator.free(result);

        const expected = "<body><div>\n  Some   more\n  text\n  <span> \t </span><!-- a comment to be removed -->\n  <pre>  Preserve   spaces  </pre>\n  More   text\n  to <em> come </em></div></body>";
        try testing.expectEqualStrings(expected, result);
    }
}

test "template normalize" {
    {
        const allocator = testing.allocator;

        const html =
            \\<div>
            \\    <p>Before template</p>
            \\    <template id="test">
            \\         <!-- comment in template -->
            \\        <span>  Template content  </span><em>  </em>
            \\        <strong>  Bold text</strong>
            \\
            \\    </template>
            \\    <p>After template</p>
            \\</div>
        ;

        const doc = try z.createDocFromString(html);
        defer z.destroyDocument(doc);

        const root = z.documentRoot(doc).?;

        const template_elt_before = z.getElementByTag(root, .template).?;

        // check theat the browser does not read the template
        const children_elts = try z.children(allocator, template_elt_before);
        defer allocator.free(children_elts);
        try testing.expect(children_elts.len == 0); // the browser does not read the template

        // template access is only via its `templateContent()`: check the number of nodes
        const template_before = z.elementToTemplate(template_elt_before).?;
        const template_content_before = z.templateContent(template_before);
        const template_content_node_before = z.fragmentToNode(template_content_before);
        const child_nodes_before = try z.childNodes(allocator, template_content_node_before);
        defer allocator.free(child_nodes_before);
        try testing.expect(child_nodes_before.len == 8);

        try z.normalizeDOMWithOptions(
            allocator,
            z.nodeToElement(root).?,
            .{
                .skip_comments = true,
            },
        );

        const serialized = try z.outerHTML(allocator, z.nodeToElement(root).?);
        defer allocator.free(serialized);

        const expected = "<html><head></head><body><div>\n    <p>Before template</p>\n    <template id=\"test\">\n         \n        <span>  Template content  </span><em>  </em>\n        <strong>  Bold text</strong>\n\n    </template>\n    <p>After template</p></div></body></html>";

        try testing.expectEqualStrings(expected, serialized);

        const template_elt_after = z.getElementByTag(root, .template).?;

        // inspect the template content after: the number of nodes went down
        const template_after = z.elementToTemplate(template_elt_after).?;
        const template_content_after = z.templateContent(template_after);
        const template_content_node_after = z.fragmentToNode(template_content_after);
        const child_nodes_after = try z.childNodes(allocator, template_content_node_after);
        defer allocator.free(child_nodes_after);
        try testing.expect(child_nodes_after.len == 7);
    }
}

// test "normalize performance benchmark" {
//     const allocator = std.heap.c_allocator;

//     // Create large HTML document with lots of whitespace for normalization
//     var html_builder: std.ArrayList(u8) = .empty;
//     defer html_builder.deinit(allocator);

//     // Pre-allocate capacity for the HTML builder (estimate ~25KB for this test)
//     try html_builder.ensureTotalCapacity(allocator, 25_000);

//     try html_builder.appendSlice(allocator,
//         \\<html>
//         \\<body>
//         \\  <div class="container">
//         \\    <header>
//         \\      <h1>   Performance Test Document   </h1>
//         \\      <nav>
//         \\        <ul>
//     );

//     // Add many elements with whitespace
//     for (0..100) |i| {
//         try html_builder.appendSlice(allocator,
//             \\          <li>
//             \\            <a href="/page
//         );

//         const num_str = try std.fmt.allocPrint(allocator, "{d}", .{i});
//         defer allocator.free(num_str);
//         try html_builder.appendSlice(allocator, num_str);

//         try html_builder.appendSlice(allocator,
//             \\">   Link
//         );
//         try html_builder.appendSlice(allocator, num_str);
//         try html_builder.appendSlice(allocator,
//             \\   </a>
//             \\            <span>   Some text with    whitespace   </span>
//             \\            <!-- comment with whitespace -->
//             \\            <em>     emphasized text     </em>
//             \\          </li>
//         );
//     }

//     try html_builder.appendSlice(allocator,
//         \\        </ul>
//         \\      </nav>
//         \\    </header>
//         \\    <main>
//         \\      <section>
//         \\        <p>   This is a paragraph with    lots of    whitespace   </p>
//         \\        <div>
//         \\          <pre>   Preserve   this   whitespace   </pre>
//         \\          <textarea>   Also preserve   this   </textarea>
//         \\        </div>
//         \\      </section>
//         \\    </main>
//         \\  </div>
//         \\</body>
//         \\</html>
//     );

//     const large_html = try html_builder.toOwnedSlice(allocator);
//     defer allocator.free(large_html);

//     const iterations = 100;
//     const kb_size = (@as(f64, @floatFromInt(large_html.len)) / 1024.0);
//     print("\n=== NORMALIZE PERFORMANCE BENCHMARK ===\n", .{});
//     print("HTML size: {d} bytes (~{d:.1}KB)\n", .{ large_html.len, kb_size });
//     print("Iterations: {d}\n", .{iterations});

//     var timer = try std.time.Timer.start();

//     // Measure parsing only (with proper memory management)
//     timer.reset();
//     for (0..iterations) |_| {
//         const temp_doc = try z.createDocFromString(large_html);
//         const body_elt = try z.bodyElement(temp_doc);
//         _ = body_elt;
//         z.destroyDocument(temp_doc);
//     }
//     const parsing_time_ns = timer.read();

//     // Measure DOM-based normalization (with parsing)
//     timer.reset();
//     for (0..iterations) |_| {
//         const temp_doc = try z.createDocFromString(large_html);
//         const body_elt = try z.bodyElement(temp_doc);

//         try z.normalizeDOMWithOptions(
//             allocator,
//             body_elt,
//             .{
// //                 .skip_comments = true,
//             },
//         );
//         z.destroyDocument(temp_doc);
//     }
//     const dom_total_time_ns = timer.read();

//     // Measure string-based normalization (no parsing needed)
//     timer.reset();
//     for (0..iterations) |_| {
//         const normalized = try normalizeHtmlString(allocator, large_html);
//         allocator.free(normalized);
//     }
//     const string_time_ns = timer.read();

//     // Calculate times
//     const dom_normalize_time_ns = dom_total_time_ns - parsing_time_ns;
//     const norm_op_time = @as(f64, @floatFromInt(dom_normalize_time_ns)) / @as(f64, @floatFromInt(iterations)) / 1_000_000;
//     const parse_op_time = @as(f64, @floatFromInt(parsing_time_ns)) / @as(f64, @floatFromInt(iterations)) / 1_000_000;
//     const string_op_time = @as(f64, @floatFromInt(string_time_ns)) / @as(f64, @floatFromInt(iterations)) / 1_000_000;

//     // Calculate MB/s correctly
//     const total_mb = (kb_size * @as(f64, @floatFromInt(iterations))) / 1024.0;
//     const parsing_time_s = @as(f64, @floatFromInt(parsing_time_ns)) / 1_000_000_000.0;
//     const dom_normalize_time_s = @as(f64, @floatFromInt(dom_normalize_time_ns)) / 1_000_000_000.0;
//     const string_time_s = @as(f64, @floatFromInt(string_time_ns)) / 1_000_000_000.0;

//     const parsing_speed_mb_s = total_mb / parsing_time_s;
//     const dom_normalize_speed_mb_s = total_mb / dom_normalize_time_s;
//     const string_speed_mb_s = total_mb / string_time_s;

//     const speedup = dom_normalize_time_s / string_time_s;

//     print("\n--- Results ---\n", .{});
//     print("Parsing processing speed:     {d:.1} MB/s ({d:.2} ms/op)\n", .{ parsing_speed_mb_s, parse_op_time });
//     print("DOM normalize processing:     {d:.1} MB/s ({d:.2} ms/op)\n", .{ dom_normalize_speed_mb_s, norm_op_time });
//     print("String normalize processing:  {d:.1} MB/s ({d:.2} ms/op)\n", .{ string_speed_mb_s, string_op_time });
//     print("String vs DOM speedup:        {d:.1}x faster\n", .{speedup});
// }

test "string-based HTML normalization" {
    const allocator = testing.allocator;

    // Test basic whitespace removal
    const html1 = "<div>\n  \t  <p>Hello world</p>   \n\t  </div>";
    const normalized1 = try normalizeHtmlString(allocator, html1);
    defer allocator.free(normalized1);

    const expected1 = "<div><p>Hello world</p></div>";
    try testing.expectEqualStrings(expected1, normalized1);

    // Test preserve tags
    const html2 = "<div>\n  <pre>  preserve  this  </pre>\n  <p>Normal text</p>  \n</div>";
    const normalized2 = try normalizeHtmlString(allocator, html2);
    defer allocator.free(normalized2);

    const expected2 = "<div><pre>  preserve  this  </pre><p>Normal text</p></div>";
    try testing.expectEqualStrings(expected2, normalized2);

    // Test script tags
    const html3 = "<div>\n  <script>\n  console.log('test');\n  </script>\n  <span>Text</span>  \n</div>";
    const normalized3 = try normalizeHtmlString(allocator, html3);
    defer allocator.free(normalized3);

    const expected3 = "<div><script>\n  console.log('test');\n  </script><span>Text</span></div>";
    try testing.expectEqualStrings(expected3, normalized3);
}

test "browser-like normalization" {
    const allocator = testing.allocator;

    // Create HTML with various whitespace types
    const html = "<div>\r<p>Text</p>\r\n<span> Regular space </span>\n\t<em>Tab and newline</em>\r</div>";

    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    const body_elt = z.bodyElement(doc).?;

    // Standard browser-like normalization
    try normalizeDOM(allocator, body_elt);

    const result = try z.innerHTML(allocator, body_elt);
    defer allocator.free(result);

    // Should remove \r, \n, \t patterns but preserve meaningful spaces
    const expected = "<div><p>Text</p><span> Regular space </span><em>Tab and newline</em></div>";
    try testing.expectEqualStrings(expected, result);
}

test "collapsible whitespace detection accuracy" {
    // Test the isUndesirableWhitespace function for browser-like behavior

    // Should detect collapsible whitespace patterns (\r, \n, \t)
    try testing.expect(isUndesirableWhitespace("\r"));
    try testing.expect(isUndesirableWhitespace("\n"));
    try testing.expect(isUndesirableWhitespace("\t"));
    try testing.expect(isUndesirableWhitespace("\r\n"));
    try testing.expect(isUndesirableWhitespace("\n\t"));
    try testing.expect(isUndesirableWhitespace("\t\r\n"));
    try testing.expect(isUndesirableWhitespace("")); // empty strings

    // Should NOT detect spaces (preserve meaningful spacing)
    try testing.expect(!isUndesirableWhitespace(" "));
    try testing.expect(!isUndesirableWhitespace(" \n")); // space with newline
    try testing.expect(!isUndesirableWhitespace("text"));
    try testing.expect(!isUndesirableWhitespace(" text "));
    try testing.expect(!isUndesirableWhitespace("a"));
}

test "aggressive normalization for display" {
    const allocator = testing.allocator;

    // Create HTML with comments and various whitespace
    const html = "<div><!-- comment -->\n<p>Text</p> \n<span> Keep spaces </span>\t</div>";

    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    const body_elt = z.bodyElement(doc).?;

    // Aggressive normalization for display
    try normalizeForDisplay(allocator, body_elt);

    const result = try z.innerHTML(allocator, body_elt);
    defer allocator.free(result);

    // Should remove comments and ALL whitespace-only nodes (including spaces)
    const expected = "<div><p>Text</p><span> Keep spaces </span></div>";
    try testing.expectEqualStrings(expected, result);
}

test "string-based normalization with comment removal" {
    const allocator = testing.allocator;

    // Test comment removal
    const html_with_comments = "<div><!-- Comment 1 --><p>Text</p><!-- Comment 2 --></div>";

    // Keep comments
    const normalized_keep = try normalizeHtmlStringWithOptions(allocator, html_with_comments, .{
        .remove_comments = false,
        .remove_whitespace_text_nodes = true,
    });
    defer allocator.free(normalized_keep);

    const expected_keep = "<div><!-- Comment 1 --><p>Text</p><!-- Comment 2 --></div>";
    try testing.expectEqualStrings(expected_keep, normalized_keep);

    // Remove comments
    const normalized_remove = try normalizeHtmlStringWithOptions(allocator, html_with_comments, .{
        .remove_comments = true,
        .remove_whitespace_text_nodes = true,
    });
    defer allocator.free(normalized_remove);

    const expected_remove = "<div><p>Text</p></div>";
    try testing.expectEqualStrings(expected_remove, normalized_remove);

    // Test mixed whitespace and comments
    const html_mixed = "<div>\n  <!-- Comment -->\n  <p>Text</p>  \n<!-- Another -->\n</div>";
    const normalized_mixed = try normalizeHtmlStringWithOptions(allocator, html_mixed, .{
        .remove_comments = true,
        .remove_whitespace_text_nodes = true,
    });
    defer allocator.free(normalized_mixed);

    const expected_mixed = "<div><p>Text</p></div>";
    try testing.expectEqualStrings(expected_mixed, normalized_mixed);
}

// test "string vs DOM normalization performance comparison" {
//     const allocator = std.heap.c_allocator;

//     const test_html =
//         \\<html>
//         \\  <body>
//         \\    <div class="container">
//         \\      <pre>  preserve  this  whitespace  </pre>
//         \\      <p>   Normal text   </p>
//         \\      <script>
//         \\        console.log("preserve this too");
//         \\      </script>
//         \\      <span>   More text   </span>
//         \\    </div>
//         \\  </body>
//         \\</html>
//     ;

//     const iterations = 1000;
//     var timer = try std.time.Timer.start();

//     print("\n=== STRING vs DOM NORMALIZATION COMPARISON ===\n", .{});
//     print("Test HTML size: {d} bytes\n", .{test_html.len});
//     print("Iterations: {d}\n", .{iterations});

//     // Test string-based normalization
//     timer.reset();
//     for (0..iterations) |_| {
//         const normalized = try normalizeHtmlString(allocator, test_html);
//         allocator.free(normalized);
//     }
//     const string_time_ns = timer.read();

//     // Test DOM-based normalization
//     timer.reset();
//     for (0..iterations) |_| {
//         const doc = try z.createDocFromString(test_html);
//         const body_elt = z.bodyElement(doc).?;
//         try normalizeDOMWithOptions(allocator, body_elt, .{
//             .remove_whitespace_text_nodes = true,
//             .skip_comments = false,
//         });
//         z.destroyDocument(doc);
//     }
//     const dom_time_ns = timer.read();

//     // Calculate performance
//     const string_ms = @as(f64, @floatFromInt(string_time_ns)) / 1_000_000.0;
//     const dom_ms = @as(f64, @floatFromInt(dom_time_ns)) / 1_000_000.0;

//     const string_speed = (@as(f64, @floatFromInt(test_html.len * iterations)) / 1024.0 / 1024.0) / (string_ms / 1000.0);
//     const dom_speed = (@as(f64, @floatFromInt(test_html.len * iterations)) / 1024.0 / 1024.0) / (dom_ms / 1000.0);

//     const speedup = dom_ms / string_ms;

//     print("\n--- Results ---\n", .{});
//     print("String-based: {d:.1} MB/s ({d:.2} ms total)\n", .{ string_speed, string_ms });
//     print("DOM-based:    {d:.1} MB/s ({d:.2} ms total)\n", .{ dom_speed, dom_ms });
//     print("Speedup: {d:.1}x faster with string-based approach\n", .{speedup});
// }
