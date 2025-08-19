//! Optimized DOM Search Using Walker Callbacks

//======================================================================
// OPTIMIZED DOM SEARCH USING WALKER CALLBACKS
//=======================================================================

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const print = std.debug.print;
const testing = std.testing;

// Fast DOM traversal for optimized ID search
extern "c" fn lxb_dom_node_simple_walk(root: *z.DomNode, walker_cb: *const fn (*z.DomNode, ?*anyopaque) callconv(.C) u32, ctx: ?*anyopaque) void;

/// Generic walker operation types
const WalkerOperation = enum {
    /// Find single element (stops on first match)
    single,
    /// Collect multiple elements (continues through entire tree)
    multiple,
    /// Process all elements (e.g., remove attributes, modify content)
    process,
};

const IdSearch = struct {
    target_id: []const u8,
};

const ClassSearch = struct {
    target_class: []const u8,
};

const TagSearch = struct {
    target_tag: z.HtmlTag,
};

const AttrSearch = struct {
    attr_name: []const u8,
    attr_value: ?[]const u8,
};

const SearchMode = enum { single, multiple };
const SearchResult = union(enum) { result: ?*z.DomElement, results: ?[]*z.DomElement };

/// Unified compile-time walker for both single and multiple element search
/// Mode determines behavior and return type through compile-time dispatch
fn comptimeWalker(
    comptime SearchType: type,
    comptime search_config: SearchType,
    comptime mode: SearchMode,
    allocator: ?std.mem.Allocator,
    root_node: *z.DomNode,
) (if (mode == .single) ?*z.DomElement else std.mem.Allocator.Error![]const *z.DomElement) {
    // Compile-time context selection based on mode
    const Context = switch (mode) {
        .single => struct {
            found_element: ?*z.DomElement = null,
        },
        .multiple => struct {
            results: std.ArrayList(*z.DomElement),

            pub fn init(alloc: std.mem.Allocator) @This() {
                return .{ .results = std.ArrayList(*z.DomElement).init(alloc) };
            }

            pub fn deinit(self: *@This()) void {
                self.results.deinit();
            }
        },
    };

    // Initialize context based on mode
    var ctx = switch (mode) {
        .single => Context{},
        .multiple => Context.init(allocator.?),
    };

    // Clean up for multiple mode
    if (mode == .multiple) {
        defer ctx.deinit();
    }

    const callback = struct {
        fn cb(node: *z.DomNode, context: ?*anyopaque) callconv(.C) u32 {
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();
            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();

            var found = false;
            search_result: {
                switch (SearchType) {
                    IdSearch => {
                        if (!z.hasAttribute(element, "id")) break :search_result;
                        const id_value = z.getElementId_zc(element);
                        found = std.mem.eql(u8, id_value, search_config.target_id);
                        break :search_result;
                    },
                    ClassSearch => {
                        if (!z.hasAttribute(element, "class")) break :search_result;
                        found = z.hasClass(element, search_config.target_class);
                        break :search_result;
                    },
                    TagSearch => {
                        const tag = z.tagFromElement(element);
                        found = tag == search_config.target_tag;
                        break :search_result;
                    },
                    AttrSearch => {
                        if (!z.hasAttribute(element, search_config.attr_name)) break :search_result;
                        if (search_config.attr_value) |expected| {
                            const actual = z.getAttribute_zc(element, search_config.attr_name) orelse break :search_result;
                            found = std.mem.eql(u8, actual, expected);
                        } else {
                            found = true;
                        }
                        break :search_result;
                    },
                    else => @compileError("Unsupported SearchType for compile-time walker"),
                }
            }

            if (found) {
                // Compile-time mode dispatch for different behavior
                switch (mode) {
                    .single => {
                        const search_ctx = castContext(Context, context);
                        search_ctx.found_element = element;
                        return Action.STOP.toU32();
                    },
                    .multiple => {
                        const search_ctx = castContext(Context, context);
                        search_ctx.results.append(element) catch {}; // Ignore allocation errors to keep walking
                        return Action.CONTINUE.toU32();
                    },
                }
            }

            return Action.CONTINUE.toU32();
        }
    }.cb;

    // Direct integration with lxb_dom_node_simple_walk
    lxb_dom_node_simple_walk(root_node, callback, &ctx);

    // Return based on mode
    return switch (mode) {
        .single => ctx.found_element,
        .multiple => ctx.results.toOwnedSlice(),
    };
}

/// [walker] Fast getElementById using optimized DOM traversal
///
/// Returns the first element with matching ID, or null if not found.
/// IDs are "strings"
pub fn getElementByIdFast(doc: *z.HtmlDocument, id: []const u8) !?*z.DomElement {
    const root_node = z.documentRoot(doc) orelse return null;

    var search_ctx = IdSearchContext{
        .target_id = id,
        .found_element = null,
    };

    // Walk the DOM tree with our callback
    lxb_dom_node_simple_walk(root_node, idWalkerCallback, &search_ctx);

    return search_ctx.found_element;
}

