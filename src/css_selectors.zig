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
extern "c" fn lxb_css_parser_create() ?*CssParser;
extern "c" fn lxb_css_parser_init(parser: *CssParser, memory: ?*anyopaque) usize;
extern "c" fn lxb_css_parser_destroy(parser: *CssParser, destroy_self: bool) ?*CssParser;

// CSS Selectors engine functions
extern "c" fn lxb_selectors_create() ?*CssSelectors;
extern "c" fn lxb_selectors_init(selectors: *CssSelectors) usize;
extern "c" fn lxb_selectors_destroy(selectors: *CssSelectors, destroy_self: bool) ?*CssSelectors;

// Parse selectors
extern "c" fn lxb_css_selectors_parse(parser: *CssParser, selectors: [*]const u8, length: usize) ?*CssSelectorList;

// Set options for selectors: MATCH_ROOT
extern "c" fn lxb_selectors_opt_set_noi(selectors: *CssSelectors, opts: usize) void;

// Find nodes matching selectors
extern "c" fn lxb_selectors_find(selectors: *CssSelectors, root: *z.DomNode, list: *CssSelectorList, callback: *const fn (
    node: *z.DomNode,
    spec: *CssSelectorSpecificity,
    ctx: ?*anyopaque,
) callconv(.C) usize, ctx: ?*anyopaque) usize;

