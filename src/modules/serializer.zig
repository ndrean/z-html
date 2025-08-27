//! Serialization, innerHTML
// =============================================================================
// Serialization Nodes and Elements
// =============================================================================

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;
const print = z.Writer.log;

const testing = std.testing;

const LXB_HTML_SERIALIZE_OPT_UNDEF: c_int = 0x00;

const lxbString = extern struct {
    data: ?[*]u8, // Pointer to string data
    length: usize, // String length
    size: usize, // lexbor Allocated size
};

extern "c" fn lxb_html_serialize_tree_str(node: *z.DomNode, str: *lxbString) usize;

extern "c" fn lxb_html_serialize_pretty_tree_cb(
    node: *z.DomNode,
    opt: usize,
    indent: usize,
    cb: *const fn ([*:0]const u8, len: usize, ctx: *anyopaque) callconv(.C) c_int,
    ctx: ?*anyopaque,
) c_int;

pub fn serializeToString(allocator: std.mem.Allocator, node: *z.DomNode) ![]u8 {
    var str = lxbString{
        .data = null,
        .length = 0,
        .size = 0,
    };
    const status = lxb_html_serialize_tree_str(node, &str);
    if (status != z._OK) {
        return Err.SerializeFailed;
    }

    if (str.data == null or str.length == 0) {
        return Err.NoBodyElement;
    }
    const result = try allocator.alloc(u8, str.length);
    @memcpy(result, str.data.?[0..str.length]);

    return result;
}

// pub fn prettyPrintFirstTest(node: *z.DomNode, ctx: PrintCtx) c_int {
//     var mut_ctx = ctx;
//     const prettyPrintCB = struct {
//         fn cb(data: [*:0]const u8, len: usize, context: ?*anyopaque) callconv(.C) c_int {
//             _ = len;
//             _ = context;
//             const l = std.mem.len(data);

//             if (std.mem.eql(u8, data[0..l], "body")) {
//                 print("{s}{s}{s}", .{ z.Colour.code(.GREEN), data, z.Colour.code(.RESET) });
//             } else if (std.mem.eql(u8, data[0..l], "p")) {
//                 print("{s}{s}{s}", .{ z.Colour.code(.YELLOW), data, z.Colour.code(.RESET) });
//             } else if (std.mem.eql(u8, data[0..l], "<") or std.mem.eql(u8, data[0..l], "</") or std.mem.eql(u8, data[0..l], ">")) {
//                 print("{s}{s}{s}", .{ z.Colour.code(.WHITE), data, z.Colour.code(.RESET) });
//             } else {
//                 print("{s}", .{data});
//             }
//             return 0;
//         }
//     }.cb;

//     return lxb_html_serialize_pretty_tree_cb(
//         node,
//         ctx.opt,
//         ctx.indent,
//         prettyPrintCB,
//         &mut_ctx,
//     );
// }

fn prettyPrint(node: *z.DomNode) c_int {
    return prettyPrintOpt(node, defaultStyler, PrintCtx.init(0));
}

fn prettyPrintOpt(
    node: *z.DomNode,
    styler: *const fn (data: [*:0]const u8, len: usize, context: ?*anyopaque) callconv(.C) c_int,
    ctx: PrintCtx,
) c_int {
    var mut_ctx = ctx;
    return lxb_html_serialize_pretty_tree_cb(
        node,
        mut_ctx.opt,
        mut_ctx.indent,
        styler,
        &mut_ctx,
    );
}