/// [attributes] Fast getElementByClass using optimized DOM traversal
///
/// Significantly faster than iterating through all elements and checking classes.
/// Uses the same optimization pattern as getElementByIdFast.
///
/// Returns the first element with matching class, or null if not found.
pub fn getElementByClassFast(doc: *z.HtmlDocument, class_name: []const u8) !?*z.DomElement {
    const root_node = z.documentRoot(doc) orelse return null;

    var search_ctx = ClassSearchContext{
        .target_class = class_name,
        .found_element = null,
    };

    lxb_dom_node_simple_walk(root_node, classWalkerCallback, &search_ctx);

    return search_ctx.found_element;
}

/// [attributes] Fast data attribute search - convenience wrapper
///
/// Searches for elements with `prefix-*` attributes (`data` or `custom`).
/// ## Example:
/// ```
/// // finds elements with data-id="123"
/// getElementByDataAttributeFast(doc, "data", "id", "123");
/// getElementByDataAttributeFast(doc, "phx", "click", "inc_temperature");
/// ---
/// ```
pub fn getElementByDataAttributeFast(doc: *z.HtmlDocument, prefix: []const u8, data_name: []const u8, value: ?[]const u8) !?*z.DomElement {
    // Build the full data attribute name
    var attr_name_buffer: [256]u8 = undefined;
    const attr_name = try std.fmt.bufPrint(
        attr_name_buffer[0..],
        "{s}-{s}",
        .{ prefix, data_name },
    );

    return getElementByAttributeFast(doc, attr_name, value);
}

/// [attributes] Fast getElementByAttribute using optimized DOM traversal
///
/// Finds the first element with a specific attribute name and optionally a specific value.
/// If attr_value is null, only checks for attribute existence.
///
/// Returns the first matching element, or null if not found.
pub fn getElementByAttributeFast(doc: *z.HtmlDocument, attr_name: []const u8, attr_value: ?[]const u8) !?*z.DomElement {
    const root_node = z.documentRoot(doc) orelse return null;

    var search_ctx = AttributeSearchContext{
        .target_attr_name = attr_name,
        .target_attr_value = attr_value,
        .found_element = null,
    };

    lxb_dom_node_simple_walk(root_node, attributeWalkerCallback, &search_ctx);

    return search_ctx.found_element;
}

//==================================================================
// COMPILE-TIME WALKER PUBLIC API
//==================================================================

/// Compile-time getElementById - maximum performance for known IDs
/// No allocation needed, returns null if not found
pub fn getElementByIdComptime(comptime id: []const u8, doc: *z.HtmlDocument) ?*z.DomElement {
    const root_node = z.documentRoot(doc) orelse return null;
    return comptimeWalker(IdSearch, .{ .target_id = id }, .single, null, root_node);
}

/// Compile-time getElementByClass - maximum performance for known classes
/// No allocation needed, returns null if not found
pub fn getElementByClassComptime(comptime class_name: []const u8, doc: *z.HtmlDocument) ?*z.DomElement {
    const root_node = z.documentRoot(doc) orelse return null;
    return comptimeWalker(ClassSearch, .{ .target_class = class_name }, .single, null, root_node);
}

/// Compile-time getElementByTagName - maximum performance for known tags
/// No allocation needed, returns null if not found
pub fn getElementByTagComptime(comptime tag: z.HtmlTag, doc: *z.HtmlDocument) ?*z.DomElement {
    const root_node = z.documentRoot(doc) orelse return null;
    return comptimeWalker(TagSearch, .{ .target_tag = tag }, .single, null, root_node);
}

/// Compile-time getElementsByClass - maximum performance for known classes
/// Caller owns returned slice and must free it
pub fn getElementsByClassComptime(comptime class_name: []const u8, allocator: std.mem.Allocator, doc: *z.HtmlDocument) ![]const *z.DomElement {
    const root_node = z.documentRoot(doc) orelse return &[_]*z.DomElement{};
    return comptimeWalker(ClassSearch, .{ .target_class = class_name }, .multiple, allocator, root_node);
}

/// Compile-time getElementsByTagName - maximum performance for known tags
/// Caller owns returned slice and must free it
pub fn getElementsByTagComptime(comptime tag: z.HtmlTag, allocator: std.mem.Allocator, doc: *z.HtmlDocument) ![]const *z.DomElement {
    const root_node = z.documentRoot(doc) orelse return &[_]*z.DomElement{};
    return comptimeWalker(TagSearch, .{ .target_tag = tag }, .multiple, allocator, root_node);
}

//==================================================================
// UNIFIED COMPILE-TIME WALKER EXAMPLES
//==================================================================

// Example demonstrating the unified comptimeWalker approach:
// Same walker function handles both single and multiple element searches
// with compile-time mode dispatch for maximum performance
test "unified comptimeWalker examples" {
    const allocator = testing.allocator;

    const html =
        \\<div id="main" class="container">
        \\  <span class="highlight">First span</span>
        \\  <p class="highlight">Paragraph</p>
        \\  <span class="highlight">Second span</span>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const root_node = z.documentRoot(doc).?;

    // ✅ Single element search - no allocation
    const single_element = comptimeWalker(IdSearch, .{ .target_id = "main" }, .single, null, root_node);
    try testing.expect(single_element != null);

    // ✅ Multiple element search - returns owned slice
    const multiple_elements = try comptimeWalker(ClassSearch, .{ .target_class = "highlight" }, .multiple, allocator, root_node);
    defer allocator.free(multiple_elements);
    try testing.expect(multiple_elements.len == 3);

    // ✅ Same walker, different search types and modes
    const span_elements = try comptimeWalker(TagSearch, .{ .target_tag = .span }, .multiple, allocator, root_node);
    defer allocator.free(span_elements);
    try testing.expect(span_elements.len == 2);
}

