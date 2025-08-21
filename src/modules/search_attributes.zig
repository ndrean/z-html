//! DOM Search Utilities Using `simple_Walk` Walker Callbacks

//======================================================================
// DOM SEARCH USING WALKER CALLBACKS
//=======================================================================

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const print = std.debug.print;
const testing = std.testing;

// Fast DOM traversal for optimized ID search
extern "c" fn lxb_dom_node_simple_walk(root: *z.DomNode, walker_cb: *const fn (*z.DomNode, ?*anyopaque) callconv(.C) u32, ctx: ?*anyopaque) void;

/// convert from "aligned" `anyopaque` to the target pointer type `T`
/// because of the callback signature:
fn castContext(comptime T: type, ctx: ?*anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(ctx.?)));
}

/// [walker] action types
const Action = enum(u32) {
    /// Continue traversing the DOM tree
    CONTINUE = 0,
    /// Stop traversal immediately (single element searches)
    STOP = 1,

    // Convert to u32 for C callback compatibility
    pub fn toU32(self: Action) u32 {
        return @intFromEnum(self);
    }
};

test "walker action enum clarity" {
    try testing.expect(Action.CONTINUE.toU32() == 0);
    try testing.expect(Action.STOP.toU32() == 1);
}

// === single ===

/// [walker] getElementById traversal DOM search
///
///
/// Input IDs are "strings".
///
/// Returns the first element with matching ID, or null if not found.
pub fn getElementById(root_node: *z.DomNode, id: []const u8) ?*z.HTMLElement {
    const IdContext = struct {
        target_id: []const u8,
        found_element: ?*z.HTMLElement = null,
    };
    var context = IdContext{ .target_id = id };

    // callback expects a u32 return type
    const callback = struct {
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();
            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

            const search_ctx = castContext(IdContext, ctx);

            if (!z.hasAttribute(element, "id")) return Action.CONTINUE.toU32();
            const id_value = z.getElementId_zc(element);

            if (std.mem.eql(u8, id_value, search_ctx.target_id)) {
                search_ctx.found_element = element;
                return Action.STOP.toU32();
            }

            return Action.CONTINUE.toU32();
        }
    }.cb;

    lxb_dom_node_simple_walk(root_node, callback, &context);
    return context.found_element;
}

pub fn getElementByClass(root_node: *z.DomNode, class_name: []const u8) ?*z.HTMLElement {
    const ClassContext = struct {
        target_class: []const u8,
        found_element: ?*z.HTMLElement = null,
    };
    var context = ClassContext{ .target_class = class_name };

    // callback expects a u32 return type
    const callback = struct {
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();
            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

            const search_ctx = castContext(ClassContext, ctx);

            if (!z.hasAttribute(element, "class")) return Action.CONTINUE.toU32();

            if (z.hasClass(element, search_ctx.target_class)) {
                search_ctx.found_element = element;
                return Action.STOP.toU32();
            }

            return Action.CONTINUE.toU32();
        }
    }.cb;

    lxb_dom_node_simple_walk(root_node, callback, &context);
    return context.found_element;
}

pub fn getElementByTag(root_node: *z.DomNode, tag: z.HtmlTag) ?*z.HTMLElement {
    const TagContext = struct {
        target_tag: z.HtmlTag,
        found_element: ?*z.HTMLElement = null,
    };
    var context = TagContext{ .target_tag = tag };

    // callback expects a u32 return type
    const callback = struct {
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();
            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

            const search_ctx = castContext(TagContext, ctx);
            const element_tag = z.tagFromElement(element);

            if (element_tag == search_ctx.target_tag) {
                search_ctx.found_element = element;
                return Action.STOP.toU32();
            }

            return Action.CONTINUE.toU32();
        }
    }.cb;

    lxb_dom_node_simple_walk(root_node, callback, &context);
    return context.found_element;
}

pub fn getElementByAttribute(
    root_node: *z.DomNode,
    attr_name: []const u8,
    attr_value: ?[]const u8,
) ?*z.HTMLElement {
    const AttrContext = struct {
        attr_name: []const u8,
        attr_value: ?[]const u8,
        found_element: ?*z.HTMLElement = null,
    };
    var context = AttrContext{
        .attr_name = attr_name,
        .attr_value = attr_value,
    };

    const callback = struct {
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();
            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

            const search_ctx = castContext(AttrContext, ctx);

            if (!z.hasAttribute(element, search_ctx.attr_name)) return Action.CONTINUE.toU32();

            if (search_ctx.attr_value) |expected| {
                const actual = z.getAttribute_zc(element, search_ctx.attr_name) orelse return Action.CONTINUE.toU32();
                if (!std.mem.eql(u8, actual, expected)) return Action.CONTINUE.toU32();
            }

            search_ctx.found_element = element;
            return Action.STOP.toU32();
        }
    }.cb;

    lxb_dom_node_simple_walk(root_node, callback, &context);
    return context.found_element;
}

pub fn getElementByDataAttribute(
    root_node: *z.DomNode,
    prefix: []const u8,
    data_name: []const u8,
    value: ?[]const u8,
) !?*z.HTMLElement {
    var attr_name_buffer: [32]u8 = undefined;
    const attr_name = try std.fmt.bufPrint(
        attr_name_buffer[0..],
        "{s}-{s}",
        .{ prefix, data_name },
    );

    return getElementByAttribute(root_node, attr_name, value);
}

// === Multiple ===
const MultipleClassContext = struct {
    target_class: []const u8,
    results: std.ArrayList(*z.HTMLElement),

    pub fn init(alloc: std.mem.Allocator, class_name: []const u8) @This() {
        return .{
            .target_class = class_name,
            .results = std.ArrayList(*z.HTMLElement).init(alloc),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.results.deinit();
    }
};

pub fn getElementsByClass(root_node: *z.DomNode, class_name: []const u8, allocator: std.mem.Allocator) ![]const *z.HTMLElement {
    var context = MultipleClassContext.init(allocator, class_name);
    defer context.deinit();

    const callback = struct {
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();
            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

            const search_ctx = castContext(MultipleClassContext, ctx);

            if (!z.hasAttribute(element, "class")) return Action.CONTINUE.toU32();

            if (z.hasClass(element, search_ctx.target_class)) {
                search_ctx.results.append(element) catch {}; // Ignore allocation errors
            }

            return Action.CONTINUE.toU32();
        }
    }.cb;

    lxb_dom_node_simple_walk(root_node, callback, &context);
    return context.results.toOwnedSlice();
}

