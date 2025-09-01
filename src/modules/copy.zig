//! Node.normalize utilities for DOM and HTML elements
//!
//! A two step process:
//! - traverse the fragment DOM (`simple_walk`) to collect elements to normalize
//! - apply normalization to the collected elements

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;

// Fast DOM traversal for optimized ID search
extern "c" fn lxb_dom_node_simple_walk(
    root: *z.DomNode,
    walker_cb: *const fn (*z.DomNode, ?*anyopaque) callconv(.c) c_int,
    ctx: ?*anyopaque,
) void;

/// convert from "aligned" `anyopaque` to the target pointer type `T`
/// because of the callback signature:
///
/// Source: Andrew Gossage <https://www.youtube.com/watch?v=qJNHUIIFMlo>
fn castContext(comptime T: type, ctx: ?*anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(ctx.?)));
}

/// Remove leading/trailing whitespace from all text nodes
pub fn removeOuterWhitespaceTextNodes(allocator: std.mem.Allocator, root_elt: *z.HTMLElement) !void {
    const NormCtx = struct { allocator: std.mem.Allocator };
    var context = NormCtx{ .allocator = allocator };

    const callback = struct {
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.c) c_int {
            const ctx_ptr: *NormCtx = castContext(NormCtx, ctx);
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

    return lxb_dom_node_simple_walk(
        z.elementToNode(root_elt),
        callback,
        &context,
    );
}

test "removeOuterWhitespaceTextNodes" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("<p> Hello   <strong> World    </strong> \nand  <em> \twelcome   \nback</em></p>");
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;
    try removeOuterWhitespaceTextNodes(testing.allocator, z.nodeToElement(body).?);
    const inner = try z.innerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(inner);
    try testing.expectEqualStrings(inner, "<p>Hello<strong>World</strong>and<em>welcome   \nback</em></p>");
}

/// [normalize] Standard browser Node.normalize()
///
/// Trims text nodes only and removes empty text nodes for non-special elements (not `<script>` or `<style>`)
///
/// Use `normalizeWithOptions` to customize behavior:
pub fn normalize(allocator: std.mem.Allocator, root_elt: *z.HTMLElement) (std.mem.Allocator.Error || z.Err)!void {
    return normalizeWithOptions(allocator, root_elt, .{});
}

pub const NormalizeOptions = struct {
    skip_comments: bool = false,
    remove_whitespace_text_nodes: bool = true,
    trim_text: bool = true,
    preserve_special_elements: bool = true,
};

const TextMerge = struct {
    target_node: *z.DomNode,
    new_content: []u8,
};

// Optimized version that avoids dupe() operations
const TextMergeOptimized = struct {
    target_node: *z.DomNode,
    original_content: []const u8, // Zero-copy reference to original text
    trim_start: usize,
    trim_end: usize,
};

// Context for the callback normalization walk
const Context =
    struct {
        allocator: std.mem.Allocator,
        options: NormalizeOptions,

        // post-walk cleanup
        nodes_to_remove: std.ArrayList(*z.DomNode),
        text_merges: std.ArrayList(TextMerge),
        template_nodes: std.ArrayList(*z.DomNode),

        fn init(alloc: std.mem.Allocator, opts: NormalizeOptions) @This() {
            return .{
                .allocator = alloc,
                .options = opts,
                .nodes_to_remove = .empty,
                .text_merges = .empty,
                .template_nodes = .empty,
            };
        }

        fn deinit(self: *@This()) void {
            for (self.text_merges.items) |merge| {
                self.allocator.free(merge.new_content);
            }
            self.text_merges.deinit(self.allocator);
            self.nodes_to_remove.deinit(self.allocator);
            self.template_nodes.deinit(self.allocator);
        }
    };