fn defaultStyler(data: [*:0]const u8, len: usize, context: ?*anyopaque) callconv(.C) c_int {
    const ctx_ptr: *PrintCtx = @ptrCast(@alignCast(context.?));
    const text = data[0..len];

    if (z.isWhitespaceOnlyText(text) or std.mem.eql(u8, text, "=\"")) {
        print("{s}", .{text});
        return 0;
    }

    if (std.mem.eql(u8, text, "<") or std.mem.eql(u8, text, ">") or std.mem.eql(u8, text, "</") or std.mem.eql(u8, text, "/>")) {
        ctx_ptr.expect_attr_value = false; // Reset state
        applyStyle(z.SyntaxStyle.brackets, text);
        return 0;
    }

    const maybeTagStyle = z.getStyleForElement(text);

    // 2. Handle HTML elements/tags
    if (len > 0 and !z.isWhitespaceOnlyText(text) and maybeTagStyle != null) {
        // print("\nis TAG ----: {s}\n", .{text});
        ctx_ptr.expect_attr_value = false; // Reset state
        applyStyle(maybeTagStyle.?, text);
        return 0;
    }

    const isAttr = z.isKnownAttribute(text);

    // 3. Handle known attributes
    if (len > 0 and !z.isWhitespaceOnlyText(text) and isAttr) {
        ctx_ptr.expect_attr_value = true; // Set flag for potential value
        applyStyle(z.SyntaxStyle.attributes, text);
        return 0;
    }

    //  Handle equals sign  (tricky =" !!)
    if (ctx_ptr.expect_attr_value and len > 0 and !z.isWhitespaceOnlyText(text) and std.mem.eql(u8, text, "=\"")) {
        applyStyle(z.SyntaxStyle.attr_equals, text);
        return 0;
    }

    // 5. Handle attribute values
    if (ctx_ptr.expect_attr_value and len > 0 and !z.isWhitespaceOnlyText(text)) {
        ctx_ptr.expect_attr_value = false; // Reset after consuming value
        applyStyle(z.SyntaxStyle.attr_values, text);
        return 0;
    }

    // 6. Handle any other non-whitespace token (reset state)
    if (len > 0 and !z.isWhitespaceOnlyText(text)) {
        ctx_ptr.expect_attr_value = false; // Reset state
        applyStyle(z.SyntaxStyle.text, text);
        return 0;
    }
    return 0;
}

fn applyStyle(style: []const u8, text: []const u8) void {
    print("{s}", .{style});
    print("{s}", .{text});
    print("{s}", .{z.Style.RESET});
}

const PrintCtx = struct {
    indent: usize = 0,
    opt: usize = 0,
    expect_attr_value: bool,
    pub fn init(
        indent: usize,
    ) @This() {
        return .{
            .indent = indent,
            .opt = 0,
            .expect_attr_value = false,
        };
    }
};

test "Serializer" {
    const allocator = testing.allocator;

    try z.Writer.initLog("logfile.log");
    defer z.Writer.deinitLog();

    // Test serialization of a simple node
    const doc = try z.parseFromString("<div><button phx-click=\"increment\">Click me</button> <p>Hello<i>there</i>, all<strong>good?</strong></p><p>Visit this link: <a href=\"https://example.com\">example.com</a></p></div><link href=\"/shared-assets/misc/link-element-example.css\" rel=\"stylesheet\"><script>console.log(\"hi\");</script>");
    defer z.destroyDocument(doc);

    const body = try z.bodyNode(doc);

    const result = try serializeToString(allocator, body);
    defer allocator.free(result);

    const expected = "<body><div><button phx-click=\"increment\">Click me</button> <p>Hello<i>there</i>, all<strong>good?</strong></p><p>Visit this link: <a href=\"https://example.com\">example.com</a></p></div><link href=\"/shared-assets/misc/link-element-example.css\" rel=\"stylesheet\"><script>console.log(\"hi\");</script></body>";

    try testing.expectEqualStrings(expected, result);

    print("\n\n", .{});
    _ = prettyPrint(body);
    print("\n\n a", .{});
}

/// [Serialize] Serializes the HTMLElement tree
///
/// Caller needs to free the returned slice.
pub fn serializeElement(allocator: std.mem.Allocator, element: *z.HTMLElement) ![]u8 {
    const node = z.elementToNode(element);
    return try serializeToString(allocator, node);
}

// -------------------------------------------------------------------------------
// Inner - Outer HTML
// -------------------------------------------------------

extern "c" fn lxb_html_element_inner_html_set(
    body: *z.HTMLElement,
    inner: [*]const u8,
    inner_len: usize,
) *z.HTMLElement;

/// [Serialize] Get element's inner HTML
///
/// When called on an element, it serializes all child nodes of that element.
///
/// Caller needs to free the returned slice
pub fn innerHTML(allocator: std.mem.Allocator, element: *z.HTMLElement) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    const element_node = z.elementToNode(element);

    // Traverse child nodes and concatenate their serialization into a slice
    var child = z.firstChild(element_node);
    while (child != null) {
        const child_html = try serializeToString(allocator, child.?);
        defer allocator.free(child_html);

        try result.appendSlice(child_html);

        child = z.nextSibling(child.?);
    }

    return result.toOwnedSlice();
}