const MultipleTagContext = struct {
    target_tag: z.HtmlTag,
    results: std.ArrayList(*z.HTMLElement),

    pub fn init(alloc: std.mem.Allocator, tag: z.HtmlTag) @This() {
        return .{
            .target_tag = tag,
            .results = std.ArrayList(*z.HTMLElement).init(alloc),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.results.deinit();
    }
};

pub fn getElementsByTag(root_node: *z.DomNode, tag: z.HtmlTag, allocator: std.mem.Allocator) ![]const *z.HTMLElement {
    var context = MultipleTagContext.init(allocator, tag);
    defer context.deinit();

    const callback = struct {
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();
            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

            const search_ctx = castContext(MultipleTagContext, ctx);
            const element_tag = z.tagFromElement(element);

            if (element_tag == search_ctx.target_tag) {
                search_ctx.results.append(element) catch {}; // Ignore allocation errors
            }

            return Action.CONTINUE.toU32();
        }
    }.cb;

    lxb_dom_node_simple_walk(root_node, callback, &context);
    return context.results.toOwnedSlice();
}

//==================================================================
// ENHANCED RUNTIME WALKER FOR DOM PROCESSING
//==================================================================

/// [walker] Runtime walker to "process all elements" with a given ``processor` function from a given node.
///
/// The `processor` signature is `fn (*z.HTMLElement) void`.
pub fn processAllElements(root_node: *z.DomNode, processor: *const fn (*z.HTMLElement) void) void {
    const ProcessAllContext = struct {
        processor: *const fn (*z.HTMLElement) void,
    };

    var ctx = ProcessAllContext{ .processor = processor };

    const callback = struct {
        fn cb(node: *z.DomNode, context: ?*anyopaque) callconv(.C) u32 {
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();
            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

            const proc_ctx = castContext(ProcessAllContext, context);
            proc_ctx.processor(element);

            return Action.CONTINUE.toU32();
        }
    }.cb;

    lxb_dom_node_simple_walk(root_node, callback, &ctx);
}

/// Remove all attributes from all elements (useful for cleaning HTML)
pub fn removeAllAttributes(root_node: *z.DomNode) void {
    const processor = struct {
        fn clean(element: *z.HTMLElement) void {
            // Get all attribute names first, then remove them
            // This avoids iterator invalidation issues
            var attr_names = std.ArrayList([]const u8).init(std.heap.page_allocator);
            defer attr_names.deinit();

            var attr = z.getFirstAttribute(element);
            while (attr != null) {
                const name = z.getAttributeName_zc(attr.?);
                attr_names.append(name) catch {};
                attr = z.getNextAttribute(attr.?);
            }

            // Now remove all attributes by name
            for (attr_names.items) |name| {
                z.removeAttribute(element, name) catch {};
            }
        }
    }.clean;

    processAllElements(root_node, processor);
}

/// Remove specific attribute from all elements
pub fn removeAttributeFromAll(root_node: *z.DomNode, attr_name: []const u8) void {
    const RemoveAttrContext = struct {
        attr_name: []const u8,
    };

    var ctx = RemoveAttrContext{ .attr_name = attr_name };

    const callback = struct {
        fn cb(node: *z.DomNode, context: ?*anyopaque) callconv(.C) u32 {
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();
            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

            const remove_ctx = castContext(RemoveAttrContext, context);
            z.removeAttribute(element, remove_ctx.attr_name) catch {};

            return Action.CONTINUE.toU32();
        }
    }.cb;

    lxb_dom_node_simple_walk(root_node, callback, &ctx);
}

test "removeAttributeFromAll" {
    const allocator = testing.allocator;

    const html =
        \\<div id="main" class="container" data-test="value">
        \\  <span class="highlight" title="tooltip">Content</span>
        \\  <p style="color: red;" data-id="123">Text</p>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const root_node = z.documentRoot(doc).?;

    // Test removing all attributes
    removeAllAttributes(root_node);

    // Verify attributes are gone
    const body = try z.bodyElement(doc);
    const serialized = try z.serializeElement(allocator, body);
    defer allocator.free(serialized);

    // Should have no attributes left
    try testing.expect(
        !std.mem.containsAtLeast(u8, serialized, 1, "class="),
    );
    try testing.expect(
        !std.mem.containsAtLeast(u8, serialized, 1, "id="),
    );
    try testing.expect(
        !std.mem.containsAtLeast(u8, serialized, 1, "data-"),
    );
}

//==================================================================
// Callbacks for attribute search
// -----------------------------------------------------------------------

// -----------------------------------------------------------------------
/// Context for fast ID search using walker callback
const IdSearchContext = struct {
    target_id: []const u8,
    found_element: ?*z.HTMLElement,
};

/// [Attr search] Walker callback for `getElementById`
///
/// Returns STOP when ID is found, CONTINUE to keep searching
fn idWalkerCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
    if (ctx == null) return Action.CONTINUE.toU32();

    const search_ctx = castContext(IdSearchContext, ctx);

    if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();

    const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

    if (!z.hasAttribute(element, "id")) return Action.CONTINUE.toU32();

    const id_value = z.getElementId_zc(element);
    if (id_value.len == 0) return Action.CONTINUE.toU32();
    const match = std.mem.eql(u8, id_value, search_ctx.target_id);

    if (match) {
        search_ctx.found_element = element;
        return Action.STOP.toU32();
    }

    return Action.CONTINUE.toU32(); // Continue searching
}

// -----------------------------------------------------------------------

/// Context for fast class search using walker callback
const ClassSearchContext = struct {
    target_class: []const u8,
    found_element: ?*z.HTMLElement,
};

/// Fast walker callback for class search optimization
///
/// Returns STOP when class is found, CONTINUE to keep searching
fn classWalkerCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
    if (ctx == null) return Action.CONTINUE.toU32();

    const search_ctx = castContext(ClassSearchContext, ctx);

    if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();

    const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

    // Check if this element has a class attribute
    if (!z.hasAttribute(element, "class")) return Action.CONTINUE.toU32();

    const match = z.hasClass(element, search_ctx.target_class);
    if (match) {
        search_ctx.found_element = element;
        return Action.STOP.toU32();
    }

    return Action.CONTINUE.toU32(); // Continue searching
}

// -----------------------------------------------------------------------

