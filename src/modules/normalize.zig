//! Node.normalize utilities for DOM and HTML elements

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;

// Fast DOM traversal for optimized ID search
extern "c" fn lxb_dom_node_simple_walk(
    root: *z.DomNode,
    walker_cb: *const fn (*z.DomNode, ?*anyopaque) callconv(.C) u32,
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
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
            const ctx_ptr: *NormCtx = castContext(NormCtx, ctx);
            if (z.isTypeText(node)) {
                const text_content = z.textContent_zc(node);
                const trimmed = std.mem.trim(
                    u8,
                    text_content,
                    &std.ascii.whitespace,
                );
                z.replaceText(ctx_ptr.allocator, node, trimmed, .{}) catch {
                    return z.Action.CONTINUE.toU32();
                };
            }

            return z.Action.CONTINUE.toU32();
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
    const doc = try z.parseFromString("<p> Hello   <strong> World    </strong> \nand  <em> \twelcome   \nback</em></p>");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);
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
pub fn normalize(
    allocator: std.mem.Allocator,
    root_elt: *z.HTMLElement,
) (std.mem.Allocator.Error || z.Err)!void {
    return normalizeWithOptions(
        allocator,
        root_elt,
        .{},
    );
}

pub const NormalizeOptions = struct {
    remove_comments: bool = false,
    remove_whitespace_text_nodes: bool = true,
    /// Trim whitespace from merged text nodes
    trim_text: bool = true,
    preserve_special_elements: bool = true,
};

const TextMerge = struct {
    target_node: *z.DomNode,
    new_content: []u8,
};

// Context for the callback normalization walk
const Context = struct {
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
            .nodes_to_remove = std.ArrayList(*z.DomNode).init(alloc),
            .text_merges = std.ArrayList(TextMerge).init(alloc),
            .template_nodes = std.ArrayList(*z.DomNode).init(alloc),
        };
    }

    fn deinit(self: *@This()) void {
        for (self.text_merges.items) |merge| {
            self.allocator.free(merge.new_content);
        }
        self.text_merges.deinit();
        self.nodes_to_remove.deinit();
        self.template_nodes.deinit();
    }

    /// _Walk-up_ the tree to check if the node is inside a whitespace preserved element.
    fn shouldPreserveWhitespace(self: @This(), node: *z.DomNode) bool {
        _ = self;
        var current = z.parentNode(node);
        while (current) |parent| {
            if (z.nodeToElement(parent)) |element| {
                const tag = z.parseTag(z.qualifiedName_zc(element)) orelse return false;
                if (z.WhitespacePreserveTagSet.contains(tag)) {
                    return true;
                }
            }
            current = z.parentNode(parent);
        }
        return false;
    }
};

/// Callback function that runs on each node during the "simple_walk". Uses a "context" argument to access "external" data
///
/// Switch on the node type and handle accordingly for post-processing by populating the "context"
///
/// It is a two-step process (you can't modify the DOM during the walk):
/// - traverse the DOM with "simple_walk" and collect nodes for post-processing
/// - post-process the collected nodes
fn collectorCallBack(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
    const context_ptr: *Context = @ptrCast(@alignCast(ctx.?));

    switch (z.nodeType(node)) {
        .comment => {
            if (context_ptr.options.remove_comments) {
                // collect comments for post-processing
                context_ptr.nodes_to_remove.append(node) catch {
                    return z.Action.STOP.toU32();
                };
            }
        },
        .element => {
            if (z.isTemplate(node)) {
                // Collect template nodes for post-processing
                context_ptr.template_nodes.append(node) catch {
                    return z.Action.STOP.toU32();
                };
                return z.Action.CONTINUE.toU32();
            }
        },
        .text => {
            if (context_ptr.shouldPreserveWhitespace(node)) {
                return z.Action.CONTINUE.toU32();
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
                        context_ptr.nodes_to_remove.append(node) catch {
                            return z.Action.STOP.toU32();
                        };
                    }
                }

                if (std.mem.eql(u8, text_content, trimmed)) return z.Action.CONTINUE.toU32();

                if (context_ptr.options.trim_text and trimmed.len > 0) {
                    const trimmed_copy = context_ptr.allocator.dupe(u8, trimmed) catch {
                        return z.Action.STOP.toU32();
                    };
                    // collect for post-processing
                    context_ptr.text_merges.append(.{
                        .target_node = node,
                        .new_content = trimmed_copy,
                    }) catch {
                        return z.Action.STOP.toU32();
                    };
                }
            }
        },

        else => {},
    }

    return z.Action.CONTINUE.toU32();
}

/// [normalize] Normalize the DOM with options `NormalizeOptions`.
///
/// - To remove comments, `remove_comments=true`.
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
    const content_node = z.fragmentToNode(content);

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

        const doc = try z.parseFromString(html);
        defer z.destroyDocument(doc);

        const body_elt = try z.bodyElement(doc);

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
                .remove_comments = true,
            },
        );

        const result = try z.serializeElement(
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

        const doc = try z.parseFromString(html);
        defer z.destroyDocument(doc);

        const body_elt = try z.bodyElement(doc);

        try normalizeWithOptions(
            allocator,
            body_elt,
            NormalizeOptions{
                .trim_text = true,
                .remove_whitespace_text_nodes = true,
                .remove_comments = false,
            },
        );

        const result = try z.serializeElement(
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

        const doc = try z.parseFromString(html);
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

        try z.normalizeWithOptions(
            allocator,
            z.nodeToElement(root).?,
            .{
                .trim_text = true,
                .remove_whitespace_text_nodes = true,
                .remove_comments = true,
            },
        );

        const serialized = try z.serializeToString(allocator, root);
        defer allocator.free(serialized);

        const expected = "<html><head></head><body><div><p>Before template</p><template id=\"test\"><span>Template content</span><em></em><strong>Bold text</strong></template><p>After template</p></div></body></html>";

        try testing.expectEqualStrings(expected, serialized);

        const template_elt_after = z.getElementByTag(root, .template).?;

        // inspect the template content after: the number of nodes went down
        const template_after = z.elementToTemplate(template_elt_after).?;
        const template_content_after = z.templateContent(template_after);
        const template_content_node_after = z.fragmentToNode(template_content_after);
        const child_nodes_after = try z.childNodes(allocator, template_content_node_after);
        defer allocator.free(child_nodes_after);
        try testing.expect(child_nodes_after.len == 3);
    }
}

test "escape" {
    const allocator = testing.allocator;

    const html = "<script> console.log(\"hello\"); </script><div>Some <b>bold</b> text</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const root = z.documentRoot(doc).?;

    try z.normalizeWithOptions(
        allocator,
        z.nodeToElement(root).?,
        .{
            .trim_text = true,
            .remove_whitespace_text_nodes = true,
            .remove_comments = true,
        },
    );

    const serialized = try z.serializeToString(allocator, root);
    defer allocator.free(serialized);

    print("{s}\n", .{serialized});
    // const expected = "<html><head></head><body><div>Some <b>bold</b> text</div></body></html>";

    // try testing.expectEqualStrings(expected, serialized);
}
