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

// Walker callback return codes
const LEXBOR_ACTION_OK: u32 = 0;
const LEXBOR_ACTION_STOP: u32 = 1;

/// Context for fast ID search using walker callback
const IdSearchContext = struct {
    target_id: []const u8,
    found_element: ?*z.DomElement,
};

/// Context for fast class search using walker callback
const ClassSearchContext = struct {
    target_class: []const u8,
    found_element: ?*z.DomElement,
};

/// Context for fast attribute search using walker callback
const AttributeSearchContext = struct {
    target_attr_name: []const u8,
    target_attr_value: ?[]const u8, // null means just check for attribute existence
    found_element: ?*z.DomElement,
};

/// Context for collecting multiple elements using walker callback
const MultiElementSearchContext = struct {
    target_attr_name: []const u8,
    target_attr_value: ?[]const u8, // null means just check for attribute existence
    target_class: ?[]const u8, // for class searches
    search_type: enum { attribute, class }, // what type of search we're doing
    allocator: std.mem.Allocator,
    results: std.ArrayList(*z.DomElement),
};

/// convert from "aligned" `anyopaque` to the target pointer type `T`
/// because of the callback signature:
fn castContext(comptime T: type, ctx: ?*anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(ctx.?)));
}

/// [Attr search] Walker callback for `getElementById`
///
/// Returns LEXBOR_ACTION_STOP=1 when ID is found, LEXBOR_ACTION_OK=0 to continue
fn idWalkerCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
    if (ctx == null) return LEXBOR_ACTION_OK;

    const search_ctx = castContext(IdSearchContext, ctx);

    if (!z.isTypeElement(node)) return LEXBOR_ACTION_OK;

    const element = z.nodeToElement(node) orelse return LEXBOR_ACTION_OK;

    if (!z.hasAttribute(element, "id")) return LEXBOR_ACTION_OK;

    const id_value = z.getElementId_zc(element);
    if (id_value.len == 0) return LEXBOR_ACTION_OK;
    const match = std.mem.eql(u8, id_value, search_ctx.target_id);

    if (match) {
        search_ctx.found_element = element;
        return LEXBOR_ACTION_STOP;
    }

    return LEXBOR_ACTION_OK; // Continue searching
}

/// Fast walker callback for class search optimization
/// Returns LEXBOR_ACTION_STOP when class is found, LEXBOR_ACTION_OK to continue
fn classWalkerCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
    if (ctx == null) return LEXBOR_ACTION_OK;

    const search_ctx = castContext(ClassSearchContext, ctx);

    if (!z.isTypeElement(node)) return LEXBOR_ACTION_OK;

    const element = z.nodeToElement(node) orelse return LEXBOR_ACTION_OK;

    // Check if this element has a class attribute
    if (!z.hasAttribute(element, "class")) return LEXBOR_ACTION_OK;

    const match = z.hasClass(element, search_ctx.target_class);
    if (match) {
        search_ctx.found_element = element;
        return LEXBOR_ACTION_STOP;
    }

    return LEXBOR_ACTION_OK; // Continue searching
}

/// Fast walker callback for collecting multiple elements by attribute
/// Always returns LEXBOR_ACTION_OK to continue searching entire tree
fn multiElementAttributeWalkerCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
    if (ctx == null) return LEXBOR_ACTION_OK;

    const search_ctx = castContext(MultiElementSearchContext, ctx);

    // Only check element nodes
    if (!z.isTypeElement(node)) return LEXBOR_ACTION_OK;

    const element = z.nodeToElement(node) orelse return LEXBOR_ACTION_OK;

    var matches = false;

    switch (search_ctx.search_type) {
        .attribute => {
            // Check if this element has the target attribute
            if (!z.hasAttribute(element, search_ctx.target_attr_name)) return LEXBOR_ACTION_OK;

            // If we only care about attribute existence (value is null), it matches
            if (search_ctx.target_attr_value == null) {
                matches = true;
            } else {
                // Otherwise, check the attribute value
                const attr_value = z.getAttribute_zc(element, search_ctx.target_attr_name) orelse return LEXBOR_ACTION_OK;
                matches = std.mem.eql(u8, attr_value, search_ctx.target_attr_value.?);
            }
        },
        .class => {
            // Check if this element has a class attribute
            if (!z.hasAttribute(element, "class")) return LEXBOR_ACTION_OK;

            matches = z.hasClass(element, search_ctx.target_class.?);
            // if (match) {
            //     search_ctx.found_element = element;
            //     return LEXBOR_ACTION_STOP;
            // }

            // Get the class value and search for the target class
            // const class_value = z.getAttribute_zc(element, "class") orelse return LEXBOR_ACTION_OK;

            // var iterator = std.mem.splitScalar(u8, class_value, ' ');
            // while (iterator.next()) |class| {
            //     const trimmed_class = std.mem.trim(u8, class, " \t\n\r");
            //     if (std.mem.eql(u8, trimmed_class, search_ctx.target_class.?)) {
            //         matches = true;
            //         break;
            //     }
            // }
        },
    }

    if (matches) {
        // Add to results - ignore allocation errors to keep walking
        search_ctx.results.append(element) catch {};
    }

    return LEXBOR_ACTION_OK; // Always continue searching
}