// Optimized context that avoids dupe() operations
const ContextOptimized = struct {
    allocator: std.mem.Allocator,
    options: NormalizeOptions,

    // post-walk cleanup - no manual string cleanup needed!
    nodes_to_remove: std.ArrayList(*z.DomNode),
    text_merges_optimized: std.ArrayList(TextMergeOptimized),
    template_nodes: std.ArrayList(*z.DomNode),

    fn init(alloc: std.mem.Allocator, opts: NormalizeOptions) @This() {
        return .{
            .allocator = alloc,
            .options = opts,
            .nodes_to_remove = .empty,
            .text_merges_optimized = .empty,
            .template_nodes = .empty,
        };
    }

    fn deinit(self: *@This()) void {
        // No string cleanup needed - we're using zero-copy slices!
        self.text_merges_optimized.deinit(self.allocator);
        self.nodes_to_remove.deinit(self.allocator);
        self.template_nodes.deinit(self.allocator);
    }

    /// _Walk-up_ the tree to check if the node is inside a whitespace preserved element.
    fn shouldPreserveWhitespace(self: @This(), node: *z.DomNode) bool {
        _ = self;
        var current = z.parentNode(node);
        while (current) |parent| {
            if (z.nodeToElement(parent)) |element| {
                const tag = z.tagFromQualifiedName(z.qualifiedName_zc(element)) orelse return false;
                if (z.WhitespacePreserveTagSet.contains(tag)) {
                    return true;
                }
            }
            current = z.parentNode(parent);
        }
        return false;
    }
};

/// [normalize] Normalize the DOM with options `NormalizeOptions`.
///
/// - To remove comments, `skip_comments=true`.
/// - Default to preserve whitespace in specific elements (`pre`, `textarea`, `script`, `style`). Use `preserve_special_elements=false` to disable this behavior.
/// - Default to trim whitespace from merged text nodes.
/// - Default to remove empty text nodes.
pub fn normalizeWithOptions(
    allocator: std.mem.Allocator,
    root_elt: *z.HTMLElement,
    options: NormalizeOptions,
) (std.mem.Allocator.Error || z.Err)!void {
    var context = Context.init(allocator, options);
    defer context.deinit();

    lxb_dom_node_simple_walk(
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

/// Callback function in `lexbor` format that runs on each node during the "simple_walk". Uses a "context" argument to access "external" data
///
/// Switch on the node type and collects for post-processing by populating the "context"
///
/// It is a two-step process (you can't modify the DOM during the walk):
/// - traverse the DOM with "simple_walk" and collect nodes for post-processing
/// - post-process the collected nodes
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
            if (context_ptr.shouldPreserveWhitespace(node)) {
                return z._CONTINUE;
            }

            if (context_ptr.options.trim_text or context_ptr.options.remove_whitespace_text_nodes) {
                const text_content = z.textContent_zc(node);
                const trimmed = std.mem.trim(
                    u8,
                    text_content,
                    &std.ascii.whitespace,
                );

                if (context_ptr.options.remove_whitespace_text_nodes) {
                    if (trimmed.len == 0) {
                        // collect for post-processing
                        context_ptr.nodes_to_remove.append(context_ptr.allocator, node) catch {
                            return z._STOP;
                        };
                    }
                }

                if (std.mem.eql(u8, text_content, trimmed)) return z._CONTINUE;

                if (context_ptr.options.trim_text and trimmed.len > 0) {
                    const trimmed_copy = context_ptr.allocator.dupe(u8, trimmed) catch {
                        return z._STOP;
                    };
                    // collect for post-processing
                    context_ptr.text_merges.append(
                        context_ptr.allocator,
                        .{
                            .target_node = node,
                            .new_content = trimmed_copy,
                        },
                    ) catch {
                        return z._STOP;
                    };
                }
            }
        },

        else => {},
    }

    return z._CONTINUE;
}