/// [Serialize] Sets / replaces element's inner HTML with security controls.
///
/// -  `options.allow_html = true`: parses content as HTML for trusted content.
/// -  `options.allow_html = false`: treats content as safe __text__ and escapes HTML if `options.escape = true`
///
/// Returns the updated element as _parsed HTML_ or _text_ or error if escaping fails
/// ## Example
/// ```
/// // parsing as HTML elements
/// try setInnerHTML(allocator, element, "<script> alert('XSS')</script>", .{});
/// <script> alert('XSS')</script>
///
/// // parsing into text
/// try setInnerHTML(allocator, element, "<script> alert('XSS')</script>", .{ .allow_html = false });
///  "<script> alert('XSS')</script>"
///
// parsing into text with escape
/// try setInnerHTML(allocator, element, "<script> alert('XSS')</script>", .{ .allow_html = false, .escape = true });
///  "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt; &amp; &quot;quotes&quot;"
/// ```
pub fn setInnerHTML(allocator: std.mem.Allocator, element: *z.HTMLElement, content: []const u8, options: z.TextOptions) !*z.HTMLElement {
    if (options.allow_html) {
        // Developer explicitly allowed HTML parsing - use at your own risk
        return lxb_html_element_inner_html_set(element, content.ptr, content.len);
    } else {
        // Safe path: treat as text content only
        const final_content = if (options.escape)
            try z.escapeHtml(allocator, content)
        else
            content;
        defer if (options.escape) allocator.free(final_content);

        try z.setTextContent(z.elementToNode(element), final_content);
        return element;
    }
}

/// [Serialize]Sets element's inner HTML directly without safety checks.
///
/// For user content, use setInnerHTML() with TextOptions instead.
fn setInnerHTMLUnsafe(element: *z.HTMLElement, inner: []const u8) *z.HTMLElement {
    return lxb_html_element_inner_html_set(
        element,
        inner.ptr,
        inner.len,
    );
}

/// [Serialize] Gets element's outer HTML (including the element itself)
///
/// Caller needs to free the returned slice
pub fn outerHTML(allocator: std.mem.Allocator, element: *z.HTMLElement) ![]u8 {
    return try serializeElement(allocator, element);
}

test "innerHTML" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Create a container element
    var div = try z.createElementAttr(doc, "div", &.{});

    // test 1 --------------
    div = setInnerHTMLUnsafe(div, "<p id=\"1\">Hello <strong>World</strong></p>");
    const inner1 = try innerHTML(allocator, div);
    defer allocator.free(inner1);

    try testing.expectEqualStrings(
        "<p id=\"1\">Hello <strong>World</strong></p>",
        inner1,
    );

    const complex_html =
        \\<h1>Title</h1>
        \\<p class="intro">Introduction paragraph</p>
        \\<article>
        \\  <ul>
        \\    <li>Item 1</li>
        \\    <li>Item 2</li>
        \\  </ul>
        \\</article>
    ;

    // test 2 --------------
    div = setInnerHTMLUnsafe(div, complex_html);

    const inner2 = try innerHTML(allocator, div);
    defer allocator.free(inner2);

    const inner3 = try serializeToString(allocator, z.elementToNode(div));
    defer allocator.free(inner3);

    try testing.expect(
        std.mem.indexOf(u8, inner2, "<h1>Title") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, inner2, "<ul>") != null,
    );

    try testing.expect(
        std.mem.indexOf(u8, inner2, "<p class=\"intro\">Intro") != null,
    );
    // check this removed old inner HTML
    try testing.expect(
        std.mem.indexOf(u8, inner2, "<p>Hello World</p>") == null,
    );

    // Test 3: Get outer HTML (includes the div itself) --------------
    const outer = try outerHTML(allocator, div);
    defer allocator.free(outer);
    // print("{s}\n", .{outer});

    // Should contain the root div tag
    try testing.expect(
        std.mem.indexOf(u8, outer, "<div>") != null,
    );
    // should could inner HTML
    try testing.expect(
        std.mem.indexOf(u8, outer, "<li>") != null,
    );

    try testing.expect(
        std.mem.indexOf(u8, outer, "</div>") != null,
    );
}

