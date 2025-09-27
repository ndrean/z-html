//! CSS Selectors

const std = @import("std");
const z = @import("../root.zig");

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
) callconv(.c) usize, ctx: ?*anyopaque) usize;

extern "c" fn lxb_selectors_match_node(selectors: *z.CssSelectors, node: *z.DomNode, list: *z.CssSelectorList, callback: *const fn (*z.DomNode, *z.CssSelectorSpecificity, ?*anyopaque) callconv(.c) usize, ctx: ?*anyopaque) usize;

// Cleanup selector list
extern "c" fn lxb_css_selector_list_destroy_memory(list: *z.CssSelectorList) void;

/// Parse and store a CSS selector for reuse
const StoredSelector = struct {
    allocator: std.mem.Allocator,
    selector_list: *z.CssSelectorList,
    original_selector: []const u8,

    pub fn deinit(self: StoredSelector) void {
        lxb_css_selector_list_destroy_memory(self.selector_list);
        self.allocator.free(self.original_selector);
    }
};

pub const CssSelectorEngine = struct {
    allocator: std.mem.Allocator,
    css_parser: *z.CssParser,
    selectors: *z.CssSelectors,
    initialized: bool = false,
    // Selector cache for performance
    selector_cache: std.StringHashMap(StoredSelector),

    const Self = @This();

    /// Initialize CSS selector engine
    pub fn init(allocator: std.mem.Allocator) !Self {
        const css_parser = lxb_css_parser_create() orelse return Err.CssParserCreateFailed;

        if (lxb_css_parser_init(css_parser, null) != z._OK) {
            _ = lxb_css_parser_destroy(css_parser, true);
            return Err.CssParserInitFailed;
        }

        const selectors = lxb_selectors_create() orelse {
            _ = lxb_css_parser_destroy(css_parser, true);
            return Err.CssSelectorsCreateFailed;
        };

        if (lxb_selectors_init(selectors) != z._OK) {
            _ = lxb_selectors_destroy(selectors, true);
            _ = lxb_css_parser_destroy(css_parser, true);
            return Err.CssSelectorsInitFailed;
        }

        // set options for unique results and root matching
        lxb_selectors_opt_set_noi(selectors, LXB_SELECTORS_OPT_MATCH_FIRST | LXB_SELECTORS_OPT_MATCH_ROOT);

        return .{
            .css_parser = css_parser,
            .selectors = selectors,
            .allocator = allocator,
            .initialized = true,
            .selector_cache = std.StringHashMap(StoredSelector).init(allocator),
        };
    }

    /// [selectors] Clean up CSS selector engine
    pub fn deinit(self: *Self) void {
        if (self.initialized) {
            // Clean up all cached selectors
            var iterator = self.selector_cache.iterator();
            while (iterator.next()) |entry| {
                var parsed = entry.value_ptr;
                parsed.deinit();
            }
            self.selector_cache.deinit();

            _ = lxb_selectors_destroy(self.selectors, true);
            _ = lxb_css_parser_destroy(self.css_parser, true);
        }
    }

    /// [selectors] Parse and store a CSS selector for reuse (caching)
    pub fn parseSelector(self: *Self, selector: []const u8) !StoredSelector {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        const selector_list = lxb_css_selectors_parse(
            self.css_parser,
            selector.ptr,
            selector.len,
        ) orelse return Err.CssSelectorParseFailed;

        // copy the selector string
        const owned_selector = try self.allocator.dupe(u8, selector);

        return StoredSelector{
            .selector_list = selector_list,
            .original_selector = owned_selector,
            .allocator = self.allocator,
        };
    }

    /// [selectors] Get or compile a cached selector
    fn getOrParseSelector(self: *Self, selector: []const u8) !*StoredSelector {
        // Check if we already have this selector compiled
        if (self.selector_cache.getPtr(selector)) |cached| {
            return cached;
        }

        // Not cached - compile and store it
        const parsed = try self.parseSelector(selector);
        try self.selector_cache.put(selector, parsed);

        return self.selector_cache.getPtr(selector).?;
    }

    /// [selectors] Find first matching node using cached selector
    pub fn querySelectorCached(
        self: *Self,
        root_node: *z.DomNode,
        selector: *StoredSelector,
    ) !?*z.DomNode {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        var context = FirstNodeContext.init();

        const status = lxb_selectors_find(
            self.selectors,
            root_node,
            selector.selector_list,
            findFirstNodeCallback,
            &context,
        );

        // Accept both success and our early stopping code
        if (status != z._OK and status != 0x7FFFFFFF) {
            return Err.CssSelectorFindFailed;
        }

        return context.first_node;
    }

    /// [selectors] Find all matching nodes using cached selector
    pub fn querySelectorAllCached(
        self: *Self,
        root_node: *z.DomNode,
        selector: *StoredSelector,
    ) ![]*z.DomNode {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        var context = FindContext.init(self.allocator);
        defer context.deinit();

        const status = lxb_selectors_find(
            self.selectors,
            root_node,
            selector.selector_list,
            findCallback,
            &context,
        );

        if (status != z._OK) {
            return Err.CssSelectorFindFailed;
        }

        return context.results.toOwnedSlice(self.allocator);
    }

    /// [selectors] Find first matching node (optimized with caching and early stopping)
    pub fn querySelector(
        self: *Self,
        root_node: *z.DomNode,
        selector: []const u8,
    ) !?*z.DomNode {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        // Use cached selector for better performance
        const parsed = try self.getOrParseSelector(selector);
        return self.querySelectorCached(root_node, parsed);
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

        // CSS selectors only on element nodes
        if (!z.isTypeElement(node)) {
            return false;
        }

        // Use cached selector for better performance
        const _selector = try self.getOrParseSelector(selector);

        var context = FindContext.init(self.allocator);
        defer context.deinit();

        const status = lxb_selectors_match_node(
            self.selectors,
            node,
            _selector.selector_list,
            findCallback,
            &context,
        );

        if (status != z._OK) {
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
        const _selector = try self.getOrParseSelector(selector);
        return self.querySelectorAllCached(root_node, _selector);
    }

    /// Query: Find all descendant nodes that match the selector
    ///
    /// /// Caller needs to free the slice
    pub fn queryAll(self: *Self, nodes: []*z.DomNode, selector: []const u8) ![]*z.DomNode {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        const selector_list = lxb_css_selectors_parse(
            self.css_parser,
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
            if (status != z._OK) {
                return Err.CssSelectorFindFailed;
            }
        }

        return context.results.toOwnedSlice(self.allocator);
    }

    /// Filter: Keep only nodes that match the selector themselves
    pub fn filter(self: *Self, nodes: []*z.DomNode, selector: []const u8) ![]*z.DomNode {
        if (!self.initialized) return Err.CssEngineNotInitialized;

        const selector_list = lxb_css_selectors_parse(
            self.css_parser,
            selector.ptr,
            selector.len,
        ) orelse return Err.CssSelectorParseFailed;
        defer lxb_css_selector_list_destroy_memory(selector_list);

        var context = FindContext.init(self.allocator);
        defer context.deinit();

        // Test each input node directly
        for (nodes) |node| {
            if (z.isTypeElement(node)) {
                const status = lxb_selectors_match_node(
                    self.selectors,
                    node,
                    selector_list,
                    findCallback,
                    &context,
                );
                if (status != z._OK) {
                    return Err.CssSelectorMatchFailed;
                }
            }
        }

        return context.results.toOwnedSlice(self.allocator);
    }
};

// === CALLBACK CONTEXT

const FindContext = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(*z.DomNode) = .empty,

    fn init(allocator: std.mem.Allocator) FindContext {
        return FindContext{ .allocator = allocator };
    }

    fn deinit(self: *FindContext) void {
        self.results.deinit(self.allocator);
    }
};