/// Context for collecting multiple elements using walker callback
const MultiElementSearchContext = struct {
    target_attr_name: []const u8,
    target_attr_value: ?[]const u8, // null means just check for attribute existence
    target_class: ?[]const u8, // for class searches
    search_type: enum { attribute, class }, // what type of search we're doing
    allocator: std.mem.Allocator,
    results: std.ArrayList(*z.HTMLElement),
};
/// Fast walker callback for collecting multiple elements by attribute
///
/// Always returns CONTINUE to search entire tree
fn multiElementAttributeWalkerCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
    if (ctx == null) return Action.CONTINUE.toU32();

    const search_ctx = castContext(MultiElementSearchContext, ctx);

    // Only check element nodes
    if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();

    const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

    var matches = false;

    switch (search_ctx.search_type) {
        .attribute => {
            // Check if this element has the target attribute
            if (!z.hasAttribute(element, search_ctx.target_attr_name)) return Action.CONTINUE.toU32();

            // If we only care about attribute existence (value is null), it matches
            if (search_ctx.target_attr_value == null) {
                matches = true;
            } else {
                // Otherwise, check the attribute value
                const attr_value = z.getAttribute_zc(element, search_ctx.target_attr_name) orelse return Action.CONTINUE.toU32();
                matches = std.mem.eql(u8, attr_value, search_ctx.target_attr_value.?);
            }
        },
        .class => {
            // Check if this element has a class attribute
            if (!z.hasAttribute(element, "class")) return Action.CONTINUE.toU32();

            matches = z.hasClass(element, search_ctx.target_class.?);
        },
    }

    if (matches) {
        // Add to results - ignore allocation errors to keep walking
        search_ctx.results.append(element) catch {};
    }

    return Action.CONTINUE.toU32(); // Always continue searching
}

// -----------------------------------------------------------------------
/// Context for fast attribute search using walker callback
const AttributeSearchContext = struct {
    target_attr_name: []const u8,
    target_attr_value: ?[]const u8, // null means just check for attribute existence
    found_element: ?*z.HTMLElement,
};
/// Fast walker callback for attribute search optimization
///
/// Returns STOP when attribute is found, CONTINUE to keep searching
fn attributeWalkerCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
    if (ctx == null) return Action.CONTINUE.toU32();

    const search_ctx = castContext(AttributeSearchContext, ctx);

    // Only check element nodes
    if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();

    const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

    // Check if this element has the target attribute
    if (!z.hasAttribute(element, search_ctx.target_attr_name)) return Action.CONTINUE.toU32();

    // If we only care about attribute existence (value is null), we found it
    if (search_ctx.target_attr_value == null) {
        search_ctx.found_element = element;
        return Action.STOP.toU32();
    }

    // Otherwise, check the attribute value
    const attr_value = z.getAttribute_zc(element, search_ctx.target_attr_name) orelse return Action.CONTINUE.toU32();

    const match = std.mem.eql(u8, attr_value, search_ctx.target_attr_value.?);

    if (match) {
        search_ctx.found_element = element;
        return Action.STOP.toU32(); // Found it! Stop traversal
    }

    return Action.CONTINUE.toU32(); // Continue searching
}

// -------------------------------------------------------------------

//==================================================================
// ENHANCED GENERIC WALKER EXAMPLES
//==================================================================

// /// Example: Find element by ID using generic walker
// pub fn getElementByIdGeneric(doc: *z.HTMLDocument , id: []const u8) !?*z.HTMLElement {
//     const IdContext = struct {
//         target_id: []const u8,
//     };

//     const predicate = struct {
//         fn check(element: *z.HTMLElement, context: *IdContext) bool {
//             if (!z.hasAttribute(element, "id")) return false;
//             const id_value = z.getElementId_zc(element);
//             return std.mem.eql(u8, id_value, context.target_id);
//         }
//     }.check;

//     const root_node = z.documentRoot(doc) orelse return null;
//     var walker_ctx = GenericWalkerContext(
//         IdContext,
//         .single,
//     ).init(
//         std.heap.page_allocator,
//         .{ .target_id = id },
//     );
//     defer walker_ctx.deinit();

//     const callback = genericWalker(IdContext, .single, predicate, null);
//     lxb_dom_node_simple_walk(root_node, callback, &walker_ctx);

//     return walker_ctx.found_element;
// }

/// [walker] Remove all attributes matching a pattern
pub fn removeMatchingAttribute(
    allocator: std.mem.Allocator,
    root_node: *z.DomNode,
    attr_pattern: []const u8,
) !u16 {
    const rmCtx = WalkSpec{
        .target_attr = attr_pattern,
        .target_value = null,
    };

    const matchAll = struct {
        fn check(element: *z.HTMLElement, context: WalkSpec) bool {
            _ = element; // All elements are processed
            _ = context; // All elements are processed
            return true; // Process all elements
        }
    }.check;

    const process = struct {
        fn run(element: *z.HTMLElement, context: WalkSpec) void {
            var attribute = z.getFirstAttribute(element);
            while (attribute != null) {
                if (z.hasAttribute(element, context.target_attr)) {
                    z.removeAttribute(element, context.target_attr) catch {};
                }
                attribute = z.getNextAttribute(attribute.?);
            }
        }
    }.run;

    const results = try runtimeWalk(
        allocator,
        root_node,
        rmCtx,
        matchAll,
        process,
    );
    defer allocator.free(results);

    return @intCast(results.len);
}

test "removeMatchingAttribute" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<div id=\"1\" class=\"bold text-xs\"><span id=\"2\"></span><span id=\"3\"></span><span  class=\"bold\"></span> <span class=\"text-xs\"></span><span class=\"bold\"></span></div><input hidden><img src=\"img\">");

    const root_node = try z.bodyNode(doc);

    const expected_without_ids = "<body><div class=\"bold text-xs\"><span></span><span></span><span class=\"bold\"></span> <span class=\"text-xs\"></span><span class=\"bold\"></span></div><input hidden><img src=\"img\"></body>";
    const expected_without_hidden = "<body><div class=\"bold text-xs\"><span></span><span></span><span class=\"bold\"></span> <span class=\"text-xs\"></span><span class=\"bold\"></span></div><input><img src=\"img\"></body>";
    const expected_without_class = "<body><div><span></span><span></span><span></span> <span></span><span></span></div><input><img src=\"img\"></body>";
    const expected_without_src = "<body><div><span></span><span></span><span></span> <span></span><span></span></div><input><img></body>";

    const expectations = [_]struct { attr_name: []const u8, expected: []const u8 }{
        .{ .attr_name = "id", .expected = expected_without_ids },
        .{ .attr_name = "hidden", .expected = expected_without_hidden },
        .{ .attr_name = "class", .expected = expected_without_class },
        .{ .attr_name = "src", .expected = expected_without_src },
    };

    var i: usize = 0;
    while (i < expectations.len) {
        const expectation = expectations[i];
        // Apply the removal
        _ = try removeMatchingAttribute(
            allocator,
            root_node,
            expectation.attr_name,
        );

        // Serialize the result
        const html = try z.serializeElement(
            allocator,
            try z.bodyElement(doc),
        );
        defer allocator.free(html);

        // Check the result
        try testing.expectEqualStrings(
            expectation.expected,
            html,
        );

        i += 1;
    }
}

