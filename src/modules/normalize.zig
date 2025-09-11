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

/// [normalize] Returns true if text contains ONLY whitespace characters (\n\t\r or " ")
pub fn isWhitespaceOnly(text: []const u8) bool {
    if (text.len == 0) return true;

    // Fast path: check against common single-character whitespace
    if (text.len == 1) {
        const char = text[0];
        return char == ' ' or char == '\t' or char == '\n' or char == '\r';
    }

    const data = text.ptr;
    for (0..text.len) |i| {
        const char = data[i];
        if (char != ' ' and char != '\t' and char != '\n' and char != '\r') {
            return false;
        }
    }
    return true;
}

/// Returns true if text contains ONLY the whitespace characters \t or \n or \r
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

test "isWhitespaceOnly & isUndesirableWhitespace" {
    const t1 = "  ";
    std.debug.assert(isWhitespaceOnly(t1));
    std.debug.assert(!isUndesirableWhitespace(t1));

    const t2 = "\n\t\r";
    std.debug.assert(isWhitespaceOnly(t2));
    std.debug.assert(isUndesirableWhitespace(t2));

    const t3 = " \n\t\r";
    std.debug.assert(isWhitespaceOnly(t3));
    std.debug.assert(!isUndesirableWhitespace(t3));

    const t4 = " \n\t\ra";
    std.debug.assert(!isWhitespaceOnly(t4));
    std.debug.assert(!isUndesirableWhitespace(t4));
}

/// convert from "aligned" `anyopaque` to the target pointer type `T`
/// because of the callback signature:
///
/// Source: Andrew Gossage <https://www.youtube.com/watch?v=qJNHUIIFMlo>
fn castContext(comptime T: type, ctx: ?*anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(ctx.?)));
}

// === DOM based normalization: Node.normalize() like -----------------------------------------

/// [normalize] Standard browser Node.normalizeDOM()
///
/// Browser-like behavior: removes collapsible whitespace (\r, \n, \t) but preserves meaningful spaces
/// Always preserves whitespace in special elements (<pre>, <code>, <script>, <style>, <textarea>)
///
/// Use `normalizeDOMwithOptions` to customize comment handling:
pub fn normalizeDOM(allocator: std.mem.Allocator, root_elt: *z.HTMLElement) (std.mem.Allocator.Error || z.Err)!void {
    return normalizeDOMwithOptions(allocator, root_elt, .{});
}