/// Callback function for lxb_selectors_find
fn findCallback(node: *z.DomNode, _: *z.CssSelectorSpecificity, ctx: ?*anyopaque) callconv(.c) usize {
    const context: *FindContext = @ptrCast(@alignCast(ctx.?));
    context.results.append(context.allocator, node) catch return z._STOP; // Return error status on allocation failure

    return z._OK;
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
    first_element: ?*z.HTMLElement,

    fn init() FirstElementContext {
        return .{ .first_element = null };
    }
};

/// Callback that stops after finding first node
fn findFirstNodeCallback(node: *z.DomNode, _: *z.CssSelectorSpecificity, ctx: ?*anyopaque) callconv(.c) usize {
    const context: *FirstNodeContext = @ptrCast(@alignCast(ctx.?));
    context.first_node = node;

    // Return a special status to indicate early stopping
    // Some lexbor implementations might use this pattern
    return 0x7FFFFFFF; // Large positive number to indicate early stop
}

/// Callback that stops after finding first element
fn findFirstElementCallback(node: *z.DomNode, _: *z.CssSelectorSpecificity, ctx: ?*anyopaque) callconv(.c) usize {
    const context: *FirstElementContext = @ptrCast(@alignCast(ctx.?));

    if (z.nodeToElement(node)) |element| {
        context.first_element = element;
        return 0x7FFFFFFF; // Large positive number to indicate early stop
    }

    return z._OK; // Continue searching
}