// Optimized collector - uses slice references instead of dupe()
fn collectorCallBackOptimized(node: *z.DomNode, ctx: ?*anyopaque) callconv(.c) c_int {
    const context_ptr: *ContextOptimized = castContext(ContextOptimized, ctx);

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
            if (context_ptr.shouldPreserveWhitespace(node)) {
                return z._CONTINUE;
            }

            if (context_ptr.options.trim_text or context_ptr.options.remove_whitespace_text_nodes) {
                const original_content = z.textContent_zc(node);

                // Calculate trim indices without creating new strings
                const trim_start = std.mem.indexOfNone(u8, original_content, " \t\n\r") orelse original_content.len;
                const trim_end_from_start = std.mem.lastIndexOfNone(u8, original_content, " \t\n\r") orelse {
                    // Entire string is whitespace
                    if (context_ptr.options.remove_whitespace_text_nodes) {
                        context_ptr.nodes_to_remove.append(context_ptr.allocator, node) catch {
                            return z._STOP;
                        };
                    }
                    return z._CONTINUE;
                };
                const trim_end = original_content.len - trim_end_from_start - 1;

                // Check if content would be empty after trimming
                if (trim_start >= original_content.len - trim_end) {
                    if (context_ptr.options.remove_whitespace_text_nodes) {
                        context_ptr.nodes_to_remove.append(context_ptr.allocator, node) catch {
                            return z._STOP;
                        };
                    }
                    return z._CONTINUE;
                }

                // Only collect if trimming is needed
                if (trim_start > 0 or trim_end > 0) {
                    if (context_ptr.options.trim_text) {
                        const merge = TextMergeOptimized{
                            .target_node = node,
                            .original_content = original_content,
                            .trim_start = trim_start,
                            .trim_end = trim_end,
                        };

                        context_ptr.text_merges_optimized.append(context_ptr.allocator, merge) catch {
                            return z._STOP;
                        };
                    }
                }
            }
        },

        else => {},
    }

    return z._CONTINUE;
}

// Optimized operations - apply trim operations using slice indices
fn PostWalkOperationsOptimized(
    allocator: std.mem.Allocator,
    context: *ContextOptimized,
    options: NormalizeOptions,
) (std.mem.Allocator.Error || z.Err)!void {
    // trim text nodes using zero-copy slices
    for (context.text_merges_optimized.items) |merge| {
        const content = merge.original_content;
        const trimmed_len = content.len - merge.trim_start - merge.trim_end;

        if (trimmed_len > 0) {
            const trimmed = content[merge.trim_start .. content.len - merge.trim_end];
            try z.replaceText(
                allocator,
                merge.target_node,
                trimmed,
                .{},
            );
        } else {
            // Empty after trimming - replace with empty string
            try z.replaceText(
                allocator,
                merge.target_node,
                "",
                .{},
            );
        }
    }

    // Remove empty text nodes and comments if selected
    for (context.nodes_to_remove.items) |node| {
        z.removeNode(node);
        z.destroyNode(node);
    }

    // Process template content with its own "simple_walk" on the document fragment content
    for (context.template_nodes.items) |template_node| {
        try normalizeTemplateContentOptimized(
            allocator,
            template_node,
            options,
        );
    }
}

// Optimized version for template normalization
pub fn normalizeWithOptionsOptimized(
    allocator: std.mem.Allocator,
    root_elt: *z.HTMLElement,
    options: NormalizeOptions,
) (std.mem.Allocator.Error || z.Err)!void {
    var context = ContextOptimized.init(allocator, options);
    defer context.deinit();

    lxb_dom_node_simple_walk(
        z.elementToNode(root_elt),
        collectorCallBackOptimized,
        &context,
    );

    try PostWalkOperationsOptimized(
        allocator,
        &context,
        options,
    );
}

/// simple_walk in the template _content_ (#document-fragment) - optimized version
fn normalizeTemplateContentOptimized(
    allocator: std.mem.Allocator,
    template_node: *z.DomNode,
    options: NormalizeOptions,
) (std.mem.Allocator.Error || z.Err)!void {
    const template = z.nodeToTemplate(template_node) orelse return;

    const content = z.templateContent(template);
    const content_node = z.fragmentNode(content);

    var template_context = ContextOptimized.init(allocator, options);
    defer template_context.deinit();

    lxb_dom_node_simple_walk(
        content_node,
        collectorCallBackOptimized,
        &template_context,
    );

    try PostWalkOperationsOptimized(
        allocator,
        &template_context,
        options,
    );
}

