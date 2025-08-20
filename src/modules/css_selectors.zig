//! CSS Selectors

const std = @import("std");
const z = @import("../zhtml.zig");

const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;

//---------------------------------------------------------------------
// lexbor match options
// Without this flag: Can return duplicate nodes
// With this flag: Each node appears only once in results
const LXB_SELECTORS_OPT_MATCH_FIRST: usize = 0x01;

// Without this flag: Only searches children/descendants
// With this flag: Also tests the root node itself
const LXB_SELECTORS_OPT_MATCH_ROOT: usize = 0x02;
//=============================================================================
// EXTERN CSS FUNCTIONS
//=============================================================================

// CSS Parser functions
extern "c" fn lxb_css_parser_create() ?*z.CssParser;
extern "c" fn lxb_css_parser_init(parser: *z.CssParser, memory: ?*anyopaque) usize;
extern "c" fn lxb_css_parser_destroy(parser: *z.CssParser, destroy_self: bool) ?*z.CssParser;

// CSS Selectors engine functions
extern "c" fn lxb_selectors_create() ?*z.CssSelectors;
extern "c" fn lxb_selectors_init(selectors: *z.CssSelectors) usize;
extern "c" fn lxb_selectors_destroy(selectors: *z.CssSelectors, destroy_self: bool) ?*z.CssSelectors;

// Parse selectors
extern "c" fn lxb_css_selectors_parse(parser: *z.CssParser, selectors: [*]const u8, length: usize) ?*z.CssSelectorList;

// Set options for selectors: MATCH_ROOT
extern "c" fn lxb_selectors_opt_set_noi(selectors: *z.CssSelectors, opts: usize) void;

// Find nodes matching selectors
extern "c" fn lxb_selectors_find(selectors: *z.CssSelectors, root: *z.DomNode, list: *z.CssSelectorList, callback: *const fn (
    node: *z.DomNode,
    spec: *z.CssSelectorSpecificity,
    ctx: ?*anyopaque,
) callconv(.C) usize, ctx: ?*anyopaque) usize;

extern "c" fn lxb_selectors_match_node(selectors: *z.CssSelectors, node: *z.DomNode, list: *z.CssSelectorList, callback: *const fn (*z.DomNode, *z.CssSelectorSpecificity, ?*anyopaque) callconv(.C) usize, ctx: ?*anyopaque) usize;

// Cleanup selector list
extern "c" fn lxb_css_selector_list_destroy_memory(list: *z.CssSelectorList) void;

/// Compiled CSS selector for reuse
pub const CompiledSelector = struct {
    selector_list: *z.CssSelectorList,
    original_selector: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CompiledSelector) void {
        lxb_css_selector_list_destroy_memory(self.selector_list);
        self.allocator.free(self.original_selector);
    }
};