test "set innerHTML" {
    const allocator = std.testing.allocator;
    const html = "<div><span>blah-blah-blah</div>";
    const inner = "<ul><li>1<li>2<li>3</ul>";
    const doc = try z.parseFromString(html);
    const body = try z.bodyElement(doc);
    const div_elt = z.firstElementChild(body);
    defer z.destroyDocument(doc);

    const inner_html = try serializeElement(allocator, div_elt.?);
    defer allocator.free(inner_html);

    try testing.expectEqualStrings(
        inner_html,
        "<div><span>blah-blah-blah</span></div>",
    );

    const element = setInnerHTMLUnsafe(div_elt.?, inner);
    const serialized = try serializeElement(allocator, element);
    defer allocator.free(serialized);

    try testing.expectEqualStrings(
        serialized,
        "<div><ul><li>1</li><li>2</li><li>3</li></ul></div>",
    );

    const set_new_body = setInnerHTMLUnsafe(
        body,
        "<p>New body content</p>",
    );
    const new_body_html = try serializeElement(allocator, set_new_body);
    defer allocator.free(new_body_html);

    try testing.expectEqualStrings(
        new_body_html,
        "<body><p>New body content</p></body>",
    );
}

test "direct serialization" {
    const allocator = testing.allocator;
    const fragment = "<div><p>Hi <strong>there</strong></p></div>";
    const doc = try z.parseFromString(fragment);
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);

    if (z.firstChild(body_node)) |div_node| {
        const serialized = try serializeToString(allocator, div_node);
        defer allocator.free(serialized);

        try testing.expect(
            std.mem.indexOf(u8, serialized, "<div>") != null,
        );
        try testing.expect(
            std.mem.indexOf(u8, serialized, "there") != null,
        );
    }
}

test "serialize Node vs tree functionality" {
    const allocator = testing.allocator;
    const fragment = "<div id=\"my-div\"><p class=\"bold\">Hello <strong>World</strong></p>   </div>";
    const doc = try z.parseFromString(fragment);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const body_node = z.elementToNode(body);

    // Get the div element
    const div_node = z.firstChild(body_node) orelse {
        try testing.expect(false); // Should have div
        return;
    };

    // Test serializeNode vs serializeTree difference
    // const node_html = try serializeNode(allocator, div_node);
    // defer allocator.free(node_html);

    const tree_html = try serializeToString(
        allocator,
        div_node,
    );
    defer allocator.free(tree_html);

    // Both should contain the div tag
    // try testing.expect(
    //     std.mem.indexOf(u8, node_html, "div") != null,
    // );
    try testing.expect(
        std.mem.indexOf(u8, tree_html, "div") != null,
    );

    // Node_html contains only "<div id='my-div'>"
    // try testing.expect(
    //     std.mem.indexOf(u8, node_html, "<p>") == null,
    // );
    // try testing.expectEqualStrings(
    //     "<div id=\"my-div\">",
    //     node_html,
    // );
    // Tree should definitely contain all content
    try testing.expect(
        std.mem.indexOf(u8, tree_html, "Hello") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, tree_html, "<strong>World</strong>") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, tree_html, "class=\"bold\"") != null,
    );
}

test "behaviour of serializeNode" {
    const allocator = testing.allocator;

    // Test different types of elements
    const test_cases = [_]struct {
        html: []const u8,
        serialized_node: []const u8,
        serialized_tree: []const u8,
    }{
        // self-closing tags
        .{
            .html = "<br/>",
            .serialized_node = "<br>",
            .serialized_tree = "<br>",
        },
        .{
            .html = "<img src=\"my-image\"/>",
            .serialized_node = "<img src=\"my-image\">",
            .serialized_tree = "<img src=\"my-image\">",
        },
        .{
            .html = "<p><span></span></p>",
            .serialized_node = "<p>",
            .serialized_tree = "<p><span></span></p>",
        },
        .{
            .html = "<p></p>",
            .serialized_node = "<p>",
            .serialized_tree = "<p></p>",
        },
        .{
            .html = "<div data-id=\"myid\" class=\"test\">Simple text</div>",
            .serialized_node = "<div data-id=\"myid\" class=\"test\">",
            .serialized_tree = "<div data-id=\"myid\" class=\"test\">Simple text</div>",
        },
    };

    for (test_cases) |case| {
        const doc = try z.parseFromString(case.html);
        defer z.destroyDocument(doc);

        const body = try z.bodyElement(doc);
        const body_node = z.elementToNode(body);
        const element_node = z.firstChild(body_node).?;

        // const serial_node = try serializeNode(allocator, element_node);
        // defer allocator.free(serial_node);

        const serialized_tree = try serializeToString(allocator, element_node);
        defer allocator.free(serialized_tree);

        // try testing.expectEqualStrings(serial_node, case.serialized_node);
        try testing.expectEqualStrings(serialized_tree, case.serialized_tree);
    }
}