fn PostWalkOperations(
    allocator: std.mem.Allocator,
    context: *Context,
    options: NormalizeOptions,
) (std.mem.Allocator.Error || z.Err)!void {
    // trim text nodes
    for (context.text_merges.items) |merge| {
        try z.replaceText(
            allocator,
            merge.target_node,
            merge.new_content,
            .{},
        );
    }

    // Remove empty text nodes and comments if selected
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
    const content_node = z.fragmentNode(content);

    var template_context = Context.init(allocator, options);
    defer template_context.deinit();

    lxb_dom_node_simple_walk(
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

        try normalizeWithOptions(
            allocator,
            body_elt,
            NormalizeOptions{
                .trim_text = true,
                .remove_whitespace_text_nodes = true,
                .skip_comments = true,
            },
        );

        const result = try z.outerHTML(
            allocator,
            body_elt,
        );
        defer allocator.free(result);

        const expected = "<body><div>Some   more\n  text<span></span><pre>  Preserve   spaces  </pre>More   text\n  to<em>come</em><i>maybe</i></div></body>";
        try testing.expectEqualStrings(expected, result);
    }
    {
        const allocator = testing.allocator;
        const html = "<div>\n  Some   more\n  text\n  <span> \t </span>\n<!-- a comment to be removed -->\n  <pre>  Preserve   spaces  </pre>\n  More   text\n  to <em> come </em>\n</div>\n";

        const doc = try z.createDocFromString(html);
        defer z.destroyDocument(doc);

        const body_elt = z.bodyElement(doc).?;

        try normalizeWithOptions(
            allocator,
            body_elt,
            NormalizeOptions{
                .trim_text = true,
                .remove_whitespace_text_nodes = true,
                .skip_comments = false,
            },
        );

        const result = try z.outerHTML(
            allocator,
            body_elt,
        );
        defer allocator.free(result);

        const expected = "<body><div>Some   more\n  text<span></span><!-- a comment to be removed --><pre>  Preserve   spaces  </pre>More   text\n  to<em>come</em></div></body>";
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
        const template_content_node_before = z.fragmentNode(template_content_before);
        const child_nodes_before = try z.childNodes(allocator, template_content_node_before);
        defer allocator.free(child_nodes_before);
        try testing.expect(child_nodes_before.len == 8);

        try z.normalizeWithOptions(
            allocator,
            z.nodeToElement(root).?,
            .{
                .trim_text = true,
                .remove_whitespace_text_nodes = true,
                .skip_comments = true,
            },
        );

        const serialized = try z.outerHTML(allocator, z.nodeToElement(root).?);
        defer allocator.free(serialized);

        const expected = "<html><head></head><body><div><p>Before template</p><template id=\"test\"><span>Template content</span><em></em><strong>Bold text</strong></template><p>After template</p></div></body></html>";

        try testing.expectEqualStrings(expected, serialized);

        const template_elt_after = z.getElementByTag(root, .template).?;

        // inspect the template content after: the number of nodes went down
        const template_after = z.elementToTemplate(template_elt_after).?;
        const template_content_after = z.templateContent(template_after);
        const template_content_node_after = z.fragmentNode(template_content_after);
        const child_nodes_after = try z.childNodes(allocator, template_content_node_after);
        defer allocator.free(child_nodes_after);
        try testing.expect(child_nodes_after.len == 3);
    }
}

test "escape" {
    const allocator = testing.allocator;

    const html = "<script> console.log(\"hello\"); </script><div>Some <b>bold</b> text</div>";
    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    const root = z.documentRoot(doc).?;

    try z.normalizeWithOptions(
        allocator,
        z.nodeToElement(root).?,
        .{
            .trim_text = true,
            .remove_whitespace_text_nodes = true,
            .skip_comments = true,
        },
    );

    const serialized = try z.outerHTML(allocator, z.nodeToElement(root).?);
    defer allocator.free(serialized);

    // print("{s}\n", .{serialized});
    // const expected = "<html><head></head><body><div>Some <b>bold</b> text</div></body></html>";

    // try testing.expectEqualStrings(expected, serialized);
}