/// [walker] Collect all elements with specific tag name (HtmlTag)
///
/// Caller owns the slice
pub fn getElementsByTagName(allocator: std.mem.Allocator, doc: *z.HTMLDocument, tag: z.HtmlTag) ![]const *z.HTMLElement {
    const spec = WalkSpec{
        .target_tag = tag,
        .target_attr = "",
    };

    const predicate = struct {
        fn check(element: *z.HTMLElement, context: WalkSpec) bool {
            const element_tag = z.tagFromElement(element);
            return context.target_tag == element_tag;
        }
    }.check;

    const root_node = z.documentRoot(doc) orelse return &[_]*z.HTMLElement{};

    return runtimeWalk(
        allocator,
        root_node,
        spec,
        predicate,
        null,
    );
}

test "collect multiple elements: getElementsByTagName" {
    const allocator = testing.allocator;

    const html =
        \\<div>
        \\  <p>First paragraph</p>
        \\  <span>Span element</span>
        \\  <p>Second paragraph</p>
        \\  <div>Nested div</div>
        \\  <p>Third paragraph</p>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Collect all P elements
    const paragraphs = try getElementsByTagName(allocator, doc, .p);
    defer allocator.free(paragraphs);

    try testing.expect(paragraphs.len == 3);

    // Verify they are all P elements
    for (paragraphs) |p| {
        try testing.expectEqualStrings("P", z.tagName_zc(p));
    }
}

// /// Example: Add class to all elements matching a condition
// pub fn addClassToElements(doc: *z.HTMLDocument , condition_attr: []const u8, new_class: []const u8) !u32 {
//     const AddClassContext = struct {
//         condition_attr: []const u8,
//         new_class: []const u8,
//         modified_count: u32 = 0,
//         allocator: std.mem.Allocator,
//     };

//     const predicate = struct {
//         fn check(element: *z.HTMLElement, context: *AddClassContext) bool {
//             return z.hasAttribute(element, context.condition_attr);
//         }
//     }.check;

//     const processor = struct {
//         fn process(element: *z.HTMLElement, context: *AddClassContext) void {
//             // Check if element already has this class to avoid duplicates
//             if (z.hasClass(element, context.new_class)) {
//                 return; // Already has the class, skip
//             }

//             // Get current class value
//             const current_class = z.getAttribute_zc(element, "class") orelse "";

//             // Create new class value by appending the new class
//             var new_class_value = std.ArrayList(u8).init(context.allocator);
//             defer new_class_value.deinit();

//             if (current_class.len > 0) {
//                 new_class_value.appendSlice(current_class) catch return;
//                 new_class_value.append(' ') catch return;
//             }
//             new_class_value.appendSlice(context.new_class) catch return;

//             // Set the updated class attribute
//             const new_value = new_class_value.toOwnedSlice() catch return;
//             defer context.allocator.free(new_value);

//             z.setAttributes(element, &[_]z.AttributePair{.{ .name = "class", .value = new_value }}) catch {};

//             context.modified_count += 1;
//         }
//     }.process;

//     const root_node = z.documentRoot(doc) orelse return 0;
//     var walker_ctx = GenericWalkerContext(AddClassContext, .process).init(std.heap.page_allocator, .{
//         .condition_attr = condition_attr,
//         .new_class = new_class,
//         .allocator = std.heap.page_allocator,
//     });
//     defer walker_ctx.deinit();

//     const callback = genericWalker(AddClassContext, .process, predicate, processor);
//     lxb_dom_node_simple_walk(root_node, callback, &walker_ctx);

//     return walker_ctx.context.modified_count;
// }

// -----------------------------------------------------------------

fn matcher(element: *z.HTMLElement, spec: WalkSpec) bool {
    return switch (std.hash_map.hashString(spec.target_attr)) {
        std.hash_map.hashString("id") => {
            return z.hasElementId(element, spec.target_value orelse return false);
        },
        std.hash_map.hashString("class") => {
            return z.hasClass(element, spec.target_value orelse return false);
        },
        std.hash_map.hashString("data-*") => {
            if (!z.hasAttribute(element, spec.target_attr)) return false;
            if (spec.target_value) |expected| {
                const actual = z.getAttribute_zc(element, spec.target_attr) orelse return false;
                return std.mem.eql(u8, actual, expected);
            }
            return true; // Just existence check
        },
        else => {
            // Generic attribute matching (fallback)
            if (!z.hasAttribute(element, spec.target_attr)) return false;
            if (spec.target_value) |expected| {
                const actual = z.getAttribute_zc(element, spec.target_attr) orelse return false;
                return std.mem.eql(u8, actual, expected);
            }
            return true;
        },
    };
}

const WalkSpec = struct {
    target_attr: []const u8,
    target_tag: ?z.HtmlTag = null,
    target_value: ?[]const u8 = null,
    data: u16 = 0,
};

const WalkCtxType = struct {
    spec: WalkSpec,
    results: std.ArrayList(*z.HTMLElement),
    result: ?[]const u8 = null, // for single element searches
    matcher: *const fn (*z.HTMLElement, WalkSpec) bool,
    processor: ?*const fn (*z.HTMLElement, WalkSpec) void,

    pub fn deinit(self: *WalkCtxType) void {
        self.results.deinit();
    }
};

fn compWalk(
    allocator: std.mem.Allocator,
    root_node: *z.DomNode,
    spec: WalkSpec,
    comptime predicate: *const fn (*z.HTMLElement, WalkSpec) bool,
    comptime processor: ?*const fn (*z.HTMLElement, WalkSpec) void,
) ![]*z.HTMLElement {
    var ctx = WalkCtxType{
        .spec = spec,
        .results = std.ArrayList(*z.HTMLElement).init(allocator),
        .matcher = predicate,
        .processor = processor,
    };
    errdefer ctx.deinit();

    // follows the pattern needed by lexbor simple_walker callback with the context casted.
    const callback = struct {
        fn cb(node: *z.DomNode, context: ?*anyopaque) callconv(.C) u32 {
            if (context == null) return Action.CONTINUE.toU32();

            const walker_context = castContext(WalkCtxType, context);
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();
            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

            const matches = walker_context.matcher(element, walker_context.spec);

            if (matches) {
                if (walker_context.processor) |proc| {
                    proc(element, walker_context.spec);
                    walker_context.spec.data += 1;
                }
                walker_context.results.append(element) catch {};
                return Action.CONTINUE.toU32();
            }

            return Action.CONTINUE.toU32();
        }
    }.cb;

    lxb_dom_node_simple_walk(
        root_node,
        callback,
        &ctx,
    );
    return ctx.results.toOwnedSlice();
}

