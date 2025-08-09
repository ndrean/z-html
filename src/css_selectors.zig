//! CSS Selectors
const std = @import("std");
const z = @import("zhtml.zig");

const err = @import("errors.zig").LexborError;

const testing = std.testing;
const print = std.debug.print;

//=============================================================================
// CSS SELECTOR TYPES
//=============================================================================

pub const CssParser = opaque {};
pub const CssSelectors = opaque {};
pub const CssSelectorList = opaque {};
pub const CssSelectorSpecificity = opaque {};

//=============================================================================
// EXTERN CSS FUNCTIONS
//=============================================================================

// CSS Parser functions
extern "c" fn lxb_css_parser_create() ?*CssParser;
extern "c" fn lxb_css_parser_init(parser: *CssParser, memory: ?*anyopaque) usize;
extern "c" fn lxb_css_parser_destroy(parser: *CssParser, destroy_self: bool) ?*CssParser;

// CSS Selectors engine functions
extern "c" fn lxb_selectors_create() ?*CssSelectors;
extern "c" fn lxb_selectors_init(selectors: *CssSelectors) usize;
extern "c" fn lxb_selectors_destroy(selectors: *CssSelectors, destroy_self: bool) ?*CssSelectors;

// Parse selectors
extern "c" fn lxb_css_selectors_parse(parser: *CssParser, selectors: [*]const u8, length: usize) ?*CssSelectorList;

// Find nodes matching selectors
extern "c" fn lxb_selectors_find(selectors: *CssSelectors, root: *z.DomNode, list: *CssSelectorList, callback: *const fn (
    node: *z.DomNode,
    spec: *CssSelectorSpecificity,
    ctx: ?*anyopaque,
) callconv(.C) usize, ctx: ?*anyopaque) usize;

// Cleanup selector list
extern "c" fn lxb_css_selector_list_destroy_memory(list: *CssSelectorList) void;

pub const CssSelectorEngine = struct {
    allocator: std.mem.Allocator,
    parser: *CssParser,
    selectors: *CssSelectors,
    initialized: bool = false,

    const Self = @This();

    /// Initialize CSS selector engine
    pub fn init(allocator: std.mem.Allocator) !Self {
        const parser = lxb_css_parser_create() orelse return err.CssParserCreateFailed;

        if (lxb_css_parser_init(parser, null) != z.LXB_STATUS_OK) {
            _ = lxb_css_parser_destroy(parser, true);
            return err.CssParserInitFailed;
        }

        const selectors = lxb_selectors_create() orelse {
            _ = lxb_css_parser_destroy(parser, true);
            return err.CssSelectorsCreateFailed;
        };

        if (lxb_selectors_init(selectors) != z.LXB_STATUS_OK) {
            _ = lxb_selectors_destroy(selectors, true);
            _ = lxb_css_parser_destroy(parser, true);
            return err.CssSelectorsInitFailed;
        }

        return .{
            .parser = parser,
            .selectors = selectors,
            .allocator = allocator,
            .initialized = true,
        };
    }

    /// [selectors] Clean up CSS selector engine
    pub fn deinit(self: *Self) void {
        if (self.initialized) {
            _ = lxb_selectors_destroy(self.selectors, true);
            _ = lxb_css_parser_destroy(self.parser, true);
            self.initialized = false;
        }
    }

    /// [selectors] Parse CSS selector string and find matching nodes
    pub fn find(self: *Self, root_node: *z.DomNode, selector: []const u8) ![]*z.DomNode {
        if (!self.initialized) return err.CssEngineNotInitialized;

        // Parse the selector
        const selector_list = lxb_css_selectors_parse(self.parser, selector.ptr, selector.len) orelse return err.CssSelectorParseFailed;
        defer lxb_css_selector_list_destroy_memory(selector_list);

        // Find matching nodes
        var context = FindContext.init(self.allocator);
        defer context.deinit();

        const status = lxb_selectors_find(self.selectors, root_node, selector_list, findCallback, &context);
        if (status != z.LXB_STATUS_OK) {
            return err.CssSelectorFindFailed;
        }

        return context.results.toOwnedSlice();
    }

    /// [selectors] Find first matching node
    pub fn findFirst(
        self: *Self,
        root_node: *z.DomNode,
        selector: []const u8,
    ) !?*z.DomNode {
        const results = try self.find(
            root_node,
            selector,
        );
        defer self.allocator.free(results);

        return if (results.len > 0) results[0] else null;
    }

    /// [selectors] Check if any nodes match the selector
    pub fn matches(
        self: *Self,
        root_node: *z.DomNode,
        selector: []const u8,
    ) !bool {
        const results = try self.find(
            root_node,
            selector,
        );
        defer self.allocator.free(results);

        return results.len > 0;
    }
};