/// Fast walker callback for attribute search optimization
/// Returns LEXBOR_ACTION_STOP when attribute is found, LEXBOR_ACTION_OK to continue
fn attributeWalkerCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
    if (ctx == null) return LEXBOR_ACTION_OK;

    const search_ctx = castContext(AttributeSearchContext, ctx);

    // Only check element nodes
    if (!z.isTypeElement(node)) return LEXBOR_ACTION_OK;

    const element = z.nodeToElement(node) orelse return LEXBOR_ACTION_OK;

    // Check if this element has the target attribute
    if (!z.hasAttribute(element, search_ctx.target_attr_name)) return LEXBOR_ACTION_OK;

    // If we only care about attribute existence (value is null), we found it
    if (search_ctx.target_attr_value == null) {
        search_ctx.found_element = element;
        return LEXBOR_ACTION_STOP;
    }

    // Otherwise, check the attribute value
    const attr_value = z.getAttribute_zc(element, search_ctx.target_attr_name) orelse return LEXBOR_ACTION_OK;

    const match = std.mem.eql(u8, attr_value, search_ctx.target_attr_value.?);

    if (match) {
        search_ctx.found_element = element;
        return LEXBOR_ACTION_STOP; // Found it! Stop traversal
    }

    return LEXBOR_ACTION_OK; // Continue searching
}

/// [attributes] Fast getElementById using optimized DOM traversal
///
/// This is significantly faster than collection-based approaches because:
/// 1. Uses lxb_dom_node_simple_walk for efficient tree traversal
/// 2. Stops immediately when ID is found (early termination)
/// 3. Avoids collection allocation/deallocation overhead
/// 4. Direct memory comparison without intermediate allocations
///
/// Returns the first element with matching ID, or null if not found.
/// IDs should be unique in valid HTML, so first match is the correct result.
pub fn getElementByIdFast(doc: *z.HtmlDocument, id: []const u8) !?*z.DomElement {
    // Start search from document root to include head elements too
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

/// [attributes] Fast data attribute search - convenience wrapper
///
/// Searches for elements with data-* attributes (common in modern web development).
/// Example:
/// ```
/// // finds elements with data-id="123"
/// getElementByDataAttributeFast(doc, "id", "123")
/// ---
/// ```
pub fn getElementByDataAttributeFast(doc: *z.HtmlDocument, data_name: []const u8, value: ?[]const u8) !?*z.DomElement {
    // Build the full data attribute name
    var attr_name_buffer: [256]u8 = undefined;
    const attr_name = try std.fmt.bufPrint(attr_name_buffer[0..], "data-{s}", .{data_name});

    return getElementByAttributeFast(doc, attr_name, value);
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
        \\  <main id="content" class="main-content" data-section="content">
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
    const header_section = try getElementByDataAttributeFast(doc, "section", "header");
    try testing.expect(header_section != null);
    try testing.expectEqualStrings("DIV", z.tagName_zc(header_section.?));

    const home_page = try getElementByDataAttributeFast(doc, "page", "home");
    try testing.expect(home_page != null);
    try testing.expectEqualStrings("A", z.tagName_zc(home_page.?));

    const tech_article = try getElementByDataAttributeFast(doc, "category", "tech");
    try testing.expect(tech_article != null);
    try testing.expectEqualStrings("ARTICLE", z.tagName_zc(tech_article.?));

    // Test 6: Non-existent searches should return null
    const missing_id = try getElementByIdFast(doc, "nonexistent");
    try testing.expect(missing_id == null);

    const missing_class = try getElementByClassFast(doc, "nonexistent-class");
    try testing.expect(missing_class == null);

    const missing_attr = try getElementByAttributeFast(doc, "nonexistent-attr", "value");
    try testing.expect(missing_attr == null);

    const missing_data = try getElementByDataAttributeFast(doc, "nonexistent", "value");
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
    const data_element = try getElementByDataAttributeFast(doc, "priority", "high");
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

test "collection vs walker - when collections are still useful" {
    const allocator = testing.allocator;

    const html =
        \\<html><body>
        \\  <div data-id="42">Exact match</div>
        \\  <div data-id="142">Partial match</div>
        \\  <div data-id="420">Partial match</div>
        \\  <div data-category="electronics">Category</div>
        \\</body></html>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // std.debug.print("\n=== When Collections Excel ===\n", .{});

    // Test exact attribute value matching where collections work well
    const walker_data_42 = try getElementsByDataAttributeWalker(allocator, doc, "id", "42");
    defer allocator.free(walker_data_42);

    // For exact data-id matching, let's use getElementsByAttributePair directly
    const collection_data_42 = try z.getElementsByAttributePair(doc, .{ .name = "data-id", .value = "42" }, false);
    const collection_data_42_count = if (collection_data_42) |coll| blk: {
        defer z.destroyCollection(coll);
        break :blk z.collectionLength(coll);
    } else 0;

    // std.debug.print("Exact data-id='42' matching:\n", .{});
    // std.debug.print("  Walker: {} elements\n", .{walker_data_42.len});
    // std.debug.print("  Collection: {} elements\n", .{collection_data_42_count});

    // Both should find exactly 1 element
    try testing.expect(walker_data_42.len == 1);
    try testing.expect(collection_data_42_count == 1);

    // std.debug.print("\n📊 Summary:\n", .{});
    // std.debug.print("• Walker: Better for CSS classes (token-based)\n", .{});
    // std.debug.print("• Collection: Better for exact attribute values\n", .{});
    // std.debug.print("• Walker: Better for single-element searches (early exit)\n", .{});
    // std.debug.print("• Collection: Better for bulk operations on known large result sets\n", .{});
}

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