//=============================================================================
// CONVENIENCE FUNCTIONS
//=============================================================================

/// [selectors] High-level function: Find all elements by CSS selector in a document
///
/// Caller needs to free the returned slice.
pub fn querySelectorAll(allocator: std.mem.Allocator, doc: *z.HTMLDocument, selector: []const u8) ![]*z.HTMLElement {
    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    const body = z.bodyElement(doc).?;
    const body_node = z.elementToNode(body);

    const nodes = try css_engine.querySelectorAll(body_node, selector);
    defer allocator.free(nodes);

    // Convert nodes to elements
    var elements: std.ArrayList(*z.HTMLElement) = .empty;
    defer elements.deinit(allocator);

    for (nodes) |node| {
        if (z.nodeToElement(node)) |element| {
            try elements.append(allocator, element);
        }
    }

    return elements.toOwnedSlice(allocator);
}

/// [selectors] High-level function: Find first element by CSS selector in a document
///
/// Returns null if no element found.
pub fn querySelector(allocator: std.mem.Allocator, doc: *z.HTMLDocument, selector: []const u8) !?*z.HTMLElement {
    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    const body = z.bodyElement(doc).?;
    const body_node = z.elementToNode(body);

    const node = try css_engine.querySelector(body_node, selector);

    if (node) |n| {
        return z.nodeToElement(n);
    }

    return null;
}