//=============================================================================
// INTERNAL CALLBACK CONTEXT
//=============================================================================

const FindContext = struct {
    results: std.ArrayList(*z.DomNode),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) FindContext {
        return FindContext{
            .results = std.ArrayList(*z.DomNode).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *FindContext) void {
        self.results.deinit();
    }
};

/// Callback function for lxb_selectors_find
fn findCallback(
    node: *z.DomNode,
    spec: *CssSelectorSpecificity,
    ctx: ?*anyopaque,
) callconv(.C) usize {
    _ = spec; // unused

    const context: *FindContext = @ptrCast(@alignCast(ctx.?));
    context.results.append(node) catch return 1; // Return error status on allocation failure

    return z.LXB_STATUS_OK;
}

//=============================================================================
// CONVENIENCE FUNCTIONS
//=============================================================================

/// [selectors] High-level function: Find elements by CSS selector in a document
pub fn findElements(
    allocator: std.mem.Allocator,
    doc: *z.HtmlDocument,
    selector: []const u8,
) ![]*z.DomElement {
    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    const body = try z.getDocumentBodyElement(doc);
    const body_node = z.elementToNode(body);

    const nodes = try css_engine.find(body_node, selector);
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

test "CSS selector basic functionality" {
    const allocator = testing.allocator;

    // Create HTML document
    const html = "<div><p class='highlight'>Hello</p><p id='my-id'>World</p><span class='highlight'>Test</span></div>";
    const doc = try z.parseHtmlString(html);
    defer z.destroyDocument(doc);

    // Test class selector
    const class_elements = try findElements(allocator, doc, ".highlight");
    defer allocator.free(class_elements);

    // print("Found {} elements with class 'highlight'\n", .{class_elements.len});
    try testing.expect(class_elements.len == 2); // p and span

    // Test ID selector
    const id_elements = try findElements(allocator, doc, "#my-id");
    defer allocator.free(id_elements);

    // print("Found {} elements with ID 'my-id'\n", .{id_elements.len});
    try testing.expect(id_elements.len == 1);

    const element_name = z.getNodeName(z.elementToNode(id_elements[0]));
    // print("Element with ID 'my-id' is: {s}\n", .{element_name});
    try testing.expectEqualStrings("P", element_name);
}

test "CSS selector engine reuse" {
    const allocator = testing.allocator;

    const html = "<article><h1>Title</h1><p>Para 1</p><p>Para 2</p><footer>End</footer></article>";
    const doc = try z.parseHtmlString(html);
    defer z.destroyDocument(doc);

    const body = try z.getDocumentBodyElement(doc);
    const body_node = z.elementToNode(body);

    // Create engine once, use multiple times
    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    // Find paragraphs
    const paragraphs = try css_engine.find(body_node, "p");
    defer allocator.free(paragraphs);
    try testing.expect(paragraphs.len == 2);

    // Find header
    const headers = try css_engine.find(body_node, "h1");
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
    const doc = try z.parseHtmlString(html);
    defer z.destroyDocument(doc);

    const body = try z.getDocumentBodyElement(doc);
    const body_node = z.elementToNode(body);

    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    // Test 1: Multiple selectors with :has() pseudo-class
    const first_selector = ".x, div:has(p[id=Y i])";
    const first_results = try css_engine.find(body_node, first_selector);
    defer allocator.free(first_results);

    // print("First selector '{s}' found {d} elements\n", .{ first_selector, first_results.len });

    // Should find:
    // 1. <p class='x z'> </p> (matches .x)
    // 2. <div> (matches div:has(p[id=Y i]))
    try testing.expect(first_results.len == 2);

    // Test 2: :blank pseudo-class
    const second_selector = "p:blank";
    const second_results = try css_engine.find(body_node, second_selector);
    defer allocator.free(second_results);

    // print("Second selector '{s}' found {d} elements\n", .{ second_selector, second_results.len });

    // Should find the <p> with only whitespace
    try testing.expect(second_results.len == 1);

    // Verify the results
    // for (first_results, 0..) |node, i| {
    //     const node_name = z.getNodeName(node);
    //     print("First result {d}: {s}\n", .{ i, node_name });
    // }

    // for (second_results, 0..) |node, i| {
    //     const node_name = z.getNodeName(node);
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

        const doc = try z.parseHtmlString(test_case.html);
        defer z.destroyDocument(doc);

        const body = try z.getDocumentBodyElement(doc);
        const body_node = z.elementToNode(body);

        const results = try css_engine.find(body_node, test_case.selector);
        defer allocator.free(results);

        // print("  Selector: '{s}' -> {d} results (expected {d})\n", .{ test_case.selector, results.len, test_case.expected_count });

        try testing.expectEqual(test_case.expected_count, results.len);
    }
}