extern "c" fn lxb_selectors_match_node(selectors: *CssSelectors, node: *z.DomNode, list: *CssSelectorList, callback: *const fn (*z.DomNode, *CssSelectorSpecificity, ?*anyopaque) callconv(.C) usize, ctx: ?*anyopaque) usize;

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

        // set options for unique results and root matching
        lxb_selectors_opt_set_noi(selectors, LXB_SELECTORS_OPT_MATCH_FIRST | LXB_SELECTORS_OPT_MATCH_ROOT);

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

    /// [selectors] Find first matching node
    pub fn findFirstNode(
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

    /// [selectors] Match a single node against a CSS selector
    /// Check if a specific node matches a selector (with type safety)
    pub fn matchNode(self: *Self, node: *z.DomNode, selector: []const u8) !bool {
        if (!self.initialized) return err.CssEngineNotInitialized;

        // CSS selectors only work on element nodes
        if (!z.isNodeElementType(node)) {
            return false;
        }

        const selector_list = lxb_css_selectors_parse(
            self.parser,
            selector.ptr,
            selector.len,
        ) orelse return err.CssSelectorParseFailed;

        defer lxb_css_selector_list_destroy_memory(selector_list);

        var context = FindContext.init(self.allocator);
        defer context.deinit();

        const status = lxb_selectors_match_node(
            self.selectors,
            node,
            selector_list,
            findCallback,
            &context,
        );

        if (status != z.LXB_STATUS_OK) {
            return err.CssSelectorMatchFailed;
        }

        return context.results.items.len > 0;
    }

    /// Find matching nodes (with optional type filtering)
    ///
    /// Caller needs to free the slice
    pub fn find(self: *Self, root_node: *z.DomNode, selector: []const u8) ![]*z.DomNode {
        if (!self.initialized) return err.CssEngineNotInitialized;

        const selector_list = lxb_css_selectors_parse(
            self.parser,
            selector.ptr,
            selector.len,
        ) orelse return err.CssSelectorParseFailed;

        defer lxb_css_selector_list_destroy_memory(selector_list);

        var context = FindContext.init(self.allocator);
        defer context.deinit();

        const status = lxb_selectors_find(
            self.selectors,
            root_node,
            selector_list,
            findCallback,
            &context,
        );
        if (status != z.LXB_STATUS_OK) {
            return err.CssSelectorFindFailed;
        }

        return context.results.toOwnedSlice();
    }

    /// Query: Find all descendant nodes that match the selector
    ///
    /// /// Caller needs to free the slice
    pub fn query(self: *Self, nodes: []*z.DomNode, selector: []const u8) ![]*z.DomNode {
        if (!self.initialized) return err.CssEngineNotInitialized;

        const selector_list = lxb_css_selectors_parse(
            self.parser,
            selector.ptr,
            selector.len,
        ) orelse return err.CssSelectorParseFailed;

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
                return err.CssSelectorFindFailed;
            }
        }

        return context.results.toOwnedSlice();
    }

    /// Filter: Keep only nodes that match the selector themselves
    /// Equivalent to C++ filter()
    pub fn filter(self: *Self, nodes: []*z.DomNode, selector: []const u8) ![]*z.DomNode {
        if (!self.initialized) return err.CssEngineNotInitialized;

        const selector_list = lxb_css_selectors_parse(
            self.parser,
            selector.ptr,
            selector.len,
        ) orelse return err.CssSelectorParseFailed;
        defer lxb_css_selector_list_destroy_memory(selector_list);

        var context = FindContext.init(self.allocator);
        defer context.deinit();

        // Test each input node directly
        for (nodes) |node| {
            if (z.isNodeElementType(node)) { // Guard for element nodes only
                const status = lxb_selectors_match_node(
                    self.selectors,
                    node,
                    selector_list,
                    findCallback,
                    &context,
                );
                if (status != z.LXB_STATUS_OK) {
                    return err.CssSelectorMatchFailed;
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
fn findCallback(node: *z.DomNode, spec: *CssSelectorSpecificity, ctx: ?*anyopaque) callconv(.C) usize {
    _ = spec; // unused

    const context: *FindContext = @ptrCast(@alignCast(ctx.?));
    context.results.append(node) catch return 1; // Return error status on allocation failure

    return z.LXB_STATUS_OK;
}

//=============================================================================
// CONVENIENCE FUNCTIONS
//=============================================================================

/// [selectors] High-level function: Find elements by CSS selector in a document
///
/// Caller needs to free the returned slice.
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
    const doc = try z.parseFromString(html);
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
    const doc = try z.parseFromString(html);
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
    const doc = try z.parseFromString(html);
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

        const doc = try z.parseFromString(test_case.html);
        defer z.destroyDocument(doc);

        const body = try z.getDocumentBodyElement(doc);
        const body_node = z.elementToNode(body);

        const results = try css_engine.find(body_node, test_case.selector);
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

    const body_node = try z.getDocumentBodyNode(doc);
    const container_div = z.firstChild(body_node).?;
    const container_div_element = z.nodeToElement(container_div);
    const class = try z.classList(
        allocator,
        container_div_element.?,
    );

    defer if (class) |c| allocator.free(c);
    try testing.expectEqualStrings("container", class.?);

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

        if (try z.elementGetNamedAttribute(allocator, element, "class")) |class_attr| {
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

    const body_node = try z.getDocumentBodyNode(doc);
    const container_div = z.firstChild(body_node).?;
    const red_box = z.firstChild(container_div).?;
    const blue_box = z.nextSibling(red_box).?;
    const paragraph = z.nextSibling(blue_box).?;

    var css_engine = try CssSelectorEngine.init(allocator);
    defer css_engine.deinit();

    const found_div = try css_engine.find(
        container_div,
        "div",
    );
    defer allocator.free(found_div);
    try testing.expect(found_div.len == 3);

    const found_box = try css_engine.find(container_div, ".box");
    defer allocator.free(found_box);
    try testing.expect(found_box.len == 2);

    const matches_div = try css_engine.matchNode(container_div, "div");
    try testing.expect(matches_div);

    const matches_box = try css_engine.matchNode(container_div, ".box");
    try testing.expect(!matches_box);

    const find_results = try css_engine.find(container_div, ".box");
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
    const container_find_box = try css_engine.find(container_div, ".box");
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

    const body_node = try z.getDocumentBodyNode(doc);
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
    const query_results = try css_engine.query(&input_nodes, ".box");
    defer allocator.free(query_results);
    try testing.expect(query_results.len == 2);
    // Should find the box_div when searching from container_div

    const filter_results = try css_engine.filter(&input_nodes, ".box");
    defer allocator.free(filter_results);
    try testing.expect(filter_results.len == 1);
    // Should keep only box_div from the input nodes

    // Test with different selector
    // `MATCH_ROOT` option allows searching from the root node itself
    const query_divs = try css_engine.query(&input_nodes, "div");
    defer allocator.free(query_divs);
    try testing.expect(query_divs.len == 3);

    const filter_divs = try css_engine.filter(&input_nodes, "div");
    defer allocator.free(filter_divs);
    try testing.expect(filter_divs.len == 2);
}