/// [normalizeDOMForDisplay] Aggressive normalization for clean terminal/display output
///
/// Removes ALL whitespace-only text nodes and comments for clean visual output
/// Used internally by prettyPrint for clean TTY display
pub fn normalizeDOMForDisplay(allocator: std.mem.Allocator, root_elt: *z.HTMLElement) (std.mem.Allocator.Error || z.Err)!void {
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
/// - To remove comments, use `skip_comments=true`.
/// - Always preserves whitespace in specific elements (`pre`, `textarea`, `script`, `style`, `code`).
/// - Removes collapsible whitespace (\r, \n, \t) from other elements while preserving meaningful spaces.
pub fn normalizeDOMwithOptions(
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

test "first normalization test - whitespaceOnly text nodes removal" {
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

// multiline version
test "normalizeOptions: preserve script and remove whitespace text nodes" {
    const allocator = testing.allocator;
    const html =
        \\<div>
        \\  <!-- a comment -->
        \\  <script> console.log("hello"); </script>
        \\  <pre>  Preserve   spaces  </pre>
        \\  <div> Some <i> bold and italic   </i> text</div>
        \\</div>
    ;
    // whitespace preserved in script element and in elements, empty text nodes removed
    {
        const doc = try z.createDocFromString(html);
        defer z.destroyDocument(doc);

        const body_elt = z.bodyElement(doc).?;

        try z.normalizeDOMwithOptions(
            allocator,
            body_elt,
            .{
                .skip_comments = false,
            },
        );

        const serialized = try z.innerHTML(allocator, body_elt);
        defer allocator.free(serialized);

        // only whitespace-only text nodes should be removed
        const expected =
            \\<div>
            \\  <!-- a comment -->
            \\  <script> console.log("hello"); </script>
            \\  <pre>  Preserve   spaces  </pre>
            \\  <div> Some <i> bold and italic   </i> text</div></div>
        ;

        try testing.expectEqualStrings(expected, serialized);
    }
    // comment removal: leaves whitespace characters as they were
    {
        const doc = try z.createDocFromString(html);
        defer z.destroyDocument(doc);

        const body_elt = z.bodyElement(doc).?;

        try z.normalizeDOMwithOptions(
            allocator,
            body_elt,
            .{
                .skip_comments = true,
            },
        );

        const serialized = try z.innerHTML(allocator, body_elt);
        defer allocator.free(serialized);

        // the whitespace characters before the comment are maintained
        const expected =
            \\<div>
            \\  
            \\  <script> console.log("hello"); </script>
            \\  <pre>  Preserve   spaces  </pre>
            \\  <div> Some <i> bold and italic   </i> text</div></div>
        ;

        try testing.expectEqualStrings(expected, serialized);
    }
}

test "normalization for display: removal of comments don't leave empty text node" {
    const allocator = testing.allocator;
    const html =
        \\<div>
        \\  <!-- comment -->
        \\  <p>Text</p>
        \\  <span> Keep spaces </span>
        \\</div>
    ;

    // const html = "<div><!-- comment -->\n<p>Text</p> \n<span> Keep spaces </span>\t</div>";

    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    const body_elt = z.bodyElement(doc).?;

    // Aggressive normalization for display
    try normalizeDOMForDisplay(allocator, body_elt);

    const result = try z.innerHTML(allocator, body_elt);
    defer allocator.free(result);

    // Should remove comments and ALL whitespace-only nodes (including spaces)
    const expected = "<div><p>Text</p><span> Keep spaces </span></div>";
    try testing.expectEqualStrings(expected, result);
}

test "template normalize" {
    const allocator = testing.allocator;

    const html =
        \\<div>
        \\  <p>Before template</p>
        \\  <template id="test">
        \\  <!-- comment in template -->
        \\  <span>  Template content  </span><em>  </em>
        \\  <strong>  Bold text</strong>
        \\  </template>
        \\  <p>After template</p>
        \\</div>
    ;

    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    const root = z.documentRoot(doc).?;

    try z.normalizeDOMwithOptions(
        allocator,
        z.nodeToElement(root).?,
        .{
            .skip_comments = true,
        },
    );

    const serialized = try z.outerHTML(allocator, z.nodeToElement(root).?);
    defer allocator.free(serialized);

    const expected =
        \\<html><head></head><body><div>
        \\  <p>Before template</p>
        \\  <template id="test">
        \\  
        \\  <span>  Template content  </span><em>  </em>
        \\  <strong>  Bold text</strong>
        \\  </template>
        \\  <p>After template</p></div></body></html>
    ;

    try testing.expectEqualStrings(expected, serialized);
}

test "string vs DOM" {
    const allocator = testing.allocator;
    const messy_html =
        \\<div>
        \\<!-- comment -->
        \\
        \\<p>Content</p>
        \\
        \\<pre>  preserve  this  </pre>
        \\
        \\</div>
    ;
    {
        const doc = try z.createDocFromString(messy_html);
        defer z.destroyDocument(doc);
        const body_elt = z.bodyElement(doc).?;
        try z.normalizeDOM(allocator, body_elt);
        const result = try z.innerHTML(allocator, body_elt);
        defer allocator.free(result);
        const expected = "<div><!-- comment --><p>Content</p><pre>  preserve  this  </pre></div>";
        try testing.expectEqualStrings(expected, result);
    }
    {
        const cleaned = try z.normalizeHtmlStringWithOptions(allocator, messy_html, .{ .remove_comments = false });
        defer allocator.free(cleaned);

        const expected = "<div><!-- comment --><p>Content</p><pre>  preserve  this  </pre></div>";
        try testing.expectEqualStrings(expected, cleaned);

        const doc = try z.createDocument();
        defer z.destroyDocument(doc);

        try z.parseString(doc, cleaned);
        const body_elt = z.bodyElement(doc).?;
        const result = try z.innerHTML(allocator, body_elt);
        defer allocator.free(result);
        try testing.expectEqualStrings(expected, result);

        try z.parseString(doc, messy_html);
        const body_elt2 = z.bodyElement(doc).?;
        try z.normalizeDOM(allocator, body_elt2);
        const result2 = try z.innerHTML(allocator, body_elt2);
        defer allocator.free(result2);
        try testing.expectEqualStrings(expected, result2);
    }
}