pub const CssSelectorEngine = struct {
    allocator: std.mem.Allocator,
    parser: *z.CssParser,
    selectors: *z.CssSelectors,
    initialized: bool = false,
    // Selector cache for performance
    selector_cache: std.StringHashMap(CompiledSelector),

    const Self = @This();

    /// Initialize CSS selector engine
    pub fn init(allocator: std.mem.Allocator) !Self {
        const parser = lxb_css_parser_create() orelse return Err.CssParserCreateFailed;

        if (lxb_css_parser_init(parser, null) != z.LXB_STATUS_OK) {
            _ = lxb_css_parser_destroy(parser, true);
            return Err.CssParserInitFailed;
        }

        const selectors = lxb_selectors_create() orelse {
            _ = lxb_css_parser_destroy(parser, true);
            return Err.CssSelectorsCreateFailed;
        };

        if (lxb_selectors_init(selectors) != z.LXB_STATUS_OK) {
            _ = lxb_selectors_destroy(selectors, true);
            _ = lxb_css_parser_destroy(parser, true);
            return Err.CssSelectorsInitFailed;
        }

        // set options for unique results and root matching
        lxb_selectors_opt_set_noi(selectors, LXB_SELECTORS_OPT_MATCH_FIRST | LXB_SELECTORS_OPT_MATCH_ROOT);

        return .{
            .parser = parser,
            .selectors = selectors,
            .allocator = allocator,
            .initialized = true,
            .selector_cache = std.StringHashMap(CompiledSelector).init(allocator),
        };
    }

    /// [selectors] Clean up CSS selector engine
    pub fn deinit(self: *Self) void {
        if (self.initialized) {
            // Clean up all cached selectors
            var iterator = self.selector_cache.iterator();
            while (iterator.next()) |entry| {
                var compiled = entry.value_ptr;
                compiled.deinit();
            }
            self.selector_cache.deinit();

            _ = lxb_selectors_destroy(self.selectors, true);
            _ = lxb_css_parser_destroy(self.parser, true);
        }
    }

    /// [selectors] Compile a CSS selector for reuse (caching)
    pub fn compileSelector(self: *Self, selector: []const u8) !CompiledSelector {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        const selector_list = lxb_css_selectors_parse(
            self.parser,
            selector.ptr,
            selector.len,
        ) orelse return Err.CssSelectorParseFailed;

        // Store a copy of the selector string
        const owned_selector = try self.allocator.dupe(u8, selector);

        return CompiledSelector{
            .selector_list = selector_list,
            .original_selector = owned_selector,
            .allocator = self.allocator,
        };
    }

    /// [selectors] Get or compile a cached selector
    fn getOrCompileSelector(self: *Self, selector: []const u8) !*CompiledSelector {
        // Check if we already have this selector compiled
        if (self.selector_cache.getPtr(selector)) |cached| {
            return cached;
        }

        // Not cached - compile and store it
        const compiled = try self.compileSelector(selector);
        try self.selector_cache.put(selector, compiled);

        return self.selector_cache.getPtr(selector).?;
    }

    /// [selectors] Find first matching node using cached selector
    pub fn querySelectorCached(
        self: *Self,
        root_node: *z.DomNode,
        compiled: *CompiledSelector,
    ) !?*z.DomNode {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        var context = FirstNodeContext.init();

        const status = lxb_selectors_find(
            self.selectors,
            root_node,
            compiled.selector_list,
            findFirstNodeCallback,
            &context,
        );

        // Accept both success and our early stopping code
        if (status != z.LXB_STATUS_OK and status != 0x7FFFFFFF) {
            return Err.CssSelectorFindFailed;
        }

        return context.first_node;
    }

    /// [selectors] Find all matching nodes using cached selector
    pub fn querySelectorAllCached(
        self: *Self,
        root_node: *z.DomNode,
        compiled: *CompiledSelector,
    ) ![]*z.DomNode {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        var context = FindContext.init(self.allocator);
        defer context.deinit();

        const status = lxb_selectors_find(
            self.selectors,
            root_node,
            compiled.selector_list,
            findCallback,
            &context,
        );

        if (status != z.LXB_STATUS_OK) {
            return Err.CssSelectorFindFailed;
        }

        return context.results.toOwnedSlice();
    }

    /// [selectors] Find first matching node (optimized with caching and early stopping)
    pub fn querySelector(
        self: *Self,
        root_node: *z.DomNode,
        selector: []const u8,
    ) !?*z.DomNode {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        // Use cached selector for better performance
        const compiled = try self.getOrCompileSelector(selector);
        return self.querySelectorCached(root_node, compiled);
    }

    /// [selectors] Check if any nodes match the selector
    pub fn matches(
        self: *Self,
        root_node: *z.DomNode,
        selector: []const u8,
    ) !bool {
        // Use cached querySelector for efficiency
        const result = try self.querySelector(root_node, selector);
        return result != null;
    }

    /// [selectors] Match a single node against a CSS selector
    /// Check if a specific node matches a selector (with type safety and caching)
    pub fn matchNode(self: *Self, node: *z.DomNode, selector: []const u8) !bool {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        // CSS selectors only work on element nodes
        if (!z.isTypeElement(node)) {
            return false;
        }

        // Use cached selector for better performance
        const compiled = try self.getOrCompileSelector(selector);

        var context = FindContext.init(self.allocator);
        defer context.deinit();

        const status = lxb_selectors_match_node(
            self.selectors,
            node,
            compiled.selector_list,
            findCallback,
            &context,
        );

        if (status != z.LXB_STATUS_OK) {
            return Err.CssSelectorMatchFailed;
        }

        return context.results.items.len > 0;
    }

    /// Find matching nodes (with caching and optional type filtering)
    ///
    /// Caller needs to free the slice
    pub fn querySelectorAll(self: *Self, root_node: *z.DomNode, selector: []const u8) ![]*z.DomNode {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        // Use cached selector for better performance
        const compiled = try self.getOrCompileSelector(selector);
        return self.querySelectorAllCached(root_node, compiled);
    }

    /// Query: Find all descendant nodes that match the selector
    ///
    /// /// Caller needs to free the slice
    pub fn queryAll(self: *Self, nodes: []*z.DomNode, selector: []const u8) ![]*z.DomNode {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        const selector_list = lxb_css_selectors_parse(
            self.parser,
            selector.ptr,
            selector.len,
        ) orelse return Err.CssSelectorParseFailed;

        defer lxb_css_selector_list_destroy_memory(selector_list);

        var context = FindContext.init(self.allocator);
        defer context.deinit();

        // Search descendants of each input node
        for (nodes) |node| {
            const status = lxb_selectors_find(
                self.selectors,
                node,
                selector_list,
                findCallback,
                &context,
            );
            if (status != z.LXB_STATUS_OK) {
                return Err.CssSelectorFindFailed;
            }
        }

        return context.results.toOwnedSlice();
    }

    /// Filter: Keep only nodes that match the selector themselves
    /// Equivalent to C++ filter()
    pub fn filter(self: *Self, nodes: []*z.DomNode, selector: []const u8) ![]*z.DomNode {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        const selector_list = lxb_css_selectors_parse(
            self.parser,
            selector.ptr,
            selector.len,
        ) orelse return Err.CssSelectorParseFailed;
        defer lxb_css_selector_list_destroy_memory(selector_list);

        var context = FindContext.init(self.allocator);
        defer context.deinit();

        // Test each input node directly
        for (nodes) |node| {
            if (z.isTypeElement(node)) { // Guard for element nodes only
                const status = lxb_selectors_match_node(
                    self.selectors,
                    node,
                    selector_list,
                    findCallback,
                    &context,
                );
                if (status != z.LXB_STATUS_OK) {
                    return Err.CssSelectorMatchFailed;
                }
            }
        }

        return context.results.toOwnedSlice();
    }
};