/// Runtime walker - takes function pointers (no comptime requirement)
fn runtimeWalk(
    allocator: std.mem.Allocator,
    root_node: *z.DomNode,
    spec: WalkSpec,
    predicate: *const fn (*z.HTMLElement, WalkSpec) bool,
    processor: ?*const fn (*z.HTMLElement, WalkSpec) void,
) ![]*z.HTMLElement {
    var ctx = WalkCtxType{
        .spec = spec,
        .results = std.ArrayList(*z.HTMLElement).init(allocator),
        .matcher = predicate,
        .processor = processor,
    };
    errdefer ctx.deinit();

    const callback = struct {
        fn cb(node: *z.DomNode, context: ?*anyopaque) callconv(.C) u32 {
            if (context == null) return Action.CONTINUE.toU32();

            const walker_context = castContext(WalkCtxType, context);
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();
            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

            const matches = walker_context.matcher(element, walker_context.spec);

            if (matches) {
                if (walker_context.processor) |proc| {
                    proc(element, walker_context.spec);
                }
                walker_context.results.append(element) catch {};
                return Action.CONTINUE.toU32();
            }

            return Action.CONTINUE.toU32();
        }
    }.cb;

    lxb_dom_node_simple_walk(
        root_node,
        callback,
        &ctx,
    );
    return ctx.results.toOwnedSlice();
}

test "runtimeWalk" {
    const allocator = testing.allocator;
    {
        const doc = try z.parseFromString("<p class=\"bold\"></p><p class=\"text-xs\"></p><p></p></p><p ><p class=\"text-xs\"></p>");

        const root_1 = z.documentRoot(doc).?; // <html>

        const expectations = [_]struct { spec: WalkSpec, len: u8 }{
            .{ .spec = .{ .target_attr = "class", .target_value = "bold" }, .len = 1 },
            .{ .spec = .{ .target_attr = "class", .target_value = "text-xs" }, .len = 2 },
        };

        var i: usize = 0;
        while (i < expectations.len) : (i += 1) {
            const exp = expectations[i];
            const result = try runtimeWalk(
                allocator,
                root_1,
                exp.spec,
                matcher,
                null,
            );
            defer allocator.free(result);
            try testing.expect(result.len == exp.len);
        }
    }
    {
        // test a fragment of the DOM
        const doc = try z.parseFromString("<div><p class=\"text-xs\"></p><p></p></div><div><p class=\"bold\"></p><p class=\"text-xs\"></p></div>");

        const root = try z.bodyNode(doc);
        const div = z.firstChild(root).?;

        const txt = try z.serializeElement(
            allocator,
            z.nodeToElement(div).?,
        );
        defer allocator.free(txt);
        try testing.expectEqualStrings(
            "<div><p class=\"text-xs\"></p><p></p></div>",
            txt,
        );

        const expectations = [_]struct { spec: WalkSpec, len: u8 }{
            .{ .spec = .{ .target_attr = "class", .target_value = "bold" }, .len = 0 },
            .{ .spec = .{ .target_attr = "class", .target_value = "text-xs" }, .len = 1 },
        };

        var i: usize = 0;
        while (i < expectations.len) : (i += 1) {
            const exp = expectations[i];
            const result = try runtimeWalk(
                allocator,
                div,
                exp.spec,
                matcher,
                null,
            );
            defer allocator.free(result);
            try testing.expect(result.len == exp.len);
        }
    }
}

/// [walker] Get elements by walk -
///
/// Specs _MUST_ use the struct `WalkSpec`
///
/// Caller owns the returned slice and must free it.
pub fn getElementsByWalk(
    allocator: std.mem.Allocator,
    node: *z.DomNode,
    context: WalkSpec,
) ![]*z.HTMLElement {
    return runtimeWalk(
        allocator,
        node,
        context,
        &matcher,
        null,
    );
}

test "getElementsByWalk" {
    const allocator = testing.allocator;

    const doc = try z.parseFromString("<p id=\"1\" class=\"bold\"></p><p class=\"text-xs\" id=\"2\"></p> <p id=\"3\" phx-click=\"increment\"></p><img src= ><img src=\"img\" data-id /></p><p ><p id=\"4\" class=\"text-xs\" data-id=\"4\"></p>");

    const root = z.documentRoot(doc).?; // <html>

    const expectations = [_]struct { spec: WalkSpec, len: u8 }{
        .{ .spec = .{ .target_attr = "phx-click" }, .len = 1 },
        .{ .spec = .{ .target_attr = "phx-click", .target_value = "increment" }, .len = 1 },
        .{ .spec = .{ .target_attr = "src" }, .len = 2 },
        .{ .spec = .{ .target_attr = "src", .target_value = "img" }, .len = 1 },
        .{ .spec = .{ .target_attr = "data-id" }, .len = 2 },
        .{ .spec = .{ .target_attr = "id", .target_value = "4" }, .len = 1 },
        .{ .spec = .{ .target_attr = "id" }, .len = 0 },
    };

    var i: usize = 0;
    while (i < expectations.len) : (i += 1) {
        const exp = expectations[i];
        const result = try getElementsByWalk(
            allocator,
            root,
            exp.spec,
        );
        defer allocator.free(result);
        try testing.expect(result.len == exp.len);
    }
}

// =============================================================================
// VERSIONS WITH TAGGED UNION: less pratical to use
// =============================================================================
const OptionType = union(enum) {
    single: ?*z.HTMLElement, // single element result
    multiple: []*z.HTMLElement, // multiple elements result
    all: void,
    err: []const u8,
};

/// Generic walker operation types
const WalkerOperation = enum {
    /// Find single element (stops on first match)
    single,
    /// Collect multiple elements (continues through entire tree)
    multiple,
    /// Process all elements (e.g., remove attributes, modify content)
    process,
};

/// [walker] Search / match spec -
///
/// The "what" to search. Can be:
///
/// `.single`, `.multiple`, `.all` (to perform an action on every matching node)
///
/// ---
const SearchSpec = struct {
    target_attr: []const u8, // "id", "class", "data-*", etc.
    target_value: ?[]const u8 = null, // null = existence check only
    mode: WalkerOperation, // single, multiple, or all
};

/// [walker] Walker context - holds search spec and results
///
/// The "how" to search
const WalkerContext = struct {
    allocator: std.mem.Allocator,
    spec: SearchSpec,
    results: std.ArrayList(*z.HTMLElement),
    result: *z.HTMLElement,
};

