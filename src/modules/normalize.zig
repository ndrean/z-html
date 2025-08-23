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
fn castContext(comptime T: type, ctx: ?*anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(ctx.?)));
}

fn removeOuterWhitespaceTextNodes(allocator: std.mem.Allocator, root_elt: *z.HTMLElement) !void {
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
                z.setOrReplaceText(ctx_ptr.allocator, node, trimmed, .{}) catch {
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

pub const NormalizeOptions = struct {
    /// Remove whitespace-only text nodes
    remove_whitespace_nodes: bool = false,
    /// Trim whitespace from merged text nodes
    trim_text: bool = false,
    /// Remove comment nodes
    remove_comments: bool = false,
    /// Remove processing instructions
    remove_processing_instructions: bool = false,
    /// Preserve whitespace in these elements
    preserve_whitespace_elements: []const []const u8 = &.{ "pre", "code", "textarea", "script", "style" },
};

/// Standard browser Node.normalize() - merges adjacent text nodes only
pub fn normalize(
    allocator: std.mem.Allocator,
    root_elt: *z.HTMLElement,
) !void {
    return normalizeWithOptions(
        allocator,
        root_elt,
        .{},
    );
}

// pub fn normalizeWithOptions(allocator: std.mem.Allocator, root_elt: *z.HTMLElement, options: NormalizeOptions) !void {
//     const Context = struct {
//         allocator: std.mem.Allocator,
//         options: NormalizeOptions,
//         current_text: ?*z.DomNode = null,
//         text_content: std.ArrayList(u8),
//         nodes_to_remove: std.ArrayList(*z.DomNode),
//         in_preserve_context: bool = false,

//         pub fn init(alloc: std.mem.Allocator, opts: NormalizeOptions) @This() {
//             return .{
//                 .allocator = alloc,
//                 .options = opts,
//                 .nodes_to_remove = std.ArrayList(*z.DomNode).init(alloc),
//                 .text_content = std.ArrayList(u8).init(alloc),
//             };
//         }

//         pub fn deinit(self: *@This()) void {
//             self.text_content.deinit();
//             self.nodes_to_remove.deinit();
//         }

//         pub fn shouldPreserveWhitespace(self: @This(), node: *z.DomNode) bool {
//             _ = self;
//             // Walk up the tree to see if we're inside a preserve-whitespace element
//             var current = z.parentNode(node);
//             while (current) |parent| {
//                 if (z.nodeToElement(parent)) |element| {
//                     const tag = z.parseTag(z.qualifiedName_zc(element)) orelse return false;
//                     if (z.WhitespacePreserveTagSet.contains(tag)) {
//                         return true;
//                     }
//                 }
//                 current = z.parentNode(parent) orelse return false;
//             }
//             return false;
//         }
//     };

//     var context = Context.init(allocator, options);
//     defer context.deinit();

//     // // first pass: collect adjacent text nodes and nodes to remove
//     // var current_text_sequence: ?struct {
//     //     first_node: *z.DomNode,
//     //     content: std.ArrayList(u8),
//     //     nodes_to_remove: std.ArrayList(*z.DomNode),
//     // } = null;

//     const callback = struct {
//         fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
//             const context_ptr: *Context = @ptrCast(@alignCast(ctx.?));
//             const opts = context_ptr.options;

//             switch (z.nodeType(node)) {
//                 .text => {
//                     const text_content = z.textContent_zc(node);
//                     const should_preserve = context_ptr.shouldPreserveWhitespace(node);

//                     // Check if node should be removed
//                     if (opts.remove_whitespace_nodes and !should_preserve) {
//                         const trimmed = std.mem.trim(u8, text_content, &std.ascii.whitespace);
//                         if (trimmed.len == 0) {
//                             context_ptr.nodes_to_remove.append(node) catch unreachable;
//                             return z.Action.CONTINUE.toU32();
//                         }
//                     }

//                     // Handle text merging
//                     if (context_ptr.current_text == null) {
//                         // First text node in sequence
//                         context_ptr.current_text = node;
//                         context_ptr.text_content.clearRetainingCapacity();

//                         if (opts.trim_text and !should_preserve) {
//                             const trimmed = std.mem.trimLeft(u8, text_content, &std.ascii.whitespace);
//                             context_ptr.text_content.appendSlice(trimmed) catch unreachable;
//                         } else {
//                             context_ptr.text_content.appendSlice(text_content) catch unreachable;
//                         }
//                     } else {
//                         // Adjacent text node - merge
//                         if (opts.trim_text and !should_preserve) {
//                             // Smart merge with single space
//                             const prev_ends_with_space = context_ptr.text_content.items.len > 0 and
//                                 std.ascii.isWhitespace(context_ptr.text_content.items[context_ptr.text_content.items.len - 1]);

//                             const trimmed = std.mem.trim(u8, text_content, &std.ascii.whitespace);

//                             if (!prev_ends_with_space and trimmed.len > 0) {
//                                 context_ptr.text_content.append(' ') catch unreachable;
//                             }
//                             context_ptr.text_content.appendSlice(trimmed) catch unreachable;
//                         } else {
//                             // Standard merge - preserve all content
//                             context_ptr.text_content.appendSlice(text_content) catch unreachable;
//                         }

//                         z.removeNode(node);
//                         z.destroyNode(node);
//                     }
//                 },

//                 .comment => {
//                     if (opts.remove_comments) {
//                         context_ptr.nodes_to_remove.append(node) catch unreachable;
//                     }
//                 },

//                 else => {
//                     // Finalize any pending text merge
//                     if (context_ptr.current_text) |text_node| {
//                         const merged = context_ptr.text_content.toOwnedSlice() catch unreachable;
//                         defer context_ptr.allocator.free(merged);

//                         const final_content = if (opts.trim_text and !context_ptr.shouldPreserveWhitespace(text_node))
//                             std.mem.trimRight(u8, merged, &std.ascii.whitespace)
//                         else
//                             merged;

//                         z.setTextContent(text_node, final_content) catch unreachable;
//                         context_ptr.current_text = null;
//                     }
//                 },
//             }

//             return z.Action.CONTINUE.toU32();
//         }
//     }.cb;

//     lxb_dom_node_simple_walk(
//         z.elementToNode(root_elt),
//         callback,
//         &context,
//     );

//     for (context.nodes_to_remove.items) |node| {
//         z.removeNode(node);
//         z.destroyNode(node);
//     }

//     for (context.text_merges.items) |merge| {
//         z.setTextContent(merge.target_node, merge.new_content) catch {};
//     }
// }

pub fn normalizeWithOptions(
    allocator: std.mem.Allocator,
    root_elt: *z.HTMLElement,
    options: NormalizeOptions,
) !void {
    if (options.remove_comments or options.remove_whitespace_nodes) {
        try removeUnwantedNodes(
            allocator,
            root_elt,
            options,
        );
    }

    try mergeAdjacentTextNodes(
        allocator,
        root_elt,
        options,
    );
}

fn removeUnwantedNodes(allocator: std.mem.Allocator, root_elt: *z.HTMLElement, options: NormalizeOptions) !void {
    const CollectCtx = struct {
        allocator: std.mem.Allocator,
        options: NormalizeOptions,
        nodes_to_remove: std.ArrayList(*z.DomNode),
    };

    var collect_ctx = CollectCtx{
        .allocator = allocator,
        .options = options,
        .nodes_to_remove = std.ArrayList(*z.DomNode).init(allocator),
    };
    defer collect_ctx.nodes_to_remove.deinit();

    const callback = struct {
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
            const ctx_ptr = castContext(CollectCtx, ctx);
            const opts = ctx_ptr.options;

            switch (z.nodeType(node)) {
                .text => {
                    if (opts.remove_whitespace_nodes) {
                        const text_content = z.textContent_zc(node);
                        const trimmed = std.mem.trim(
                            u8,
                            text_content,
                            &std.ascii.whitespace,
                        );
                        if (trimmed.len == 0) {
                            ctx_ptr.nodes_to_remove.append(node) catch unreachable;
                        }
                    }
                },
                .comment => {
                    if (opts.remove_comments) {
                        ctx_ptr.nodes_to_remove.append(node) catch unreachable;
                    }
                },
                else => {},
            }

            return z.Action.CONTINUE.toU32();
        }
    }.cb;

    lxb_dom_node_simple_walk(
        z.elementToNode(root_elt),
        callback,
        &collect_ctx,
    );

    for (collect_ctx.nodes_to_remove.items) |node| {
        z.removeNode(node);
        z.destroyNode(node);
    }
}

fn mergeAdjacentTextNodes(allocator: std.mem.Allocator, root_elt: *z.HTMLElement, options: NormalizeOptions) !void {
    // We need to process each element's children separately
    // since adjacent text nodes are siblings within the same parent

    const Context = struct {
        allocator: std.mem.Allocator,
        options: NormalizeOptions,
        text_merges: std.ArrayList(TextMergeOperation),

        const TextMergeOperation = struct {
            target_node: *z.DomNode,
            new_content: []u8,
            nodes_to_remove: std.ArrayList(*z.DomNode),

            fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
                alloc.free(self.new_content);
                self.nodes_to_remove.deinit();
            }
        };

        fn init(alloc: std.mem.Allocator, opts: NormalizeOptions) @This() {
            return .{
                .allocator = alloc,
                .options = opts,
                .text_merges = std.ArrayList(TextMergeOperation).init(alloc),
            };
        }

        fn deinit(self: *@This()) void {
            for (self.text_merges.items) |*merge| {
                merge.deinit(self.allocator);
            }
            self.text_merges.deinit();
        }

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

    var context = Context.init(allocator, options);
    defer context.deinit();

    // Callback to find elements and process their children
    const callback = struct {
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
            const context_ptr: *Context = @ptrCast(@alignCast(ctx.?));

            // Only process element nodes (which can have text node children)
            if (z.nodeType(node) == .element) {
                processElementChildren(context_ptr, node) catch unreachable;
            }

            return z.Action.CONTINUE.toU32();
        }

        fn processElementChildren(context_ptr: *Context, parent_element: *z.DomNode) !void {
            const children = try z.childNodes(
                context_ptr.allocator,
                parent_element,
            );
            defer context_ptr.allocator.free(children);

            var i: usize = 0;
            while (i < children.len) {
                const child = children[i];

                if (z.nodeType(child) == .text) {
                    // Found a text node - look for adjacent text nodes
                    const text_sequence_start = i;
                    var j = i + 1;

                    // Find end of adjacent text node sequence
                    while (j < children.len and z.nodeType(children[j]) == .text) {
                        j += 1;
                    }

                    // If we have more than one text node, merge them
                    if (j > i + 1) {
                        try mergeTextSequence(context_ptr, children[text_sequence_start..j]);
                    }

                    // Skip past the text sequence we just processed
                    i = j;
                } else {
                    i += 1;
                }
            }
        }

        fn mergeTextSequence(context_ptr: *Context, text_nodes: []*z.DomNode) !void {
            if (text_nodes.len <= 1) return;

            const first_node = text_nodes[0];
            const should_preserve = context_ptr.shouldPreserveWhitespace(first_node);

            var merged_content = std.ArrayList(u8).init(context_ptr.allocator);
            var nodes_to_remove = std.ArrayList(*z.DomNode).init(context_ptr.allocator);

            // Process first text node
            const first_text = z.textContent_zc(first_node);
            if (context_ptr.options.trim_text and !should_preserve) {
                const trimmed = std.mem.trimLeft(u8, first_text, &std.ascii.whitespace);
                try merged_content.appendSlice(trimmed);
            } else {
                try merged_content.appendSlice(first_text);
            }

            // Process remaining text nodes
            for (text_nodes[1..]) |text_node| {
                const text_content = z.textContent_zc(text_node);

                if (context_ptr.options.trim_text and !should_preserve) {
                    // Smart merge with single space
                    const prev_ends_with_space = merged_content.items.len > 0 and
                        std.ascii.isWhitespace(merged_content.items[merged_content.items.len - 1]);

                    const trimmed = std.mem.trim(u8, text_content, &std.ascii.whitespace);

                    if (!prev_ends_with_space and trimmed.len > 0) {
                        try merged_content.append(' ');
                    }
                    try merged_content.appendSlice(trimmed);
                } else {
                    // Standard merge - preserve all content
                    try merged_content.appendSlice(text_content);
                }

                // Mark this node for removal
                try nodes_to_remove.append(text_node);
            }

            // Apply final trimming if needed
            const final_content = if (context_ptr.options.trim_text and !should_preserve) blk: {
                const trimmed_slice = std.mem.trimRight(
                    u8,
                    merged_content.items,
                    &std.ascii.whitespace,
                );
                const owned = try context_ptr.allocator.dupe(u8, trimmed_slice);
                break :blk owned;
            } else blk: {
                break :blk try merged_content.toOwnedSlice();
            };

            // Store the merge operation
            try context_ptr.text_merges.append(.{
                .target_node = first_node,
                .new_content = final_content,
                .nodes_to_remove = nodes_to_remove,
            });
        }
    }.cb;

    lxb_dom_node_simple_walk(
        z.elementToNode(root_elt),
        callback,
        &context,
    );

    for (context.text_merges.items) |merge| {
        try z.setOrReplaceText(
            allocator,
            merge.target_node,
            merge.new_content,
            .{},
        );
        // try z.setTextContent(merge.target_node, merge.new_content);

        for (merge.nodes_to_remove.items) |node_to_remove| {
            z.removeNode(node_to_remove);
            z.destroyNode(node_to_remove);
        }
    }
}

test "normalize with context preservation" {
    const allocator = testing.allocator;
    const html =
        \\<div>
        \\  Some   text
        \\  <pre>  Preserve   spaces  </pre>
        \\  More   text
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body_elt = try z.bodyElement(doc);

    try normalizeWithOptions(
        allocator,
        body_elt,
        .{
            .trim_text = true,
            .remove_whitespace_nodes = true,
        },
    );

    const result = try z.serializeElement(
        allocator,
        body_elt,
    );
    defer allocator.free(result);
    print("{s}\n", .{result});

    // Should be: <div>Some text<pre>  Preserve   spaces  </pre>More text</div>
    // Note: spaces preserved inside <pre>
}