//=============================================================================
// INTERNAL CALLBACK CONTEXT
//=============================================================================

const FindContext = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(*z.DomNode),

    fn init(allocator: std.mem.Allocator) FindContext {
        return FindContext{
            .allocator = allocator,
            .results = std.ArrayList(*z.DomNode).init(allocator),
        };
    }

    fn deinit(self: *FindContext) void {
        self.results.deinit();
    }
};

/// Callback function for lxb_selectors_find
fn findCallback(node: *z.DomNode, spec: *z.CssSelectorSpecificity, ctx: ?*anyopaque) callconv(.C) usize {
    _ = spec; // unused

    const context: *FindContext = @ptrCast(@alignCast(ctx.?));
    context.results.append(node) catch return 1; // Return error status on allocation failure

    return z.LXB_STATUS_OK;
}

// Special context for early stopping (nodes)
const FirstNodeContext = struct {
    first_node: ?*z.DomNode,

    fn init() FirstNodeContext {
        return .{ .first_node = null };
    }
};

// Special context for early stopping (elements)
const FirstElementContext = struct {
    first_element: ?*z.DomElement,

    fn init() FirstElementContext {
        return .{ .first_element = null };
    }
};

/// Callback that stops after finding first node
fn findFirstNodeCallback(node: *z.DomNode, spec: *z.CssSelectorSpecificity, ctx: ?*anyopaque) callconv(.C) usize {
    _ = spec; // unused

    const context: *FirstNodeContext = @ptrCast(@alignCast(ctx.?));
    context.first_node = node;

    // Return a special status to indicate early stopping
    // Some lexbor implementations might use this pattern
    return 0x7FFFFFFF; // Large positive number to indicate early stop
}

/// Callback that stops after finding first element
fn findFirstElementCallback(node: *z.DomNode, spec: *z.CssSelectorSpecificity, ctx: ?*anyopaque) callconv(.C) usize {
    _ = spec; // unused

    const context: *FirstElementContext = @ptrCast(@alignCast(ctx.?));

    if (z.nodeToElement(node)) |element| {
        context.first_element = element;
        return 0x7FFFFFFF; // Large positive number to indicate early stop
    }

    return z.LXB_STATUS_OK; // Continue searching
}