const WalkerContextType = struct {
    spec: SearchSpec,
    results: std.ArrayList(*z.HTMLElement),
    result: ?*z.HTMLElement,
    predicate: *const fn (*z.HTMLElement, SearchSpec) bool,
    processor: ?*const fn (*z.HTMLElement, SearchSpec) void,

    pub fn deinit(self: *WalkerContextType) void {
        self.results.deinit();
    }
};

fn universalPredicate(element: *z.HTMLElement, spec: SearchSpec) bool {
    return switch (std.hash_map.hashString(spec.target_attr)) {
        std.hash_map.hashString("id") => {
            return z.hasElementId(element, spec.target_value orelse return false);
        },
        std.hash_map.hashString("class") => {
            return z.hasClass(element, spec.target_value orelse return false);
        },
        std.hash_map.hashString("data-*") => {
            if (!z.hasAttribute(element, spec.target_attr)) return false;
            if (spec.target_value) |expected| {
                const actual = z.getAttribute_zc(element, spec.target_attr) orelse return false;
                return std.mem.eql(u8, actual, expected);
            }
            return true; // Just existence check
        },
        else => {
            // Generic attribute matching (fallback)
            if (!z.hasAttribute(element, spec.target_attr)) return false;
            if (spec.target_value) |expected| {
                const actual = z.getAttribute_zc(element, spec.target_attr) orelse return false;
                return std.mem.eql(u8, actual, expected);
            }
            return true;
        },
    };
}

// TODO: to use universalPredicate
fn comptime_walker(
    allocator: std.mem.Allocator,
    root: *z.DomNode,
    spec: SearchSpec,
    comptime predicate: *const fn (*z.HTMLElement, SearchSpec) bool,
    comptime processor: ?*const fn (*z.HTMLElement, SearchSpec) void,
) !WalkerContextType {
    var ctx = WalkerContextType{
        .spec = spec,
        .results = std.ArrayList(*z.HTMLElement).init(allocator), // ✅ Own the ArrayList
        .result = null,
        .predicate = predicate,
        .processor = processor,
    };
    errdefer ctx.deinit(); // Clean up on error

    const callback = struct {
        fn cb(node: *z.DomNode, context: ?*anyopaque) callconv(.C) u32 {
            if (context == null) return Action.CONTINUE.toU32();

            const walker_context = castContext(WalkerContextType, context);
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();
            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

            const matches = walker_context.predicate(element, walker_context.spec);

            if (matches) {
                if (walker_context.processor) |proc| {
                    proc(element, walker_context.spec);
                }

                switch (walker_context.spec.mode) {
                    .single => {
                        walker_context.result = element;
                        return Action.STOP.toU32();
                    },
                    .multiple => {
                        walker_context.results.append(element) catch {};
                        return Action.CONTINUE.toU32();
                    },
                    .process => {
                        return Action.CONTINUE.toU32();
                    },
                }
            }

            return Action.CONTINUE.toU32();
        }
    }.cb;

    lxb_dom_node_simple_walk(root, callback, &ctx);
    return ctx; // ✅ Now safe to return
}

/// walker function that can be customized for different operations
///
/// Caller owns the returned slice
fn runtime_walker(
    allocator: std.mem.Allocator,
    root: *z.DomNode,
    spec: SearchSpec,
    predicate: *const fn (*z.HTMLElement, SearchSpec) bool,
    processor: ?*const fn (*z.HTMLElement, SearchSpec) void,
) ![]const *z.HTMLElement {
    var results = std.ArrayList(*z.HTMLElement).init(allocator);
    errdefer results.deinit(); // Clean up on error

    const RTWalkCtxType = struct {
        spec: SearchSpec,
        results: *std.ArrayList(*z.HTMLElement),
        predicate: *const fn (*z.HTMLElement, SearchSpec) bool,
        processor: ?*const fn (*z.HTMLElement, SearchSpec) void,
    };

    var ctx = RTWalkCtxType{
        .spec = spec,
        .results = &results,
        .predicate = predicate,
        .processor = processor,
    };

    const callback = struct {
        fn cb(node: *z.DomNode, context: ?*anyopaque) callconv(.C) u32 {
            if (context == null) return Action.CONTINUE.toU32();

            // Cast to the correct context type
            const walker_context = castContext(RTWalkCtxType, context);
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();
            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

            // Call predicate with the spec
            const matches = walker_context.predicate(element, walker_context.spec);

            if (matches) {
                // Apply processor function if provided
                if (walker_context.processor) |proc| {
                    proc(element, walker_context.spec);
                }

                switch (walker_context.spec.mode) {
                    .single => {
                        walker_context.results.append(element) catch {};
                        return Action.STOP.toU32();
                    },
                    .multiple => {
                        walker_context.results.append(element) catch {};
                        return Action.CONTINUE.toU32();
                    },
                    .process => {
                        return Action.CONTINUE.toU32();
                    },
                }
            }

            return Action.CONTINUE.toU32();
        }
    }.cb;

    lxb_dom_node_simple_walk(root, callback, &ctx);
    return results.toOwnedSlice();
}

fn myPredicate(element: *z.HTMLElement, ctx: SearchSpec) bool {
    if (!z.hasAttribute(element, ctx.target_attr)) return false;
    if (std.mem.eql(u8, "id", ctx.target_attr)) {
        return z.hasElementId(element, ctx.target_value orelse return false);
    }
    const value = z.getAttribute_zc(element, ctx.target_attr) orelse return false;
    return std.mem.eql(u8, value, ctx.target_value.?);
}

fn myprocessor(element: *z.HTMLElement, ctx: SearchSpec) void {
    _ = element;
    _ = ctx;
    // Process the element as needed
}

fn getByRuntime(
    allocator: std.mem.Allocator,
    root_node: *z.DomNode,
    context: SearchSpec,
    predicate: *const fn (*z.HTMLElement, SearchSpec) bool,
    processor: ?*const fn (*z.HTMLElement, SearchSpec) void,
) ![]const *z.HTMLElement {
    _ = processor;
    return runtime_walker(
        allocator,
        root_node,
        context,
        predicate,
        null,
    );
}

/// [walker] Comptime search
///
/// Caller owns the returned slice (case `.multiple`)
fn getByComptime(
    allocator: std.mem.Allocator,
    root_node: *z.DomNode,
    context: SearchSpec,
) !OptionType {
    var walker_context = try comptime_walker(
        allocator,
        root_node,
        context,
        &universalPredicate,
        null,
    );
    defer walker_context.deinit(); // ✅ Clean up the ArrayList

    return switch (walker_context.spec.mode) {
        .single => OptionType{ .single = walker_context.result },
        .multiple => OptionType{ .multiple = try walker_context.results.toOwnedSlice() },
        .process => OptionType{ .all = {} },
    };
}