test "normalize performance benchmark" {
    const allocator = testing.allocator;

    // Create large HTML document with lots of whitespace for normalization
    var html_builder: std.ArrayList(u8) = .empty;
    defer html_builder.deinit(allocator);

    try html_builder.appendSlice(allocator,
        \\<html>
        \\<body>
        \\  <div class="container">
        \\    <header>
        \\      <h1>   Performance Test Document   </h1>
        \\      <nav>
        \\        <ul>
    );

    // Add many elements with whitespace
    for (0..100) |i| {
        try html_builder.appendSlice(allocator,
            \\          <li>   
            \\            <a href="/page
        );

        const num_str = try std.fmt.allocPrint(allocator, "{d}", .{i});
        defer allocator.free(num_str);
        try html_builder.appendSlice(allocator, num_str);

        try html_builder.appendSlice(allocator,
            \\">   Link 
        );
        try html_builder.appendSlice(allocator, num_str);
        try html_builder.appendSlice(allocator,
            \\   </a>
            \\            <span>   Some text with    whitespace   </span>
            \\            <!-- comment with whitespace -->
            \\            <em>     emphasized text     </em>
            \\          </li>
        );
    }

    try html_builder.appendSlice(allocator,
        \\        </ul>
        \\      </nav>
        \\    </header>
        \\    <main>
        \\      <section>
        \\        <p>   This is a paragraph with    lots of    whitespace   </p>
        \\        <div>
        \\          <pre>   Preserve   this   whitespace   </pre>
        \\          <textarea>   Also preserve   this   </textarea>
        \\        </div>
        \\      </section>
        \\    </main>
        \\  </div>
        \\</body>
        \\</html>
    );

    const large_html = try html_builder.toOwnedSlice(allocator);
    defer allocator.free(large_html);

    const iterations = 50;
    print("\n=== NORMALIZE PERFORMANCE BENCHMARK ===\n", .{});
    print("HTML size: {d} bytes (~{d:.1}KB)\n", .{ large_html.len, @as(f64, @floatFromInt(large_html.len)) / 1024.0 });
    print("Iterations: {d}\n", .{iterations});

    var timer = try std.time.Timer.start();

    // Test current approach with buffer collections
    timer.reset();
    for (0..iterations) |_| {
        const doc = try z.createDocFromString(large_html);
        defer z.destroyDocument(doc);

        const body_elt = z.bodyElement(doc).?;
        try normalizeWithOptions(
            allocator,
            body_elt,
            .{
                .trim_text = true,
                .remove_whitespace_text_nodes = true,
                .skip_comments = true,
            },
        );
    }
    const current_time = timer.read();

    // Test optimized approach with zero-copy slices
    timer.reset();
    for (0..iterations) |_| {
        const doc = try z.createDocFromString(large_html);
        defer z.destroyDocument(doc);

        const body_elt = z.bodyElement(doc).?;
        try normalizeWithOptionsOptimized(
            allocator,
            body_elt,
            .{
                .trim_text = true,
                .remove_whitespace_text_nodes = true,
                .skip_comments = true,
            },
        );
    }
    const optimized_time = timer.read();

    const ns_to_ms = @as(f64, @floatFromInt(std.time.ns_per_ms));
    const current_ms = @as(f64, @floatFromInt(current_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations));
    const optimized_ms = @as(f64, @floatFromInt(optimized_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations));

    print("\n--- Results ---\n", .{});
    print("Current approach (dupe): {d:.3} ms/op\n", .{current_ms});
    print("Optimized approach (zero-copy): {d:.3} ms/op\n", .{optimized_ms});

    if (optimized_ms < current_ms) {
        const improvement = current_ms / optimized_ms;
        print("🚀 Optimized is {d:.2}x faster!\n", .{improvement});
    } else if (current_ms < optimized_ms) {
        const slower = optimized_ms / current_ms;
        print("⚠️  Optimized is {d:.2}x slower\n", .{slower});
    } else {
        print("📊 Performance is equivalent\n", .{});
    }

    // BEAM Scheduler compliance check
    print("\n--- BEAM Scheduler Compliance ---\n", .{});
    print("Current: {s} (limit: 1ms)\n", .{if (current_ms < 1.0) "✅ SAFE" else "❌ DIRTY SCHEDULER"});
    print("Optimized: {s} (limit: 1ms)\n", .{if (optimized_ms < 1.0) "✅ SAFE" else "❌ DIRTY SCHEDULER"});

    print("\n✅ Normalize benchmark completed!\n", .{});
}

test "DOMPurify" {
    _ = "";
}