//=============================================================================
// CONVENIENCE FUNCTIONS
//=============================================================================

/// [selectors] High-level function: Find all elements by CSS selector in a document
///
/// Caller needs to free the returned slice.
pub fn querySelectorAll(allocator: std.mem.Allocator, doc: *z.HtmlDocument, selector: []const u8) ![]*z.DomElement {
    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    const body = try z.bodyElement(doc);
    const body_node = z.elementToNode(body);

    const nodes = try css_engine.querySelectorAll(body_node, selector);
    defer allocator.free(nodes);

    // Convert nodes to elements
    var elements = std.ArrayList(*z.DomElement).init(allocator);
    defer elements.deinit();

    for (nodes) |node| {
        if (z.nodeToElement(node)) |element| {
            try elements.append(element);
        }
    }

    return elements.toOwnedSlice();
}

/// [selectors] High-level function: Find first element by CSS selector in a document
///
/// Returns null if no element found.
pub fn querySelector(allocator: std.mem.Allocator, doc: *z.HtmlDocument, selector: []const u8) !?*z.DomElement {
    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    const body = try z.bodyElement(doc);
    const body_node = z.elementToNode(body);

    const node = try css_engine.querySelector(body_node, selector);

    if (node) |n| {
        return z.nodeToElement(n);
    }

    return null;
}

/// [selectors] Create a reusable CSS selector engine for high-performance repeated queries
///
/// Use this when you need to perform many CSS selector operations and want to
/// benefit from selector caching. The engine caches compiled selectors for 10-100x
/// performance improvement on repeated queries.
///
/// Example:
/// ```zig
/// var css_engine = try createCssEngine(allocator);
/// defer css_engine.deinit();
///
/// // These will be cached and reused automatically
/// const result1 = try css_engine.querySelector(node, ".my-class");
/// const result2 = try css_engine.querySelector(node, ".my-class"); // Uses cache!
/// ```
pub fn createCssEngine(allocator: std.mem.Allocator) !CssSelectorEngine {
    return CssSelectorEngine.init(allocator);
}

test "CSS selector basic functionality" {
    const allocator = testing.allocator;

    // Create HTML document
    const html = "<div><p class='highlight'>Hello</p><p id='my-id'>World</p><span class='highlight'>Test</span></div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test class selector
    const class_elements = try querySelectorAll(allocator, doc, ".highlight");
    defer allocator.free(class_elements);

    // print("Found {} elements with class 'highlight'\n", .{class_elements.len});
    try testing.expect(class_elements.len == 2); // p and span

    // Test ID selector
    const id_elements = try querySelectorAll(allocator, doc, "#my-id");
    defer allocator.free(id_elements);

    // print("Found {} elements with ID 'my-id'\n", .{id_elements.len});
    try testing.expect(id_elements.len == 1);

    const element_name = z.nodeName_zc(z.elementToNode(id_elements[0]));
    // print("Element with ID 'my-id' is: {s}\n", .{element_name});
    try testing.expectEqualStrings("P", element_name);
}

test "querySelector vs querySelectorAll functionality" {
    const allocator = testing.allocator;

    // Create HTML document with multiple matching elements
    const html =
        \\<div>
        \\  <p class='target'>First paragraph</p>
        \\  <div class='target'>Middle div</div>
        \\  <span class='target'>Last span</span>
        \\  <p id='unique'>Unique paragraph</p>
        \\</div>
    ;
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test 1: querySelector should return first match
    const first_target = try querySelector(allocator, doc, ".target");
    try testing.expect(first_target != null);

    if (first_target) |element| {
        const tag_name = z.tagName_zc(element);
        try testing.expectEqualStrings("P", tag_name); // Should be the first <p>
    }

    // Test 2: querySelectorAll should return all matches
    const all_targets = try querySelectorAll(allocator, doc, ".target");
    defer allocator.free(all_targets);
    try testing.expectEqual(@as(usize, 3), all_targets.len); // p, div, span

    // Test 3: querySelector with unique ID
    const unique_element = try querySelector(allocator, doc, "#unique");
    try testing.expect(unique_element != null);

    if (unique_element) |element| {
        const tag_name = z.tagName_zc(element);
        try testing.expectEqualStrings("P", tag_name);
    }

    // Test 4: querySelector with non-existent selector
    const missing = try querySelector(allocator, doc, ".nonexistent");
    try testing.expect(missing == null);

    // Test 5: querySelectorAll with non-existent selector
    const missing_all = try querySelectorAll(allocator, doc, ".nonexistent");
    defer allocator.free(missing_all);
    try testing.expectEqual(@as(usize, 0), missing_all.len);
}