test "getById Runtime & Comptime" {
    const allocator = testing.allocator;

    const html = "<div id=\"1\" class=\"bold\"></div><div class=\"bold\" id=\"2\"></div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const root_node = z.documentRoot(doc) orelse return;

    // Test getById
    const runtime_element_1 = try getByRuntime(
        allocator,
        root_node,
        .{
            .target_attr = "id",
            .target_value = "1",
            .mode = .single,
        },
        &myPredicate,
        null,
    );
    defer allocator.free(runtime_element_1);

    try testing.expect(runtime_element_1.len > 0);

    const runtime_element_2 = try getByRuntime(
        allocator,
        root_node,
        .{
            .target_attr = "id",
            .target_value = "10",
            .mode = .single,
        },
        &myPredicate,
        null,
    );
    defer allocator.free(runtime_element_2);

    try testing.expect(runtime_element_2.len == 0);

    const comptime_element_1 = try getByComptime(
        allocator,
        root_node,
        .{
            .target_attr = "id",
            .target_value = "10",
            .mode = .single,
        },
    );

    try testing.expect(comptime_element_1.single == null);

    const comptime_element_2 = try getByComptime(
        allocator,
        root_node,
        .{
            .target_attr = "id",
            .target_value = "2",
            .mode = .single,
        },
    );

    const element = try z.serializeElement(
        allocator,
        comptime_element_2.single.?,
    );
    defer allocator.free(element);
    try testing.expectEqualStrings(
        "<div class=\"bold\" id=\"2\"></div>",
        element,
    );

    const runtime_element_3 = try getByRuntime(
        allocator,
        root_node,
        .{
            .target_attr = "class",
            .target_value = "bold",
            .mode = .multiple,
        },
        &myPredicate,
        null,
    );
    defer allocator.free(runtime_element_3);

    try testing.expect(runtime_element_3.len == 2);

    const comptime_element_3 = try getByComptime(
        allocator,
        root_node,
        .{
            .target_attr = "class",
            .target_value = "bold",
            .mode = .multiple,
        },
    );
    defer allocator.free(comptime_element_3.multiple);

    try testing.expect(comptime_element_3.multiple.len == 2);

    // if (comptime_element_3) |e| {
    //     const element = try z.serializeElement(allocator, e);
    //     defer allocator.free(element);
    //     try testing.expectEqualStrings("<div class=\"bold\" id=\"2\">Second</div>", element);
    // }

}

// ----------------------------------------------------------
// TESTS
// ----------------------------------------------------------

test "element / attribute  name & value" {
    const allocator = testing.allocator;

    const html =
        "<div class='test' id='my-id' data-value='123' title='tooltip' hidden>Content</div>";

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const body_node = try z.bodyNode(doc);
    const div = z.firstChild(body_node).?;
    const div_elt = z.nodeToElement(div).?;

    // Get ID attribute from an element
    const id = try z.getElementId(allocator, div_elt);
    defer allocator.free(id);
    try testing.expectEqualStrings(id, "my-id");

    // get attribute name and value
    const first = z.getFirstAttribute(div_elt).?;
    const name = try z.getAttributeName(allocator, first);
    defer allocator.free(name);
    try testing.expectEqualStrings(name, "class");
    const value = try z.getAttributeValue(allocator, first);
    defer allocator.free(value);
    try testing.expectEqualStrings("test", value);
}

test "collect  attributes" {
    const allocator = testing.allocator;

    const html = "<div class='test' id='my-id' data-value='123' title='tooltip' hidden>Content</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const body_node = try z.bodyNode(doc);
    const div = z.firstChild(body_node).?;
    const div_elt = z.nodeToElement(div).?;

    const attrs = try z.getAttributes(
        allocator,
        div_elt,
    );
    defer {
        for (attrs) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        allocator.free(attrs);
    }

    const expected_names = [_][]const u8{ "class", "id", "data-value", "title", "hidden" };
    const expected_values = [_][]const u8{ "test", "my-id", "123", "tooltip", "" };

    for (attrs, 0..) |attr_pair, i| {
        _ = i; // Unused index
        // print("Attribute {}: {s} = {s}\n", .{ i, attr_pair.name, attr_pair.value });

        // Find this attribute in expected lists
        var found = false;
        for (expected_names, 0..) |expected_name, j| {
            if (std.mem.eql(u8, attr_pair.name, expected_name)) {
                try testing.expectEqualStrings(expected_values[j], attr_pair.value);
                found = true;
                break;
            }
        }
        try testing.expect(found);
    }
}

test "single element search" {
    const allocator = testing.allocator;
    const html =
        \\<div>
        \\  <p id="target" class="text">Target paragraph</p>
        \\  <span class="highlight">Span 1</span>
        \\  <span class="highlight">Span 2</span>
        \\  <div>
        \\    <p id="nested" class="text">Nested paragraph</p>
        \\  </div>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test compile-time ID search with compile-time known string
    const element_by_id = getElementById(
        z.documentRoot(doc).?,
        "target",
    );
    try testing.expect(element_by_id != null);

    const id_text = try z.getTextContent(
        allocator,
        z.elementToNode(element_by_id.?),
    );
    defer allocator.free(id_text);
    try testing.expect(std.mem.eql(u8, id_text, "Target paragraph"));

    // Test compile-time class search with compile-time known string
    const element_by_class = getElementByClass(
        z.documentRoot(doc).?,
        "highlight",
    );
    try testing.expect(element_by_class != null);
    try testing.expect(z.hasClass(element_by_class.?, "highlight"));

    // Test compile-time tag search
    const element_by_tag = getElementByTag(
        z.documentRoot(doc).?,
        .span,
    );
    try testing.expect(element_by_tag != null);
    try testing.expect(z.tagFromElement(element_by_tag.?) == .span);
}

test "multiple element search" {
    const allocator = testing.allocator;
    const html =
        \\<div>
        \\  <p class="text">Paragraph 1</p>
        \\  <span class="highlight">Span 1</span>
        \\  <span class="highlight">Span 2</span>
        \\  <div>
        \\    <p class="text">Paragraph 2</p>
        \\    <span class="highlight">Span 3</span>
        \\  </div>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test compile-time class search (multiple) with correct parameter order
    const elements_by_class = try getElementsByClass(
        z.documentRoot(doc).?,
        "highlight",
        allocator,
    );
    defer allocator.free(elements_by_class);
    try testing.expect(elements_by_class.len == 3);

    // Verify all found elements have the class
    for (elements_by_class) |element| {
        try testing.expect(z.hasClass(element, "highlight"));
    }

    // Test compile-time tag search (multiple) with correct parameter order
    const elements_by_tag = try getElementsByTag(
        z.documentRoot(doc).?,
        .p,
        allocator,
    );
    defer allocator.free(elements_by_tag);
    try testing.expect(elements_by_tag.len == 2);

    // Verify all found elements are paragraphs
    for (elements_by_tag) |element| {
        try testing.expect(z.tagFromElement(element) == .p);
    }
}