test "setInnerHTML security model" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const div = try z.createElementAttr(doc, "div", &.{});

    // Test 1: Malicious content treated as safe text (default behavior)
    const malicious_content = "<script>alert('XSS')</script><p>Safe text</p>";

    _ = try setInnerHTML(allocator, div, malicious_content, .{ .allow_html = false });

    const safe_result = try innerHTML(allocator, div);
    defer allocator.free(safe_result);

    // print("\nTest 1 (safe text): {s}\n", .{safe_result});

    // Should NOT contain parsed script tag - should be HTML-escaped text
    try testing.expect(std.mem.indexOf(u8, safe_result, "<script>") == null);
    try testing.expect(std.mem.indexOf(u8, safe_result, "&lt;script&gt;") != null);

    // Test 2: With explicit escaping enabled
    _ = try setInnerHTML(
        allocator,
        div,
        malicious_content,
        .{ .escape = true, .allow_html = false },
    );

    const escaped_result = try innerHTML(allocator, div);
    defer allocator.free(escaped_result);

    // print("Test 2 (escaped): {s}\n", .{escaped_result});

    // Should be double-escaped text (& becomes &amp;)
    try testing.expect(std.mem.indexOf(u8, escaped_result, "&amp;lt;script&amp;gt;") != null);

    // Test 3: Developer explicitly allows HTML (dangerous but intentional)
    const trusted_content = "<p class=\"safe\">This is trusted template content</p>";

    _ = try setInnerHTML(allocator, div, trusted_content, .{ .allow_html = true });

    const html_result = try innerHTML(allocator, div);
    defer allocator.free(html_result);

    // print("Test 3 (trusted HTML): {s}\n", .{html_result});

    // Should contain parsed HTML since developer explicitly allowed it
    try testing.expect(std.mem.indexOf(u8, html_result, "<p class=\"safe\">") != null);
    try testing.expect(std.mem.indexOf(u8, html_result, "trusted template") != null);

    // Test 4: Even with allow_html=true, developer should be cautious
    _ = try setInnerHTML(allocator, div, malicious_content, .{ .allow_html = true });

    const dangerous_result = try innerHTML(allocator, div);
    defer allocator.free(dangerous_result);

    // print("Test 4 (DANGEROUS - allow_html=true): {s}\n", .{dangerous_result});

    // This WILL contain script tag - developer responsibility!
    try testing.expect(std.mem.indexOf(u8, dangerous_result, "<script>") != null);
}
test "serializeNode vs serializeTree comparison" {
    const allocator = testing.allocator;

    const fragment = "<article><header>Title</header><section>Content <span>inside</span></section></article>";

    const doc = try z.parseFromString(fragment);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const body_node = z.elementToNode(body);
    const article_node = z.firstChild(body_node).?;

    // Serialize the article element
    // const node_result = try serializeNode(allocator, article_node);
    // defer allocator.free(node_result);

    const tree_result = try serializeToString(allocator, article_node);
    defer allocator.free(tree_result);

    // try testing.expect(node_result.len == 9);
    try testing.expect(tree_result.len == 87);

    // try testing.expectEqualStrings(node_result, "<article>");
    try testing.expectEqualStrings(tree_result, fragment);

    // Both should contain the article tag
    // try testing.expect(std.mem.indexOf(u8, node_result, "article") != null);
    try testing.expect(std.mem.indexOf(u8, tree_result, "article") != null);

    // Tree should definitely contain all nested content
    try testing.expect(std.mem.indexOf(u8, tree_result, "Title") != null);
    try testing.expect(std.mem.indexOf(u8, tree_result, "Content") != null);
    try testing.expect(std.mem.indexOf(u8, tree_result, "<span>inside</span>") != null);
}