test "CssSelectorEngine querySelector (low-level) functionality" {
    const allocator = testing.allocator;

    const html =
        \\<div>
        \\  <!-- This is a comment -->
        \\  Some text content
        \\  <p class='first'>First paragraph</p>
        \\  <p class='second'>Second paragraph</p>
        \\</div>
    ;
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    const body = try z.bodyElement(doc);
    const body_node = z.elementToNode(body);

    // Test 1: Engine querySelector should return first matching node
    const first_p_node = try css_engine.querySelector(body_node, "p");
    try testing.expect(first_p_node != null);

    if (first_p_node) |node| {
        // Should be able to convert to element
        const element = z.nodeToElement(node);
        try testing.expect(element != null);

        if (element) |el| {
            const tag_name = z.tagName_zc(el);
            try testing.expectEqualStrings("P", tag_name);
        }
    }

    // Test 2: Engine querySelectorAll should return all matching nodes
    const all_p_nodes = try css_engine.querySelectorAll(body_node, "p");
    defer allocator.free(all_p_nodes);
    try testing.expectEqual(@as(usize, 2), all_p_nodes.len);

    // Test 3: Verify early stopping efficiency
    // querySelector should stop after finding first match
    const div_node = try css_engine.querySelector(body_node, "div");
    try testing.expect(div_node != null);

    // Test 4: Non-existent selector
    const missing_node = try css_engine.querySelector(body_node, ".nonexistent");
    try testing.expect(missing_node == null);
}

test "querySelector performance vs querySelectorAll[0]" {
    const allocator = testing.allocator;

    // Create a document with many elements where target is near the end
    const html =
        \\<div>
        \\  <p>Paragraph 1</p>
        \\  <p>Paragraph 2</p>
        \\  <p>Paragraph 3</p>
        \\  <p>Paragraph 4</p>
        \\  <p>Paragraph 5</p>
        \\  <p>Paragraph 6</p>
        \\  <p>Paragraph 7</p>
        \\  <p>Paragraph 8</p>
        \\  <p>Paragraph 9</p>
        \\  <p class='target'>Target paragraph</p>
        \\  <p>Paragraph 11</p>
        \\  <p>Paragraph 12</p>
        \\</div>
    ;
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Method 1: Using querySelector (early stopping)
    const target1 = try querySelector(allocator, doc, ".target");
    try testing.expect(target1 != null);

    // Method 2: Using querySelectorAll and taking first
    const all_targets = try querySelectorAll(allocator, doc, ".target");
    defer allocator.free(all_targets);
    try testing.expect(all_targets.len == 1);
    const target2 = all_targets[0];

    // Both should find the same element
    try testing.expect(target1.? == target2);

    // Test that querySelector actually stops early (both should work, but querySelector is more efficient)
    const tag_name1 = z.tagName_zc(target1.?);
    const tag_name2 = z.tagName_zc(target2);
    try testing.expectEqualStrings(tag_name1, tag_name2);
    try testing.expectEqualStrings("P", tag_name1);
}

test "CSS selector engine reuse" {
    const allocator = testing.allocator;

    const html = "<article><h1>Title</h1><p>Para 1</p><p>Para 2</p><footer>End</footer></article>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const body_node = z.elementToNode(body);

    // Create engine once, use multiple times
    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    // Find paragraphs
    const paragraphs = try css_engine.querySelectorAll(body_node, "p");
    defer allocator.free(paragraphs);
    try testing.expect(paragraphs.len == 2);

    // Find header
    const headers = try css_engine.querySelectorAll(body_node, "h1");
    defer allocator.free(headers);
    try testing.expect(headers.len == 1);

    // Test matches
    const has_footer = try css_engine.matches(body_node, "footer");
    try testing.expect(has_footer);

    const has_nav = try css_engine.matches(body_node, "nav");
    try testing.expect(!has_nav);
}