test "bigger search functions" {
    const html =
        \\<html>
        \\<head><title>Test Document</title></head>
        \\<body>
        \\  <div id="header" class="navigation top-level" data-section="header">
        \\    <nav class="menu">
        \\      <a href="/home" class="nav-link active" data-page="home">Home</a>
        \\      <a href="/about" class="nav-link" data-page="about">About</a>
        \\    </nav>
        \\  </div>
        \\  <main id="content" class="main-content" phx-section="content">
        \\    <article class="post featured" data-id="123" data-category="tech">
        \\      <h1 class="title">Article Title</h1>
        \\      <p class="intro">Introduction paragraph</p>
        \\    </article>
        \\    <aside class="sidebar" data-widget="recent-posts">
        \\      <div class="widget" data-type="list">Widget Content</div>
        \\    </aside>
        \\  </main>
        \\  <footer id="footer" class="bottom-section" data-section="footer">
        \\    <span class="copyright">© 2025</span>
        \\  </footer>
        \\</body>
        \\</html>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const root_node = z.documentRoot(doc).?;

    // Test 1: getElementByIdFast - should find elements by ID
    const header = getElementById(
        root_node,
        "header",
    );
    try testing.expect(header != null);
    try testing.expectEqualStrings("DIV", z.tagName_zc(header.?));

    const content = getElementById(
        root_node,
        "content",
    );
    try testing.expect(content != null);
    try testing.expectEqualStrings("MAIN", z.tagName_zc(content.?));

    const footer = getElementById(
        root_node,
        "footer",
    );
    try testing.expect(footer != null);
    try testing.expectEqualStrings("FOOTER", z.tagName_zc(footer.?));

    // Test 2: getElementByClassFast - should find first element with class
    const nav_link = getElementByClass(
        root_node,
        "nav-link",
    );
    try testing.expect(nav_link != null);
    try testing.expectEqualStrings("A", z.tagName_zc(nav_link.?));

    const post = getElementByClass(
        root_node,
        "post",
    );
    try testing.expect(post != null);
    try testing.expectEqualStrings("ARTICLE", z.tagName_zc(post.?));

    const widget = getElementByClass(
        root_node,
        "widget",
    );
    try testing.expect(widget != null);
    try testing.expectEqualStrings("DIV", z.tagName_zc(widget.?));

    // Test 3: getElementByAttributeFast - attribute existence only
    const href_element = getElementByAttribute(
        root_node,
        "href",
        null,
    );
    try testing.expect(href_element != null);
    try testing.expectEqualStrings("A", z.tagName_zc(href_element.?));

    // Test 4: getElementByAttributeFast - attribute with specific value
    const home_link = getElementByAttribute(
        root_node,
        "href",
        "/home",
    );
    try testing.expect(home_link != null);
    try testing.expectEqualStrings("A", z.tagName_zc(home_link.?));

    const about_link = getElementByAttribute(
        root_node,
        "href",
        "/about",
    );
    try testing.expect(about_link != null);
    try testing.expectEqualStrings("A", z.tagName_zc(about_link.?));

    // Test 5: getElementByDataAttributeFast - data attributes
    const header_section = try getElementByDataAttribute(
        root_node,
        "data",
        "section",
        "header",
    );
    try testing.expectEqualStrings("DIV", z.tagName_zc(header_section.?));

    const home_page = try getElementByDataAttribute(
        root_node,
        "data",
        "page",
        "home",
    );
    try testing.expectEqualStrings("A", z.tagName_zc(home_page.?));

    const tech_article = try getElementByDataAttribute(
        root_node,
        "data",
        "category",
        "tech",
    );
    try testing.expect(tech_article != null);
    try testing.expectEqualStrings("ARTICLE", z.tagName_zc(tech_article.?));

    // Test custom prefix functionality (phx- instead of data-)
    const content_section = try getElementByDataAttribute(
        root_node,
        "phx",
        "section",
        "content",
    );
    try testing.expectEqualStrings("MAIN", z.tagName_zc(content_section.?));

    // Test 6: Non-existent searches should return null
    const missing_id = getElementById(
        root_node,
        "nonexistent",
    );
    try testing.expect(missing_id == null);

    const missing_class = getElementByClass(
        root_node,
        "nonexistent-class",
    );
    try testing.expect(missing_class == null);

    const missing_attr = getElementByAttribute(
        root_node,
        "nonexistent-attr",
        "value",
    );
    try testing.expect(missing_attr == null);

    const missing_data = try getElementByDataAttribute(
        root_node,
        "nonexistent",
        "data",
        "value",
    );
    try testing.expect(missing_data == null);
}

// test "collection vs walker - when collections are still useful" {
//     const allocator = testing.allocator;

//     const html =
//         \\<html><body>
//         \\  <div data-id="42">Exact match</div>
//         \\  <div data-id="142">Partial match</div>
//         \\  <div data-id="420">Partial match</div>
//         \\  <div data-category="electronics">Category</div>
//         \\</body></html>
//     ;

//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     // std.debug.print("\n=== When Collections Excel ===\n", .{});

//     // Test exact attribute value matching where collections work well
//     const walker_data_42 = try getElementsByDataAttributeWalker(allocator, doc, "id", "42");
//     defer allocator.free(walker_data_42);

//     // For exact data-id matching, let's use getElementsByAttributePair directly
//     const collection_data_42 = try z.getElementsByAttributePair(doc, .{ .name = "data-id", .value = "42" }, false);
//     const collection_data_42_count = if (collection_data_42) |coll| blk: {
//         defer z.destroyCollection(coll);
//         break :blk z.collectionLength(coll);
//     } else 0;

//     // std.debug.print("Exact data-id='42' matching:\n", .{});
//     // std.debug.print("  Walker: {} elements\n", .{walker_data_42.len});
//     // std.debug.print("  Collection: {} elements\n", .{collection_data_42_count});

//     // Both should find exactly 1 element
//     try testing.expect(walker_data_42.len == 1);
//     try testing.expect(collection_data_42_count == 1);

//     // std.debug.print("• Walker: Better for CSS classes (token-based)\n", .{});
//     // std.debug.print("• Collection: Better for exact attribute values\n", .{});
//     // std.debug.print("• Walker: Better for single-element searches (early exit)\n", .{});
//     // std.debug.print("• Collection: Better for bulk operations on known large result sets\n", .{});
// }