//==================================================================
// Callbacks for attribute search
// -----------------------------------------------------------------------

/// convert from "aligned" `anyopaque` to the target pointer type `T`
/// because of the callback signature:
fn castContext(comptime T: type, ctx: ?*anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(ctx.?)));
}

// -----------------------------------------------------------------------
/// Context for fast ID search using walker callback
const IdSearchContext = struct {
    target_id: []const u8,
    found_element: ?*z.DomElement,
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
    found_element: ?*z.DomElement,
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
    results: std.ArrayList(*z.DomElement),
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
    found_element: ?*z.DomElement,
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

/// [walker] action types
const Action = enum(u32) {
    /// Continue traversing the DOM tree
    // const LEXBOR_ACTION_OK: u32 = 0;
    CONTINUE = 0,
    /// Stop traversal immediately (single element searches)
    // const LEXBOR_ACTION_STOP: u32 = 1;
    STOP = 1,

    // Convert to u32 for C callback compatibility
    pub fn toU32(self: Action) u32 {
        return @intFromEnum(self);
    }
};

test "walker action enum clarity" {
    // Demonstrate the improved semantics
    const action_continue = Action.CONTINUE;
    const action_stop = Action.STOP;

    try testing.expect(action_continue.toU32() == 0);
    try testing.expect(action_stop.toU32() == 1);

    // Shows intent much clearer than magic numbers
    const should_continue = true;
    const next_action: Action = if (should_continue) .CONTINUE else .STOP;
    try testing.expect(next_action == .CONTINUE);
}

//==================================================================
// GENERIC WALKER INFRASTRUCTURE
//==================================================================

/// Generic context for walker-based DOM operations
fn GenericWalkerContext(comptime ContextType: type, comptime operation: WalkerOperation) type {
    return struct {
        const Self = @This();

        // User-defined context data
        context: ContextType,

        // Operation-specific data
        found_element: if (operation == .single) ?*z.DomElement else void,
        results: if (operation == .multiple) std.ArrayList(*z.DomElement) else void,

        // Statistics
        nodes_visited: u32 = 0,
        elements_processed: u32 = 0,

        pub fn init(allocator: std.mem.Allocator, context: ContextType) Self {
            return Self{
                .context = context,
                .found_element = if (operation == .single) null else {},
                .results = if (operation == .multiple) std.ArrayList(*z.DomElement).init(allocator) else {},
            };
        }

        pub fn deinit(self: *Self) void {
            if (operation == .multiple) {
                self.results.deinit();
            }
        }

        pub fn getResults(self: *Self) ![]const *z.DomElement {
            return switch (operation) {
                .single => if (self.found_element) |elem| &[_]*z.DomElement{elem} else &[_]*z.DomElement{},
                .multiple => self.results.toOwnedSlice(),
                .process => &[_]*z.DomElement{}, // No results for processing operations
            };
        }
    };
}

/// Generic walker function that can be customized for different operations
fn genericWalker(
    comptime ContextType: type,
    comptime operation: WalkerOperation,
    comptime predicate: fn (*z.DomElement, *ContextType) bool,
    comptime processor: ?fn (*z.DomElement, *ContextType) void,
) fn (*z.DomNode, ?*anyopaque) callconv(.C) u32 {
    const WalkerCtx = GenericWalkerContext(
        ContextType,
        operation,
    );

    return struct {
        fn callback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
            if (ctx == null) return Action.CONTINUE.toU32();

            const walker_ctx = castContext(WalkerCtx, ctx);
            walker_ctx.nodes_visited += 1;

            // Only process element nodes
            if (!z.isTypeElement(node)) return Action.CONTINUE.toU32();

            const element = z.nodeToElement(node) orelse return Action.CONTINUE.toU32();
            walker_ctx.elements_processed += 1;

            // Check if this element matches our criteria
            const matches = predicate(element, &walker_ctx.context);

            if (matches) {
                // Apply processor function if provided
                if (processor) |proc| {
                    proc(element, &walker_ctx.context);
                }

                switch (operation) {
                    .single => {
                        walker_ctx.found_element = element;
                        return Action.STOP.toU32();
                    },
                    .multiple => {
                        walker_ctx.results.append(element) catch {};
                        return Action.CONTINUE.toU32();
                    },
                    .process => {
                        return Action.CONTINUE.toU32();
                    },
                }
            }

            return Action.CONTINUE.toU32();
        }
    }.callback;
}

/// Simple getElementById wrapper - returns single element or null
/// Uses fast walker, no allocation needed
pub fn getElementById(doc: *z.HtmlDocument, id: []const u8) !?*z.DomElement {
    return getElementByIdFast(doc, id);
}