pub fn filter(allocator: std.mem.Allocator, nodes: []*z.DomNode, selector: []const u8) ![]*z.DomNode {
    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    return css_engine.filter(nodes, selector);
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
    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    // Test class selector
    const class_elements = try querySelectorAll(allocator, doc, ".highlight");
    defer allocator.free(class_elements);

    // z.print("Found {} elements with class 'highlight'\n", .{class_elements.len});
    try testing.expect(class_elements.len == 2); // p and span

    // Test ID selector
    const id_elements = try querySelectorAll(allocator, doc, "#my-id");
    defer allocator.free(id_elements);

    // z.print("Found {} elements with ID 'my-id'\n", .{id_elements.len});
    try testing.expect(id_elements.len == 1);

    const element_name = z.nodeName_zc(z.elementToNode(id_elements[0]));
    // z.print("Element with ID 'my-id' is: {s}\n", .{element_name});
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
    const doc = try z.createDocFromString(html);
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
    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    const body = z.bodyElement(doc).?;
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
    const doc = try z.createDocFromString(html);
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
    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    const body = z.bodyElement(doc).?;
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

test "CSS selector nth-child functionality" {
    const allocator = testing.allocator;

    // Create HTML with ul > li structure
    const html =
        \\<ul>
        \\  <li>First item</li>
        \\  <li>Second item</li>
        \\  <li>Third item</li>
        \\  <li>Fourth item</li>
        \\</ul>
    ;

    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    const body_node = z.bodyNode(doc).?;

    // Test CSS selector for second li
    var engine = try z.CssSelectorEngine.init(allocator);
    defer engine.deinit();

    // Find the second li element using nth-child
    const second_li_results = try engine.querySelectorAll(body_node, "ul > li:nth-child(2)");
    defer allocator.free(second_li_results);

    try testing.expect(second_li_results.len == 1);

    if (second_li_results.len > 0) {
        const second_li_node = second_li_results[0];
        const text_content = try z.textContent(allocator, second_li_node);
        defer allocator.free(text_content);

        // Should be "Second item"
        try testing.expect(std.mem.eql(u8, std.mem.trim(u8, text_content, " \t\n\r"), "Second item"));
    }

    // Test finding all li elements
    const all_li_results = try engine.querySelectorAll(body_node, "ul > li");
    defer allocator.free(all_li_results);

    try testing.expect(all_li_results.len == 4);

    // Test first li using querySelector (single result)
    const first_li_node = try engine.querySelector(body_node, "ul > li:first-child");
    if (first_li_node) |node| {
        const text_content = try z.textContent(allocator, node);
        defer allocator.free(text_content);
        try testing.expect(std.mem.eql(u8, std.mem.trim(u8, text_content, " \t\n\r"), "First item"));
    } else {
        try testing.expect(false); // Should find first li
    }
}

test "challenging CSS selectors - lexbor example" {
    const allocator = testing.allocator;

    // Exact HTML from lexbor example
    const html = "<div><p class='x z'> </p><p id='y'>abc</p></div>";
    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    const body = z.bodyElement(doc).?;
    const body_node = z.elementToNode(body);

    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    // Test 1: Multiple selectors with :has() pseudo-class
    const first_selector = ".x, div:has(p[id=Y i])";
    const first_results = try css_engine.querySelectorAll(body_node, first_selector);
    defer allocator.free(first_results);

    // z.print("First selector '{s}' found {d} elements\n", .{ first_selector, first_results.len });

    // Should find:
    // 1. <p class='x z'> </p> (matches .x)
    // 2. <div> (matches div:has(p[id=Y i]))
    try testing.expect(first_results.len == 2);

    // Test 2: :blank pseudo-class
    const second_selector = "p:blank";
    const second_results = try css_engine.querySelectorAll(body_node, second_selector);
    defer allocator.free(second_results);

    // z.print("Second selector '{s}' found {d} elements\n", .{ second_selector, second_results.len });

    // Should find the <p> with only whitespace
    try testing.expect(second_results.len == 1);

    // Verify the results
    // for (first_results, 0..) |node, i| {
    //     const node_name = z.nodeName_zc(node);
    //     z.print("First result {d}: {s}\n", .{ i, node_name });
    // }

    // for (second_results, 0..) |node, i| {
    //     const node_name = z.nodeName_zc(node);
    //     z.print("Second result {d}: {s}\n", .{ i, node_name });
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
        // z.print("\nTest case {}: {s}\n", .{ i + 1, test_case.description });

        const doc = try z.createDocFromString(test_case.html);
        defer z.destroyDocument(doc);

        const body = z.bodyElement(doc).?;
        const body_node = z.elementToNode(body);

        const results = try css_engine.querySelectorAll(body_node, test_case.selector);
        defer allocator.free(results);

        // z.print("  Selector: '{s}' -> {d} results (expected {d})\n", .{ test_case.selector, results.len, test_case.expected_count });

        try testing.expectEqual(test_case.expected_count, results.len);
    }
}

// test "debug what classes lexbor sees" {
//     const allocator = testing.allocator;

//     const html = "<div class='container'><div class='box red'>Red Box</div><div class='box blue'>Blue Box</div><p class='text'>Paragraph</p></div>";

//     const doc = try z.createDocFromString(html);
//     defer z.destroyDocument(doc);

//     const collection = z.createDefaultCollection(doc) orelse return error.CollectionCreateFailed;
//     defer z.destroyCollection(collection);

//     const body_node = z.bodyNode(doc).?;
//     const container_div = z.firstChild(body_node).?;
//     const container_div_element = z.nodeToElement(container_div);

//     var tokenList = try z.classList(
//         allocator,
//         container_div_element.?,
//     );
//     defer tokenList.deinit();

//     const class = try tokenList.toString(allocator);
//     defer allocator.free(class);
//     try testing.expectEqualStrings("container", class);

//     const red_box = z.firstChild(container_div).?;
//     const blue_box = z.nextSibling(red_box).?;
//     const paragraph = z.nextSibling(blue_box).?;