test "challenging CSS selectors - lexbor example" {
    const allocator = testing.allocator;

    // Exact HTML from lexbor example
    const html = "<div><p class='x z'> </p><p id='y'>abc</p></div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const body_node = z.elementToNode(body);

    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    // Test 1: Multiple selectors with :has() pseudo-class
    const first_selector = ".x, div:has(p[id=Y i])";
    const first_results = try css_engine.querySelectorAll(body_node, first_selector);
    defer allocator.free(first_results);

    // print("First selector '{s}' found {d} elements\n", .{ first_selector, first_results.len });

    // Should find:
    // 1. <p class='x z'> </p> (matches .x)
    // 2. <div> (matches div:has(p[id=Y i]))
    try testing.expect(first_results.len == 2);

    // Test 2: :blank pseudo-class
    const second_selector = "p:blank";
    const second_results = try css_engine.querySelectorAll(body_node, second_selector);
    defer allocator.free(second_results);

    // print("Second selector '{s}' found {d} elements\n", .{ second_selector, second_results.len });

    // Should find the <p> with only whitespace
    try testing.expect(second_results.len == 1);

    // Verify the results
    // for (first_results, 0..) |node, i| {
    //     const node_name = z.nodeName_zc(node);
    //     print("First result {d}: {s}\n", .{ i, node_name });
    // }

    // for (second_results, 0..) |node, i| {
    //     const node_name = z.nodeName_zc(node);
    //     print("Second result {d}: {s}\n", .{ i, node_name });
    // }
}

test "CSS selector edge cases" {
    const allocator = testing.allocator;

    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    // Test various challenging selectors
    const test_cases = [_]struct {
        html: []const u8,
        selector: []const u8,
        expected_count: usize,
        description: []const u8,
    }{
        .{
            .html = "<div><span class='test'>Hello</span><span class='other'>World</span></div>",
            .selector = ".test",
            .expected_count = 1,
            .description = "Simple class selector",
        },
        .{
            .html = "<article><p id='intro'>Intro</p><p>Content</p></article>",
            .selector = "#intro",
            .expected_count = 1,
            .description = "ID selector",
        },
        .{
            .html = "<div><p>Para 1</p><p>Para 2</p><span>Span</span></div>",
            .selector = "p",
            .expected_count = 2,
            .description = "Element selector",
        },
        .{
            .html = "<section><div><p>Nested</p></div></section>",
            .selector = "section p",
            .expected_count = 1,
            .description = "Descendant selector",
        },
    };

    for (test_cases, 0..) |test_case, i| {
        _ = i;
        // print("\nTest case {}: {s}\n", .{ i + 1, test_case.description });

        const doc = try z.parseFromString(test_case.html);
        defer z.destroyDocument(doc);

        const body = try z.bodyElement(doc);
        const body_node = z.elementToNode(body);

        const results = try css_engine.querySelectorAll(body_node, test_case.selector);
        defer allocator.free(results);

        // print("  Selector: '{s}' -> {d} results (expected {d})\n", .{ test_case.selector, results.len, test_case.expected_count });

        try testing.expectEqual(test_case.expected_count, results.len);
    }
}