/// Simple getElementsByClass wrapper - returns owned slice
/// Caller must free the returned slice
pub fn getElementsByClass(allocator: std.mem.Allocator, doc: *z.HtmlDocument, class_name: []const u8) ![]const *z.DomElement {
    const root_node = z.documentRoot(doc) orelse return &[_]*z.DomElement{};

    const result = try getByComptime(allocator, root_node, .{
        .target_attr = "class",
        .target_value = class_name,
        .mode = .multiple,
    });

    return switch (result) {
        .multiple => |elements| elements, // Caller owns this slice
        else => &[_]*z.DomElement{}, // Return empty slice for non-multiple results
    };
}

/// Simple getElementsByAttribute wrapper - returns owned slice
///
/// Caller must free the returned slice
pub fn getElementsByAttribute(allocator: std.mem.Allocator, doc: *z.HtmlDocument, attr_name: []const u8, attr_value: ?[]const u8) ![]const *z.DomElement {
    const root_node = z.documentRoot(doc) orelse return &[_]*z.DomElement{};

    const result = try getByComptime(allocator, root_node, .{
        .target_attr = attr_name,
        .target_value = attr_value,
        .mode = .multiple,
    });

    return switch (result) {
        .multiple => |elements| elements, // Caller owns this slice
        else => &[_]*z.DomElement{}, // Return empty slice
    };
}

//==================================================================
// ENHANCED GENERIC WALKER EXAMPLES
//==================================================================

// /// Example: Find element by ID using generic walker
// pub fn getElementByIdGeneric(doc: *z.HtmlDocument, id: []const u8) !?*z.DomElement {
//     const IdContext = struct {
//         target_id: []const u8,
//     };