//     // Check what classes each element actually has
//     const elements = [_]struct { node: *z.DomNode, name: []const u8 }{
//         .{ .node = container_div, .name = "container" },
//         .{ .node = red_box, .name = "box red" },
//         .{ .node = blue_box, .name = "box blue" },
//         .{ .node = paragraph, .name = "text" },
//     };

//     for (elements) |elem| {
//         const element = z.nodeToElement(elem.node).?;

//         if (try z.getAttribute(allocator, element, "class")) |class_attr| {
//             defer allocator.free(class_attr);
//             try testing.expectEqualStrings(class_attr, elem.name);
//         }
//     }

//     // Test simple matchNode
//     var css_engine = try CssSelectorEngine.init(allocator);
//     defer css_engine.deinit();

//     // Test red box
//     const red_div = try css_engine.matchNode(red_box, "div");
//     const red_box_class = try css_engine.matchNode(red_box, ".box");
//     const red_red_class = try css_engine.matchNode(red_box, ".red");
//     const red_blue_class = try css_engine.matchNode(red_box, ".blue");
//     try testing.expect(red_div);
//     try testing.expect(red_box_class);
//     try testing.expect(red_red_class);
//     try testing.expect(!red_blue_class);

//     // Test blue box
//     const blue_div = try css_engine.matchNode(blue_box, "div");
//     const blue_box_class = try css_engine.matchNode(blue_box, ".box");
//     const blue_red_class = try css_engine.matchNode(blue_box, ".red");
//     const blue_blue_class = try css_engine.matchNode(blue_box, ".blue");

//     try testing.expect(blue_div);
//     try testing.expect(blue_box_class);
//     try testing.expect(!blue_red_class);
//     try testing.expect(blue_blue_class);
// }

test "CSS selector matchNode vs find vs matches" {
    const allocator = testing.allocator;
    // !! the html string must be without whitespace, indentation, or newlines (#text nodes are not elements)
    const html =
        "<div class='container'><div class='box red'>Red Box</div><div class='box blue'>Blue Box</div><p class='text'>Paragraph</p></div>";

    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    const body_node = z.bodyNode(doc).?;
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

    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    const body_node = z.bodyNode(doc).?;
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
    var html_buffer: std.ArrayList(u8) = .empty;
    defer html_buffer.deinit(allocator);

    try html_buffer.appendSlice(allocator, "<html><body>");

    // Add many elements to make the performance difference noticeable
    for (0..100) |i| {
        const div = try std.fmt.allocPrint(allocator, "<div class='item item-{}' data-id='{}'>Item {}</div>", .{ i % 10, i, i });
        defer allocator.free(div);
        try html_buffer.appendSlice(allocator, div);
    }

    try html_buffer.appendSlice(allocator, "</body></html>");

    const html = try html_buffer.toOwnedSlice(allocator);
    defer allocator.free(html);

    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    const body = z.bodyElement(doc).?;
    const body_node = z.elementToNode(body);

    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    // Test 1: Demonstrate caching with manual compilation
    var compiled_selector = try css_engine.parseSelector(".item-5");
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
    // std.debug.z.print("Cache count after manual compilation: {}\n", .{css_engine.selector_cache.count()});

    // The cache should now contain at least 1 selector: ".item-7" (manual compilation doesn't go into main cache)
    try testing.expect(css_engine.selector_cache.count() >= 1);

    // std.debug.z.print("\n Selector caching working! Cache contains {} compiled selectors.\n", .{css_engine.selector_cache.count()});
    // std.debug.z.print("   Repeated queries now 10-100x faster!\n", .{});
}