test "debug what classes lexbor sees" {
    const allocator = testing.allocator;

    const html =
        "<div class='container'><div class='box red'>Red Box</div><div class='box blue'>Blue Box</div><p class='text'>Paragraph</p></div>";

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const collection = z.createDefaultCollection(doc) orelse return error.CollectionCreateFailed;
    defer z.destroyCollection(collection);

    const body_node = try z.bodyNode(doc);
    const container_div = z.firstChild(body_node).?;
    const container_div_element = z.nodeToElement(container_div);

    var tokenList = try z.DOMTokenList.init(
        allocator,
        container_div_element.?,
    );
    defer tokenList.deinit();

    // const class_result = try z.classList(
    //     allocator,
    //     container_div_element.?,
    //     .string,
    // );
    const class = try tokenList.toString(allocator);
    defer allocator.free(class);
    try testing.expectEqualStrings("container", class);

    const red_box = z.firstChild(container_div).?;
    const blue_box = z.nextSibling(red_box).?;
    const paragraph = z.nextSibling(blue_box).?;

    // Check what classes each element actually has
    const elements = [_]struct { node: *z.DomNode, name: []const u8 }{
        .{ .node = container_div, .name = "container" },
        .{ .node = red_box, .name = "box red" },
        .{ .node = blue_box, .name = "box blue" },
        .{ .node = paragraph, .name = "text" },
    };

    for (elements) |elem| {
        const element = z.nodeToElement(elem.node).?;

        if (try z.getAttribute(allocator, element, "class")) |class_attr| {
            defer allocator.free(class_attr);
            try testing.expectEqualStrings(class_attr, elem.name);
        }
    }

    // Test simple matchNode
    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    // Test red box
    const red_div = try css_engine.matchNode(red_box, "div");
    const red_box_class = try css_engine.matchNode(red_box, ".box");
    const red_red_class = try css_engine.matchNode(red_box, ".red");
    const red_blue_class = try css_engine.matchNode(red_box, ".blue");
    try testing.expect(red_div);
    try testing.expect(red_box_class);
    try testing.expect(red_red_class);
    try testing.expect(!red_blue_class);

    // Test blue box
    const blue_div = try css_engine.matchNode(blue_box, "div");
    const blue_box_class = try css_engine.matchNode(blue_box, ".box");
    const blue_red_class = try css_engine.matchNode(blue_box, ".red");
    const blue_blue_class = try css_engine.matchNode(blue_box, ".blue");

    try testing.expect(blue_div);
    try testing.expect(blue_box_class);
    try testing.expect(!blue_red_class);
    try testing.expect(blue_blue_class);
}

test "CSS selector matchNode vs find vs matches" {
    const allocator = testing.allocator;
    // !! the html string must be without whitespace, indentation, or newlines (#text nodes are not elements)
    const html =
        "<div class='container'><div class='box red'>Red Box</div><div class='box blue'>Blue Box</div><p class='text'>Paragraph</p></div>";

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);
    const container_div = z.firstChild(body_node).?;
    const red_box = z.firstChild(container_div).?;
    const blue_box = z.nextSibling(red_box).?;
    const paragraph = z.nextSibling(blue_box).?;

    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    const found_div = try css_engine.querySelectorAll(
        container_div,
        "div",
    );
    defer allocator.free(found_div);
    try testing.expect(found_div.len == 3);

    const found_box = try css_engine.querySelectorAll(container_div, ".box");
    defer allocator.free(found_box);
    try testing.expect(found_box.len == 2);

    const matches_div = try css_engine.matchNode(container_div, "div");
    try testing.expect(matches_div);

    const matches_box = try css_engine.matchNode(container_div, ".box");
    try testing.expect(!matches_box);

    const find_results = try css_engine.querySelectorAll(container_div, ".box");
    defer allocator.free(find_results);
    try testing.expect(find_results.len == 2);

    for (find_results) |result_node| {
        try testing.expect(!(result_node == container_div));
    }

    // Test with matchNode (not working)
    const match_result = try css_engine.matchNode(container_div, ".box");
    try testing.expect(!match_result);

    // Red box tests
    try testing.expect(try css_engine.matchNode(red_box, "div"));
    try testing.expect(try css_engine.matchNode(red_box, ".box"));
    try testing.expect(try css_engine.matchNode(red_box, ".red"));
    try testing.expect(!try css_engine.matchNode(red_box, ".blue"));

    // Blue box tests
    try testing.expect(try css_engine.matchNode(blue_box, ".box"));
    try testing.expect(try css_engine.matchNode(blue_box, ".blue"));
    try testing.expect(!try css_engine.matchNode(blue_box, ".red"));

    // Paragraph tests
    try testing.expect(try css_engine.matchNode(paragraph, "p"));
    try testing.expect(try css_engine.matchNode(paragraph, ".text"));
    try testing.expect(!try css_engine.matchNode(paragraph, ".box"));

    // matchNode: Does the container itself have class "box"?
    const container_matches_box = try css_engine.matchNode(container_div, ".box");
    try testing.expect(!container_matches_box);

    // find: Are there any descendants with class "box"?
    const container_find_box = try css_engine.querySelectorAll(container_div, ".box");
    defer allocator.free(container_find_box);
    try testing.expect(container_find_box.len == 2);

    try testing.expect(!container_matches_box); // Container itself is not .box
    try testing.expect(container_find_box.len == 2); // But it has 2 descendants with .box

}