//     const predicate = struct {
//         fn check(element: *z.DomElement, context: *IdContext) bool {
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
pub fn removeMatchingAttribute(allocator: std.mem.Allocator, root_node: *z.DomNode, attr_pattern: []const u8) !u16 {
    const rmCtx = WalkSpec{
        .target_attr = attr_pattern,
        .target_value = null,
        .data = 0,
    };

    const matchAll = struct {
        fn check(element: *z.DomElement, context: WalkSpec) bool {
            _ = element; // All elements are processed
            _ = context; // All elements are processed
            return true; // Process all elements
        }
    }.check;

    const process = struct {
        fn run(element: *z.DomElement, context: WalkSpec) void {
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
pub fn getElementsByTagName(allocator: std.mem.Allocator, doc: *z.HtmlDocument, tag: z.HtmlTag) ![]const *z.DomElement {
    const spec = WalkSpec{
        .target_tag = tag,
        .target_attr = "",
    };

    const predicate = struct {
        fn check(element: *z.DomElement, context: WalkSpec) bool {
            const element_tag = z.tagFromElement(element);
            return context.target_tag == element_tag;
        }
    }.check;

    const root_node = z.documentRoot(doc) orelse return &[_]*z.DomElement{};

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

/// Example: Add class to all elements matching a condition
pub fn addClassToElements(doc: *z.HtmlDocument, condition_attr: []const u8, new_class: []const u8) !u32 {
    const AddClassContext = struct {
        condition_attr: []const u8,
        new_class: []const u8,
        modified_count: u32 = 0,
        allocator: std.mem.Allocator,
    };

    const predicate = struct {
        fn check(element: *z.DomElement, context: *AddClassContext) bool {
            return z.hasAttribute(element, context.condition_attr);
        }
    }.check;

    const processor = struct {
        fn process(element: *z.DomElement, context: *AddClassContext) void {
            // Check if element already has this class to avoid duplicates
            if (z.hasClass(element, context.new_class)) {
                return; // Already has the class, skip
            }

            // Get current class value
            const current_class = z.getAttribute_zc(element, "class") orelse "";

            // Create new class value by appending the new class
            var new_class_value = std.ArrayList(u8).init(context.allocator);
            defer new_class_value.deinit();

            if (current_class.len > 0) {
                new_class_value.appendSlice(current_class) catch return;
                new_class_value.append(' ') catch return;
            }
            new_class_value.appendSlice(context.new_class) catch return;

            // Set the updated class attribute
            const new_value = new_class_value.toOwnedSlice() catch return;
            defer context.allocator.free(new_value);

            z.setAttributes(element, &[_]z.AttributePair{.{ .name = "class", .value = new_value }}) catch {};

            context.modified_count += 1;
        }
    }.process;

    const root_node = z.documentRoot(doc) orelse return 0;
    var walker_ctx = GenericWalkerContext(AddClassContext, .process).init(std.heap.page_allocator, .{
        .condition_attr = condition_attr,
        .new_class = new_class,
        .allocator = std.heap.page_allocator,
    });
    defer walker_ctx.deinit();

    const callback = genericWalker(AddClassContext, .process, predicate, processor);
    lxb_dom_node_simple_walk(root_node, callback, &walker_ctx);

    return walker_ctx.context.modified_count;
}

// -----------------------------------------------------------------

fn matcher(element: *z.DomElement, spec: WalkSpec) bool {
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
    results: std.ArrayList(*z.DomElement),
    result: ?[]const u8 = null, // for single element searches
    matcher: *const fn (*z.DomElement, WalkSpec) bool,
    processor: ?*const fn (*z.DomElement, WalkSpec) void,

    pub fn deinit(self: *WalkCtxType) void {
        self.results.deinit();
    }
};

fn compWalk(
    allocator: std.mem.Allocator,
    root_node: *z.DomNode,
    spec: WalkSpec,
    comptime predicate: *const fn (*z.DomElement, WalkSpec) bool,
    comptime processor: ?*const fn (*z.DomElement, WalkSpec) void,
) ![]*z.DomElement {
    var ctx = WalkCtxType{
        .spec = spec,
        .results = std.ArrayList(*z.DomElement).init(allocator),
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
    predicate: *const fn (*z.DomElement, WalkSpec) bool,
    processor: ?*const fn (*z.DomElement, WalkSpec) void,
) ![]*z.DomElement {
    var ctx = WalkCtxType{
        .spec = spec,
        .results = std.ArrayList(*z.DomElement).init(allocator),
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
) ![]*z.DomElement {
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
    single: ?*z.DomElement, // single element result
    multiple: []*z.DomElement, // multiple elements result
    all: void,
    err: []const u8,
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
    results: std.ArrayList(*z.DomElement),
    result: *z.DomElement,
};

const WalkerContextType = struct {
    spec: SearchSpec,
    results: std.ArrayList(*z.DomElement),
    result: ?*z.DomElement,
    predicate: *const fn (*z.DomElement, SearchSpec) bool,
    processor: ?*const fn (*z.DomElement, SearchSpec) void,

    pub fn deinit(self: *WalkerContextType) void {
        self.results.deinit();
    }
};

fn universalPredicate(element: *z.DomElement, spec: SearchSpec) bool {
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
    comptime predicate: *const fn (*z.DomElement, SearchSpec) bool,
    comptime processor: ?*const fn (*z.DomElement, SearchSpec) void,
) !WalkerContextType {
    var ctx = WalkerContextType{
        .spec = spec,
        .results = std.ArrayList(*z.DomElement).init(allocator), // ✅ Own the ArrayList
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
    predicate: *const fn (*z.DomElement, SearchSpec) bool,
    processor: ?*const fn (*z.DomElement, SearchSpec) void,
) ![]const *z.DomElement {
    var results = std.ArrayList(*z.DomElement).init(allocator);
    errdefer results.deinit(); // Clean up on error

    const RTWalkCtxType = struct {
        spec: SearchSpec,
        results: *std.ArrayList(*z.DomElement),
        predicate: *const fn (*z.DomElement, SearchSpec) bool,
        processor: ?*const fn (*z.DomElement, SearchSpec) void,
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

fn myPredicate(element: *z.DomElement, ctx: SearchSpec) bool {
    if (!z.hasAttribute(element, ctx.target_attr)) return false;
    if (std.mem.eql(u8, "id", ctx.target_attr)) {
        return z.hasElementId(element, ctx.target_value orelse return false);
    }
    const value = z.getAttribute_zc(element, ctx.target_attr) orelse return false;
    return std.mem.eql(u8, value, ctx.target_value.?);
}

fn myprocessor(element: *z.DomElement, ctx: SearchSpec) void {
    _ = element;
    _ = ctx;
    // Process the element as needed
}

fn getByRuntime(
    allocator: std.mem.Allocator,
    root_node: *z.DomNode,
    context: SearchSpec,
    predicate: *const fn (*z.DomElement, SearchSpec) bool,
    processor: ?*const fn (*z.DomElement, SearchSpec) void,
) ![]const *z.DomElement {
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

//==================================================================
// WALKER-BASED MULTIPLE RESULTS (Alternative to Collections)
//==================================================================

/// [attributes] Find ALL elements with specific class using walker (alternative to collection)
///
/// This is a walker-based alternative to the collection-based getElementsByClassName.
/// Potentially faster for large DOMs as it avoids collection overhead.
///
/// Caller must free the returned slice.
pub fn getElementsByClassWalker(allocator: std.mem.Allocator, doc: *z.HtmlDocument, class_name: []const u8) ![]const *z.DomElement {
    const root_node = z.documentRoot(doc) orelse return &[_]*z.DomElement{};

    var search_ctx = MultiElementSearchContext{
        .target_attr_name = undefined, // Not used for class search
        .target_attr_value = undefined, // Not used for class search
        .target_class = class_name,
        .search_type = .class,
        .allocator = allocator,
        .results = std.ArrayList(*z.DomElement).init(allocator),
    };
    defer search_ctx.results.deinit();

    lxb_dom_node_simple_walk(root_node, multiElementAttributeWalkerCallback, &search_ctx);

    return search_ctx.results.toOwnedSlice();
}

/// [attributes] Find ALL elements with specific attribute using walker (alternative to collection)
///
/// This is a walker-based alternative to collection-based attribute searching.
/// Can search by attribute existence (attr_value = null) or specific values.
///
/// Caller must free the returned slice.
pub fn getElementsByAttributeWalker(allocator: std.mem.Allocator, doc: *z.HtmlDocument, attr_name: []const u8, attr_value: ?[]const u8) ![]const *z.DomElement {
    const root_node = z.documentRoot(doc) orelse return &[_]*z.DomElement{};

    var search_ctx = MultiElementSearchContext{
        .target_attr_name = attr_name,
        .target_attr_value = attr_value,
        .target_class = undefined, // Not used for attribute search
        .search_type = .attribute,
        .allocator = allocator,
        .results = std.ArrayList(*z.DomElement).init(allocator),
    };
    defer search_ctx.results.deinit();

    lxb_dom_node_simple_walk(root_node, multiElementAttributeWalkerCallback, &search_ctx);

    return search_ctx.results.toOwnedSlice();
}

/// [attributes] Find ALL elements with specific data-* attribute using walker
///
/// Convenience wrapper for data attribute searching.
/// Example: getElementsByDataAttributeWalker(allocator, doc, "category", "tech")
///          finds all elements with data-category="tech"
///
/// Caller must free the returned slice.
pub fn getElementsByDataAttributeWalker(allocator: std.mem.Allocator, doc: *z.HtmlDocument, data_name: []const u8, value: ?[]const u8) ![]const *z.DomElement {
    // Build the full data attribute name
    var attr_name_buffer: [256]u8 = undefined;
    const attr_name = try std.fmt.bufPrint(attr_name_buffer[0..], "data-{s}", .{data_name});

    return getElementsByAttributeWalker(allocator, doc, attr_name, value);
}

// ----------------------------------------------------------
// TESTS
// ----------------------------------------------------------

test "element / attribute  name & value" {
    const allocator = testing.allocator;

    const html = "<div class='test' id='my-id' data-value='123' title='tooltip' hidden>Content</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const body_node = try z.bodyNode(doc);
    const div = z.firstChild(body_node).?;
    const div_elt = z.nodeToElement(div).?;

    // Get ID attribute from an element
    const id = try z.getElementId(allocator, div_elt);
    defer allocator.free(id);
    try testing.expectEqualStrings(id, "my-id");

    // Get class attribute from an element using unified classList
    const class_result = try z.classList(allocator, div_elt, .string);
    const class = class_result.string;
    defer allocator.free(class);
    try testing.expectEqualStrings(class, "test");

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

test "optimized walker-based search functions" {
    // Create a comprehensive test document
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

    // Test 1: getElementByIdFast - should find elements by ID
    const header = try getElementByIdFast(doc, "header");
    try testing.expect(header != null);
    try testing.expectEqualStrings("DIV", z.tagName_zc(header.?));

    const content = try getElementByIdFast(doc, "content");
    try testing.expect(content != null);
    try testing.expectEqualStrings("MAIN", z.tagName_zc(content.?));

    const footer = try getElementByIdFast(doc, "footer");
    try testing.expect(footer != null);
    try testing.expectEqualStrings("FOOTER", z.tagName_zc(footer.?));

    // Test 2: getElementByClassFast - should find first element with class
    const nav_link = try getElementByClassFast(doc, "nav-link");
    try testing.expect(nav_link != null);
    try testing.expectEqualStrings("A", z.tagName_zc(nav_link.?));

    const post = try getElementByClassFast(doc, "post");
    try testing.expect(post != null);
    try testing.expectEqualStrings("ARTICLE", z.tagName_zc(post.?));

    const widget = try getElementByClassFast(doc, "widget");
    try testing.expect(widget != null);
    try testing.expectEqualStrings("DIV", z.tagName_zc(widget.?));

    // Test 3: getElementByAttributeFast - attribute existence only
    const href_element = try getElementByAttributeFast(doc, "href", null);
    try testing.expect(href_element != null);
    try testing.expectEqualStrings("A", z.tagName_zc(href_element.?));

    // Test 4: getElementByAttributeFast - attribute with specific value
    const home_link = try getElementByAttributeFast(doc, "href", "/home");
    try testing.expect(home_link != null);
    try testing.expectEqualStrings("A", z.tagName_zc(home_link.?));

    const about_link = try getElementByAttributeFast(doc, "href", "/about");
    try testing.expect(about_link != null);
    try testing.expectEqualStrings("A", z.tagName_zc(about_link.?));

    // Test 5: getElementByDataAttributeFast - data attributes
    const header_section = try getElementByDataAttributeFast(doc, "data", "section", "header");
    try testing.expect(header_section != null);
    try testing.expectEqualStrings("DIV", z.tagName_zc(header_section.?));

    const home_page = try getElementByDataAttributeFast(doc, "data", "page", "home");
    try testing.expect(home_page != null);
    try testing.expectEqualStrings("A", z.tagName_zc(home_page.?));

    const tech_article = try getElementByDataAttributeFast(doc, "data", "category", "tech");
    try testing.expect(tech_article != null);
    try testing.expectEqualStrings("ARTICLE", z.tagName_zc(tech_article.?));

    // Test custom prefix functionality (phx- instead of data-)
    const content_section = try getElementByDataAttributeFast(doc, "phx", "section", "content");
    try testing.expect(content_section != null);
    try testing.expectEqualStrings("MAIN", z.tagName_zc(content_section.?));

    // Test 6: Non-existent searches should return null
    const missing_id = try getElementByIdFast(doc, "nonexistent");
    try testing.expect(missing_id == null);

    const missing_class = try getElementByClassFast(doc, "nonexistent-class");
    try testing.expect(missing_class == null);

    const missing_attr = try getElementByAttributeFast(doc, "nonexistent-attr", "value");
    try testing.expect(missing_attr == null);

    const missing_data = try getElementByDataAttributeFast(doc, "nonexistent", "data", "value");
    try testing.expect(missing_data == null);
}

test "walker-based search vs existing implementations comparison" {
    const allocator = testing.allocator;

    const html =
        \\<div class="container">
        \\  <p id="paragraph1" class="text intro">First paragraph</p>
        \\  <span class="text highlight" data-priority="high">Important text</span>
        \\  <div class="box" data-type="info">Info box</div>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Compare ID search methods
    const element_fast = try getElementByIdFast(doc, "paragraph1");
    const element_collection = try z.getElementById(doc, "paragraph1");

    try testing.expect(element_fast != null);
    try testing.expect(element_collection != null);
    try testing.expect(element_fast.? == element_collection.?);

    // Test class search - walker vs manual iteration
    const class_fast = try getElementByClassFast(doc, "text");
    try testing.expect(class_fast != null);
    try testing.expectEqualStrings("P", z.tagName_zc(class_fast.?));

    // Verify the found element actually has the class
    try testing.expect(z.hasClass(class_fast.?, "text"));

    // Test data attribute search
    const data_element = try getElementByDataAttributeFast(doc, "data", "priority", "high");
    try testing.expect(data_element != null);
    try testing.expectEqualStrings("SPAN", z.tagName_zc(data_element.?));

    // Verify the data attribute value using allocator
    if (try z.getAttribute(allocator, data_element.?, "data-priority")) |priority| {
        defer allocator.free(priority);
        try testing.expectEqualStrings("high", priority);
    }

    // Test content verification using allocator
    const content = try z.getTextContent(allocator, z.elementToNode(data_element.?));
    defer allocator.free(content);
    try testing.expectEqualStrings("Important text", content);
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

//     // std.debug.print("\n📊 Summary:\n", .{});
//     // std.debug.print("• Walker: Better for CSS classes (token-based)\n", .{});
//     // std.debug.print("• Collection: Better for exact attribute values\n", .{});
//     // std.debug.print("• Walker: Better for single-element searches (early exit)\n", .{});
//     // std.debug.print("• Collection: Better for bulk operations on known large result sets\n", .{});
// }

test "getElementById vs getElementByIdFast comparison" {
    const allocator = testing.allocator;

    const html = "<div><p id='test-element'>Hello World</p></div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test that both methods find the same element
    const element_fast = try getElementByIdFast(doc, "test-element");
    const element_collection = try z.getElementById(doc, "test-element");

    try testing.expect(element_fast != null);
    try testing.expect(element_collection != null);

    // They should be the same element (same memory address)
    try testing.expect(element_fast.? == element_collection.?);

    // Verify content is correct
    const text = try z.getTextContent(allocator, z.elementToNode(element_fast.?));
    defer allocator.free(text);
    try testing.expectEqualStrings("Hello World", text);
}

test "getElementById performance comparison" {
    const allocator = testing.allocator;

    // Create a larger document with many elements to see performance difference
    var html_buffer = std.ArrayList(u8).init(allocator);
    defer html_buffer.deinit();

    const writer = html_buffer.writer();
    try writer.writeAll("<html><body>");

    // Add many elements before the target
    for (0..1000) |i| {
        try writer.print("<div class='element-{}'>Element {}</div>", .{ i, i });
    }

    // Add target element near the end
    try writer.writeAll("<p id='target-element'>This is the target</p>");

    // Add some more elements after target
    for (0..100) |i| {
        try writer.print("<span class='after-{}'>After {}</span>", .{ i, i });
    }

    try writer.writeAll("</body></html>");

    const html = try html_buffer.toOwnedSlice();
    defer allocator.free(html);

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test both methods find the same element
    const fast_result = try getElementByIdFast(doc, "target-element");
    const collection_result = try z.getElementById(doc, "target-element");

    try testing.expect(fast_result != null);
    try testing.expect(collection_result != null);
    try testing.expect(fast_result.? == collection_result.?);

    // Verify we found the correct element
    const content = try z.getTextContent(allocator, z.elementToNode(fast_result.?));
    defer allocator.free(content);
    try testing.expectEqualStrings("This is the target", content);

    // print("✅ Both methods found the same element with {} total DOM nodes\n", .{1101});
}

test "elementHasNamedAttribute - isolated test" {
    const html = "<div id='test-div' class='example'>Simple content</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const body_node = z.elementToNode(body);
    const div_node = z.firstChild(body_node).?;
    const div_element = z.nodeToElement(div_node).?;

    // print("\n=== Testing elementHasNamedAttribute in isolation ===\n", .{});

    // Test basic functionality
    // print("Testing 'id' attribute...\n", .{});
    const has_id = z.hasAttribute(div_element, "id");
    try testing.expect(has_id);
    // print("✅ Has 'id' attribute: {}\n", .{has_id});

    // print("Testing 'class' attribute...\n", .{});
    const has_class = z.hasAttribute(div_element, "class");
    try testing.expect(has_class);
    // print("✅ Has 'class' attribute: {}\n", .{has_class});

    // print("Testing 'missing' attribute...\n", .{});
    const has_missing = z.hasAttribute(div_element, "missing");
    try testing.expect(!has_missing);
    // print("✅ Has 'missing' attribute: {}\n", .{has_missing});

    // print("✅ elementHasNamedAttribute isolated test passed!\n", .{});
}

// test "enhanced generic walker - single element search" {
//     const html =
//         \\<div>
//         \\  <p id="target">Target paragraph</p>
//         \\  <span id="other">Other element</span>
//         \\</div>
//     ;

//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     // Test generic ID search
//     const result = try getElementByIdGeneric(doc, "target");
//     try testing.expect(result != null);
//     try testing.expectEqualStrings("P", z.tagName_zc(result.?));

//     // Test non-existent ID
//     const missing = try getElementByIdGeneric(doc, "missing");
//     try testing.expect(missing == null);
// }

// test "enhanced generic walker - attribute removal" {
//     const allocator = testing.allocator;

//     const html =
//         \\<div data-test="1" class="example" data-id="123">
//         \\  <span data-value="abc" title="tooltip" data-category="tech">Content</span>
//         \\  <p class="text" style="color: red;">Paragraph</p>
//         \\</div>
//     ;

//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     // Remove all data-* attributes
//     const removed_count = try removeAttributesMatching(doc, "data-");
//     try testing.expect(removed_count == 4); // data-test, data-id, data-value, data-category

//     // Verify attributes were removed
//     const body = try z.bodyElement(doc);
//     const first_child = z.firstChild(z.elementToNode(body));
//     try testing.expect(first_child != null);
//     const div = z.nodeToElement(first_child.?).?;

//     // Should still have class but not data-* attributes
//     try testing.expect(z.hasAttribute(div, "class"));
//     try testing.expect(!z.hasAttribute(div, "data-test"));
//     try testing.expect(!z.hasAttribute(div, "data-id"));

//     // Check serialized output doesn't contain data attributes
//     const body_node = try z.bodyNode(doc);
//     const html_output = try z.serializeToString(allocator, body_node);
//     defer allocator.free(html_output);
//     try testing.expect(std.mem.indexOf(u8, html_output, "data-") == null);
// }

// test "enhanced generic walker - modify elements" {
//     const html =
//         \\<div>
//         \\  <p data-highlight="true">Paragraph 1</p>
//         \\  <span>Normal span</span>
//         \\  <div data-highlight="false">Div with data</div>
//         \\  <p data-highlight="true">Paragraph 2</p>
//         \\</div>
//     ;

//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     // Add 'highlighted' class to all elements with data-highlight attribute
//     const modified_count = try addClassToElements(doc, "data-highlight", "highlighted");
//     try testing.expect(modified_count == 3);

//     // Verify that at least one element with data-highlight has the class
//     // Use our search function to find an element with data-highlight
//     const highlighted_element = try getElementByAttributeFast(doc, "data-highlight", null);
//     try testing.expect(highlighted_element != null);
//     try testing.expect(z.hasClass(highlighted_element.?, "highlighted"));
// }

test "compile-time walkers - single element search" {
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
    const element_by_id = getElementByIdComptime("target", doc);
    try testing.expect(element_by_id != null);
    const id_text = try z.getTextContent(allocator, z.elementToNode(element_by_id.?));
    defer allocator.free(id_text);
    try testing.expect(std.mem.eql(u8, id_text, "Target paragraph"));

    // Test compile-time class search with compile-time known string
    const element_by_class = getElementByClassComptime("highlight", doc);
    try testing.expect(element_by_class != null);
    try testing.expect(z.hasClass(element_by_class.?, "highlight"));

    // Test compile-time tag search
    const element_by_tag = getElementByTagComptime(.span, doc);
    try testing.expect(element_by_tag != null);
    try testing.expect(z.tagFromElement(element_by_tag.?) == .span);
}

test "compile-time walkers - multiple element search" {
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
    const elements_by_class = try getElementsByClassComptime("highlight", allocator, doc);
    defer allocator.free(elements_by_class);
    try testing.expect(elements_by_class.len == 3);

    // Verify all found elements have the class
    for (elements_by_class) |element| {
        try testing.expect(z.hasClass(element, "highlight"));
    }

    // Test compile-time tag search (multiple) with correct parameter order
    const elements_by_tag = try getElementsByTagComptime(.p, allocator, doc);
    defer allocator.free(elements_by_tag);
    try testing.expect(elements_by_tag.len == 2);

    // Verify all found elements are paragraphs
    for (elements_by_tag) |element| {
        try testing.expect(z.tagFromElement(element) == .p);
    }
}