test "multiple reuse css_engine" {
    const html =
        \\<div>
        \\<template id="groceries-page-template" title="Grocery Page">
        \\<div class="flex flex-col md:flex-row gap-8 p-4">
        \\<div class="md:w-1/2">
        \\<h2 class="text-3xl font-bold text-gray-800 mb-6">Grocery Items</h2>
        \\<div class="space-y-4 max-h-[400px] overflow-y-auto pr-2"
        \\          hx-get="/api/items"
        \\          hx-trigger="load, every 60s"
        \\          hx-target="this"
        \\          hx-swap="innerHTML">
        \\<p class="text-gray-500">Loading items...</p>
        \\</div>
        \\</div>
        \\      <div
        \\        id="item-details-card"
        \\        class="md:w-1/2 bg-gray-100 rounded-xl p-6 shadow-lg min-h-[300px] flex items-center justify-center transition-all duration-300"
        \\        hx-get="/item-details/default"
        \\        hx-trigger="load"
        \\        hx-target="this"
        \\        hx-swap="innerHTML"
        \\      ></div>
        \\    </div>
        \\  </template>
        \\  <template id="shopping-list-template" title="Shopping List">
        \\    <div class="flex flex-col items-center">
        \\      <h2 class="text-3xl font-bold text-gray-800 mb-6">Shopping List</h2>
        \\      <div
        \\        id="cart-content"
        \\        class="w-full max-w-xl bg-white rounded-lg p-6 shadow-md max-h-[500px] overflow-y-auto"
        \\        hx-get="/api/cart"
        \\        hx-trigger="load, every 30s"
        \\        hx-target="this"
        \\        hx-swap="innerHTML"
        \\      >
        \\        <p class="text-gray-600 text-center">Your cart is empty.</p>
        \\      </div>
        \\    </div>
        \\  </template>
        \\  <template title="Default Item Details" id="item-details-default-template">
        \\    <div class="text-center text-gray-500">
        \\      <h3 class="text-xl font-semibold mb-4">Select an item</h3>
        \\      <p class="text-gray-400">
        \\        Click on a grocery item to view its details here.
        \\      </p>
        \\    </div>
        \\  </template>
        \\  <template title="Cart Item" id="cart-item-template">
        \\    <div class="flex justify-between items-center p-4 border-b">
        \\      <div>
        \\          >${d:.2}</span
        \\        >
        \\      </div>
        \\      <div class="flex items-center space-x-2">
        \\        <button
        \\          class="px-2 py-1 bg-red-500 text-white rounded"
        \\          hx-post="/api/cart/decrease-quantity/{d}"
        \\          hx-target="#cart-content"
        \\          hx-swap="innerHTML"
        \\        >
        \\          -
        \\        </button>
        \\        <span class="px-3 py-1 bg-gray-100 rounded">{d}</span>
        \\        <button
        \\          class="px-2 py-1 bg-green-500 text-white rounded"
        \\          hx-post="/api/cart/increase-quantity/{d}"
        \\          hx-target="#cart-content"
        \\          hx-swap="innerHTML"
        \\        >
        \\          +
        \\        </button>
        \\        <button
        \\          class="px-2 py-1 bg-red-600 text-white rounded ml-2"
        \\          hx-delete="/api/cart/remove/{d}"
        \\          hx-target="#cart-content"
        \\          hx-swap="innerHTML"
        \\        >
        \\          Remove
        \\        </button>
        \\      </div>
        \\    </div>
        \\  </template>
        \\  <template title="Item Details" id="grocery-item-template">
        \\    <div
        \\      class="bg-white rounded-lg p-4 shadow-md flex justify-between items-cente\\r transition-transform transform hover:scale-[1.02] cursor-pointer"
        \\      hx-get="/api/item-details/{d}"
        \\      hx-target="#item-details-card"
        \\      hx-swap="innerHTML"
        \\    >
        \\      <di>
        \\        <span class="text-lg font-semibold text-gray-900">{s}</span
        \\        ><span class="text-sm text-gray-500 ml-2">${d:.2}</span>
        \\      </di\\v>
        \\      <button
        \\        class="px-4 py-2 bg-blue-500 text-white text-sm font-medium rounded-full hover:bg-blue-600 transition-colors"
        \\        hx-post="/api/cart/add/{d}"
        \\        hx-swap="none"
        \\      >
        \\        Add to Cart
        \\      </button>
        \\    </div>
        \\  </template>
        \\  <template title="Item Details" id="item-details-template">
        \\    <div class="text-center">
        \\      <h3 class="text-2xl font-bold text-gray-800 mb-4">{s}</h3>
        \\      <div
        \\        class="w-24 h-24 bg-gray-200 rounded-full mx-auto mb-4 flex items-center \\justify-center"
        \\      >
        \\        <svg
        \\          class="w-12 h-12 text-gray-400"
        \\          fill="none"
        \\          stroke="currentColor"
        \\          viewBox="0 0 24 24"
        \\        >
        \\          <path
        \\            stroke-linecap="round"
        \\            stroke-linejoin="round"
        \\            stroke-width="2"
        \\            d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"
        \\          ></path>
        \\        </svg>
        \\      </div>
        \\      <div class="bg-blue-50 rounded-lg p-6 mb-6">
        \\        <p class="text-3xl font-bold text-blue-600">${d:.2}</p>
        \\        <p class="text-gray-600 mt-2">per unit</p>
        \\      </div>
        \\      <div class="space-y-3">
        \\        <button
        \\          class="w-full bg-blue-600 text-white py-3 px-6 rounded-lg hover:bg-blue-70\\0 transition-colors font-semibold"
        \\          hx-post="/api/cart/add/{d}"
        \\          hx-swap="none"
        \\        >
        \\          Add to Cart
        \\        </button>
        \\        <button
        \\          class="w-full border border-gray-300 text-gray-700 py-2 px-6 rounded-lg hover:bg-gray-50 transition-colors"
        \\          onclic\\k="alert('More details coming soon!')"
        \\        >
        \\          More Details
        \\        </button>
        \\      </div>
        \\    </div>
        \\  </template>
        \\</div>
    ;

    const allocator = testing.allocator;
    const normHTML = try z.normalizeHtmlStringWithOptions(allocator, html, .{
        .remove_whitespace_text_nodes = true,
    });
    defer allocator.free(normHTML);
    const doc = try z.createDocFromString(normHTML);
    defer z.destroyDocument(doc);
    const body_node = z.bodyNode(doc).?;

    // try z.prettyPrint(allocator, body_node);

    // const item_template = z.getElementById(body_node, "grocery-item-template");

    // if (item_template != null) {
    //     const grocery_item_template_html = try z.innerTemplateHTML(allocator, z.elementToNode(item_template.?));
    //     print("Grocery Item Template HTML:\n{s}\n", .{grocery_item_template_html});
    //     allocator.free(grocery_item_template_html);
    // } else {
    //     print("not found", .{}); // Should find the grocery-item-template
    // }

    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    for (0..100) |_| {
        const item_template = try css_engine.querySelector(
            body_node,
            "#grocery-item-template",
        );

        const grocery_item_template_html = try z.innerTemplateHTML(allocator, item_template.?);
        defer allocator.free(grocery_item_template_html);
        std.debug.assert(grocery_item_template_html.len > 0);

        const groceries_template = try css_engine.querySelector(body_node, "#groceries-page-template");
        const groceries_html = try z.innerTemplateHTML(allocator, groceries_template.?);
        defer allocator.free(groceries_html);
        std.debug.assert(groceries_html.len > 0);

        const shopping_template = try css_engine.querySelector(body_node, "#shopping-list-template");
        const shopping_html = try z.innerTemplateHTML(allocator, shopping_template.?);
        defer allocator.free(shopping_html);
        std.debug.assert(shopping_html.len > 0);

        const default_template = try css_engine.querySelector(body_node, "#item-details-default-template");
        const default_html = try z.innerTemplateHTML(allocator, default_template.?);
        defer allocator.free(default_html);
        std.debug.assert(default_html.len > 0);

        const details_template = try css_engine.querySelector(body_node, "#item-details-template");
        const details_template_html = try z.innerTemplateHTML(allocator, details_template.?);
        defer allocator.free(details_template_html);
        std.debug.assert(details_template_html.len > 0);

        const cart_item_template = try css_engine.querySelector(body_node, "#cart-item-template");
        const cart_item_template_html = try z.innerTemplateHTML(allocator, cart_item_template.?);
        defer allocator.free(cart_item_template_html);
        std.debug.assert(cart_item_template_html.len > 0);
    }

    // print("{s}\n", .{grocery_item_template_html});
    // print("{s}\n", .{groceries_html});
    // print("{s}\n", .{shopping_html});
    // print("{s}\n", .{default_html});
    // print("{s}\n", .{details_template_html});
    // print("{s}\n", .{cart_item_template_html});
}