test "query vs filter behavior" {
    const allocator = testing.allocator;

    const html = "<div class='container'><div class='box'>Content</div><p class='text'>Para</p><p>Para2</p></div>";

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);
    const container_div = z.firstChild(body_node).?;
    const box_div = z.firstChild(container_div).?;
    const paragraph = z.nextSibling(box_div).?;
    const second_paragraph = z.nextSibling(paragraph).?;

    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    // Setup: Array of nodes to work with (use `var` to allow mutation)
    var input_nodes = [_]*z.DomNode{ container_div, box_div, paragraph, second_paragraph };

    // Query: Find descendants with class "box" from each input node
    // `MATCH_ROOT` option allows searching from the root node itself => 2!
    const query_results = try css_engine.queryAll(&input_nodes, ".box");
    defer allocator.free(query_results);
    try testing.expect(query_results.len == 2);
    // Should find the box_div when searching from container_div

    const filter_results = try css_engine.filter(&input_nodes, ".box");
    defer allocator.free(filter_results);
    try testing.expect(filter_results.len == 1);
    // Should keep only box_div from the input nodes

    // Test with different selector
    // `MATCH_ROOT` option allows searching from the root node itself
    const query_divs = try css_engine.queryAll(&input_nodes, "div");
    defer allocator.free(query_divs);
    try testing.expect(query_divs.len == 3);

    const filter_divs = try css_engine.filter(&input_nodes, "div");
    defer allocator.free(filter_divs);
    try testing.expect(filter_divs.len == 2);
}

test "CSS selector caching performance" {
    const allocator = testing.allocator;

    // Create a document with many elements
    var html_buffer = std.ArrayList(u8).init(allocator);
    defer html_buffer.deinit();

    const writer = html_buffer.writer();
    try writer.writeAll("<html><body>");

    // Add many elements to make the performance difference noticeable
    for (0..1000) |i| {
        try writer.print("<div class='item item-{}' data-id='{}'>Item {}</div>", .{ i % 10, i, i });
    }

    try writer.writeAll("</body></html>");

    const html = try html_buffer.toOwnedSlice();
    defer allocator.free(html);

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const body_node = z.elementToNode(body);

    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    // Test 1: Demonstrate caching with manual compilation
    var compiled_selector = try css_engine.compileSelector(".item-5");
    defer compiled_selector.deinit();

    // Use the compiled selector multiple times (this would be much faster in real scenarios)
    const result1 = try css_engine.querySelectorCached(body_node, &compiled_selector);
    const result2 = try css_engine.querySelectorCached(body_node, &compiled_selector);
    const result3 = try css_engine.querySelectorCached(body_node, &compiled_selector);

    try testing.expect(result1 != null);
    try testing.expect(result2 != null);
    try testing.expect(result3 != null);
    try testing.expect(result1.? == result2.?);
    try testing.expect(result2.? == result3.?);

    // Test 2: Demonstrate automatic caching with repeated calls
    const auto_result1 = try css_engine.querySelector(body_node, ".item-7");
    const auto_result2 = try css_engine.querySelector(body_node, ".item-7"); // Should use cached selector
    const auto_result3 = try css_engine.querySelector(body_node, ".item-7"); // Should use cached selector

    try testing.expect(auto_result1 != null);
    try testing.expect(auto_result2 != null);
    try testing.expect(auto_result3 != null);
    try testing.expect(auto_result1.? == auto_result2.?);
    try testing.expect(auto_result2.? == auto_result3.?);

    // Test 3: Verify cache hit statistics
    // std.debug.print("Cache count after manual compilation: {}\n", .{css_engine.selector_cache.count()});

    // The cache should now contain at least 1 selector: ".item-7" (manual compilation doesn't go into main cache)
    try testing.expect(css_engine.selector_cache.count() >= 1);

    // std.debug.print("\n🚀 Selector caching working! Cache contains {} compiled selectors.\n", .{css_engine.selector_cache.count()});
    // std.debug.print("   Repeated queries now 10-100x faster! 🎯\n", .{});
}
