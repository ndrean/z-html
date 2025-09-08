//! Text and comments content manipulation functions to read and set text content and comments
//!
//! It provides direct functions (terminated by `_zc`) to get zero-copy slices directly into lexbor's internal memory, and allocated versions.

const std = @import("std");
const z = @import("../root.zig");
const print = std.debug.print;
const Err = z.Err;

const testing = std.testing;

extern "c" fn lxb_dom_node_text_content(node: *z.DomNode, len: ?*usize) ?[*:0]u8;
extern "c" fn lxb_dom_node_text_content_set(node: *z.DomNode, content: [*]const u8, len: usize) u8;
extern "c" fn lxb_dom_character_data_replace(node: *z.DomNode, data: [*]const u8, len: usize, offset: usize, count: usize) u8;
extern "c" fn lexbor_destroy_text_wrapper(node: *z.DomNode, text: ?[*:0]u8) void; //<- ?????

// === comment ===

/// [core] Get comment text content
///
/// Caller owns the slice
pub fn commentContent(allocator: std.mem.Allocator, comment: *z.Comment) ![]u8 {
    const inner_text = try textContent(
        allocator,
        z.commentToNode(comment),
    );
    return inner_text;
}

/// [core] Get comment text content as _zero-copy slice_ (UNSAFE)
pub fn commentContent_zc(comment: *z.Comment) []const u8 {
    return textContent_zc(z.commentToNode(comment));
}

test "comments" {
    const allocator = testing.allocator;

    const html_with_comments =
        \\<div>
        \\    <!-- regular comment -->
        \\    <!--   whitespace comment   -->
        \\    <!---->
        \\    <!--
        \\    multiline
        \\    comment
        \\    -->
        \\    <p>Text</p>
        \\</div>
    ;

    const doc = try z.createDocFromString(html_with_comments);
    defer z.destroyDocument(doc);
    const body_node = z.bodyNode(doc).?;
    const div_node = z.firstChild(body_node).?;

    var comment_count: usize = 0;
    var child = z.firstChild(div_node);

    while (child != null) {
        const node_type = z.nodeType(child.?);
        if (node_type == .comment) {
            comment_count += 1;

            const child_as_comment = z.nodeToComment(child.?).?;
            const comment_text = z.commentContent_zc(child_as_comment);

            const alloc_comment_text = try z.commentContent(allocator, child_as_comment);
            defer allocator.free(alloc_comment_text);

            try testing.expectEqualStrings(alloc_comment_text, comment_text);
        }
        child = z.nextSibling(child.?);
    }

    try testing.expect(comment_count == 4);
}

// === text ===

/// [core] Get the concatenated text content with empty string fallback of a node
///
/// Returns the text content or an empty string if none exists.
///
/// Caller owns the slice
/// ## Example
/// ```
/// const doc = try z.createDocFromString("<div><p>I am <strong>bold</strong></p><p>and I am <em>italic</em></p></div>");
/// const div = z.firstChild(try z.bodyNode(doc));
/// const text = try textContent(allocator, div.?);
/// defer allocator.free(text);
/// try testing.expectEqualStrings("I am boldand I am italic", text);
/// ---
/// ```
pub fn textContent(allocator: std.mem.Allocator, node: *z.DomNode) ![]u8 {
    var len: usize = 0;
    const text_ptr = lxb_dom_node_text_content(node, &len) orelse return allocator.dupe(u8, "");

    defer lexbor_destroy_text_wrapper(node, text_ptr);

    if (len == 0) return allocator.dupe(u8, "");

    // const result = try allocator.alloc(u8, len);
    // @memcpy(result, text_ptr[0..len]);
    // return result;
    return allocator.dupe(u8, text_ptr[0..len]);
}

test "textContent" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("<div><p>I am <strong>bold</strong></p><p>and I am <em>italic</em></p></div>");
    const div = z.firstChild(z.bodyNode(doc).?);
    const p = z.firstChild(div.?);
    const text = try textContent(allocator, p.?);
    defer allocator.free(text);
    try testing.expectEqualStrings("I am bold", text);
    try testing.expectEqualStrings("I am boldand I am italic", z.textContent_zc(div.?));
}

/// [core] Get text content as _zero-copy slice_ (UNSAFE)
///
/// Returns a slice directly into lexbor's internal memory - no allocation!
pub fn textContent_zc(node: *z.DomNode) []const u8 {
    var len: usize = 0;
    const text_ptr = lxb_dom_node_text_content(node, &len) orelse return "";

    if (len == 0) return "";

    return text_ptr[0..len];
}

// pub const TextOptions = struct {
//     escape: bool = false,
//     remove_comments: bool = false,
//     remove_empty_elements: bool = false,
//     keep_new_lines: bool = false,
// };

/// [core] Sets any inner content of a node with new content as text.
///
/// This **replaces** _any_ existing content, even empty. check `replaceText()` to modify existing text nodes.
/// ## Example
/// ```
/// const doc = try z.createDocFromString("<p>Hello <strong>world</strong></p>");
/// defer z.destroyDocument(doc);
/// const p = firstChild(try bodyNode(doc));
/// try setContentAsText(p.?, "Hi");
///
/// const text = try z.outerHTML(allocator, z.nodeToElement(p.?).?);
/// defer allocator.free(text);
/// try testing.expectEqualStrings("<p>Hi</p>", text);
/// ---
/// ```
pub fn setContentAsText(node: *z.DomNode, content: []const u8) !void {
    const status = lxb_dom_node_text_content_set(
        node,
        content.ptr,
        content.len,
    );
    if (status != z._OK) return Err.SetTextContentFailed;
}

test "setContentAsText" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("<p>Hello <strong>world</strong></p><p></p>");
    defer z.destroyDocument(doc);

    // replace the inner content of an element with a new text node
    const p1 = z.firstChild(z.bodyNode(doc).?).?;
    try testing.expect(z.isNodeEmpty(p1) == false);
    try testing.expect(z.tagFromElement(z.firstElementChild(z.nodeToElement(p1).?).?) == .strong);
    try setContentAsText(p1, "New text");
    try testing.expectEqualStrings("New text", z.textContent_zc(p1));

    const txt1 = try z.outerHTML(allocator, z.nodeToElement(p1).?);
    defer allocator.free(txt1);
    try testing.expectEqualStrings("<p>New text</p>", txt1);

    // setting text content on empty paragraph
    const p2 = z.nextSibling(p1).?;
    try testing.expect(z.isNodeEmpty(p2) == true);
    try setContentAsText(p2, "hi");
    try testing.expectEqualStrings("hi", z.textContent_zc(p2));
    const txt2 = try z.outerHTML(allocator, z.nodeToElement(p2).?);
    defer allocator.free(txt2);
    try testing.expectEqualStrings("<p>hi</p>", txt2);

    // create
    const div_elt = try z.createElement(doc, "div");
    const div = z.elementToNode(div_elt);

    try setContentAsText(div, "Hola");
    try testing.expectEqualStrings("Hola", z.textContent_zc(div));
}

/// [core] replace the text data of a _text node_ with escape option.
///
/// If `options.escape = true`, the text will be HTML-escaped before insertion.
/// ## Example
/// ```
/// const doc = try z.createDocFromString("<p>Hello <strong>world</strong></p>");
/// defer z.destroyDocument(doc);
/// const p = firstChild(try bodyNode(doc));
/// const inner_text = firstChild(p.?);
///
/// try replaceText(allocator, inner_text.?, "Hi ", .{});
/// try testing.expectEqualStrings("Hi world", z.textContent_zc(p.?));
///
/// const html = try z.outerHTML(allocator, z.nodeToElement(p.?).?);
/// defer allocator.free(html);
/// try testing.expectEqualStrings("<p>Hi <strong>world</strong></p>", html);
/// ---
/// ```
pub fn replaceText(node: ?*z.DomNode, text: []const u8) !void {
    // const n = node orelse return Err.NoNode;

    if (node == null) return Err.NoNode;
    if (z.nodeType(node.?) != .text) return Err.NotTextNode;

    // const final_text = if (options.escape)
    //     try z.escapeHtml(allocator, text)
    // else
    //     text;

    // defer if (options.escape) allocator.free(final_text);

    const current_len = z.textContent_zc(node.?).len;

    if (lxb_dom_character_data_replace(
        node.?,
        text.ptr,
        text.len,
        0, // Start position
        current_len, // Replace entire content
    ) != z._OK) return Err.SetTextContentFailed;
}

test "replaceTextContent" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("<p>Hello <strong>world</strong></p>");
    defer z.destroyDocument(doc);

    const p = z.firstChild(z.bodyNode(doc).?);
    const inner_text = z.firstChild(p.?);
    try testing.expectEqualStrings(z.textContent_zc(inner_text.?), "Hello ");
    try testing.expectEqualStrings(z.textContent_zc(p.?), "Hello world");

    try replaceText(inner_text.?, "New text");

    const p_text = z.textContent_zc(p.?);
    try testing.expectEqualStrings("New textworld", p_text);
    try testing.expectEqualStrings("New text", z.textContent_zc(inner_text.?));
    const txt = try z.outerHTML(allocator, z.nodeToElement(p.?).?);
    defer allocator.free(txt);
    try testing.expectEqualStrings("<p>New text<strong>world</strong></p>", txt);
}
test "set and replace text content" {
    // const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);
    const element = try z.createElement(doc, "div");
    defer z.destroyNode(z.elementToNode(element));
    const node = z.elementToNode(element);
    var inner_text = z.firstChild(node);

    try testing.expect(inner_text == null);

    try testing.expectError(
        Err.NoNode,
        replaceText(inner_text, "text"),
    );

    const text_node = try z.createTextNode(doc, "");
    z.appendChild(node, text_node);
    inner_text = z.firstChild(node);

    try replaceText(inner_text.?, "Initial text");
    try testing.expectEqualStrings("Initial text", z.textContent_zc(inner_text.?));
}

test "text content" {
    const allocator = testing.allocator;

    const html = "<p>Hello <strong>World</strong>!</p>";
    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    const body = z.bodyElement(doc).?;
    const body_node = z.elementToNode(body);
    const p_node = z.firstChild(body_node).?;
    const text = try z.textContent(
        allocator,
        p_node,
    );
    defer allocator.free(text);

    try testing.expectEqualStrings("Hello World!", text);
    const text_node = z.firstChild(p_node);
    const strong_node = z.nextSibling(text_node.?);
    const strong_text = try z.textContent(
        allocator,
        strong_node.?,
    );
    defer allocator.free(strong_text);
    try testing.expectEqualStrings("World", strong_text);
}

test "getNodeTextContent" {
    const frag = "<p>First<span>Second</span></p><p>Third</p>";
    const allocator = std.testing.allocator;
    const doc = try z.createDocFromString(frag);
    defer z.destroyDocument(doc);

    const body_element = z.bodyElement(doc).?;
    const body_node = z.elementToNode(body_element);

    const first_child = z.firstChild(body_node);
    const second_child = z.nextSibling(first_child.?);

    const all_text = try z.textContent(
        allocator,
        body_node,
    );
    const first_text = try z.textContent(
        allocator,
        first_child.?,
    );
    const second_text = try z.textContent(
        allocator,
        second_child.?,
    );

    defer allocator.free(all_text);
    defer allocator.free(first_text);
    defer allocator.free(second_text);

    try testing.expectEqualStrings("FirstSecondThird", all_text);
    try testing.expectEqualStrings("FirstSecond", first_text);
    try testing.expectEqualStrings("Third", second_text);
}

test "gets all text elements from Fragment" {
    const fragment = "<div><p>First<span>Second</span></p><p>Third</p></div><div><ul><li>Fourth</li><li>Fifth</li></ul></div>";

    const allocator = testing.allocator;
    const doc = try z.createDocFromString(fragment);
    defer z.destroyDocument(doc);
    const body_element = z.bodyElement(doc).?;
    const body_node = z.elementToNode(body_element);
    const text_content = try z.textContent(allocator, body_node);
    defer allocator.free(text_content);
    try testing.expectEqualStrings("FirstSecondThirdFourthFifth", text_content);
}

/// [core] HTML escape text content for safe output
///
/// Caller must free the returned slice.
pub fn escapeHtml(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    for (text) |ch| {
        switch (ch) {
            '<' => try result.appendSlice(allocator, "&lt;"),
            '>' => try result.appendSlice(allocator, "&gt;"),
            '&' => try result.appendSlice(allocator, "&amp;"),
            '"' => try result.appendSlice(allocator, "&quot;"),
            '\'' => try result.appendSlice(allocator, "&#39;"),
            else => try result.append(allocator, ch),
        }
    }

    return result.toOwnedSlice(allocator);
}

test "get & set NodeTextContent and escape option" {
    const allocator = testing.allocator;
    const doc = try z.createDocument();
    const element = try z.createElement(doc, "div");
    defer z.destroyDocument(doc);
    const node = z.elementToNode(element);

    try z.setContentAsText(node, "Hello, world!");

    const text_content = z.textContent_zc(node);

    try testing.expectEqualStrings("Hello, world!", text_content);

    const inner_text = z.firstChild(z.elementToNode(element));
    try replaceText(inner_text.?, "<script>alert('xss')</script> & \"quotes\"");

    const new_escaped_text = try textContent(
        allocator,
        node,
    );
    defer allocator.free(new_escaped_text);
    try testing.expectEqualStrings("<script>alert('xss')</script> & \"quotes\"", new_escaped_text);
}

test "HTML escaping" {
    const allocator = testing.allocator;

    const dangerous_text = "<script>alert('xss')</script> & \"quotes\"";
    const escaped = try z.escapeHtml(allocator, dangerous_text);
    defer allocator.free(escaped);

    const expected = "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt; &amp; &quot;quotes&quot;";
    try testing.expectEqualStrings(expected, escaped);
}

test "first text content & comment" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("<p>hello <em>italic</em></p><br/><!-- \tcomment -->");

    // text content of the P element
    const p = z.firstChild(z.bodyNode(doc).?);
    const p_text = try z.textContent(allocator, p.?);
    defer allocator.free(p_text);
    try testing.expectEqualStrings("hello italic", p_text);
    try testing.expectEqualStrings("hello italic", z.textContent_zc(p.?));

    // text content of the TEXT node
    const inner = z.firstChild(p.?);
    const inner_text = try textContent(allocator, inner.?);
    defer allocator.free(inner_text);
    try testing.expectEqualStrings("hello ", inner_text);
    try testing.expectEqualStrings("hello ", z.textContent_zc(inner.?));

    // text content of the BR element
    const br = z.elementToNode(z.nextElementSibling(z.nodeToElement(p.?).?).?);
    const br_text = z.textContent_zc(br);
    try testing.expectEqualStrings("", br_text);

    // text content of the comment node
    const comment_node = z.nextSibling(br);
    const comment_node_text = try z.textContent(allocator, comment_node.?);
    defer allocator.free(comment_node_text);
    try testing.expectEqualStrings(" \tcomment ", comment_node_text);

    const comment = z.nodeToComment(comment_node.?);
    const comment_text = try commentContent(allocator, comment.?);
    defer allocator.free(comment_text);
    try testing.expectEqualStrings(" \tcomment ", comment_text);
    try testing.expectEqualStrings(" \tcomment ", z.commentContent_zc(comment.?));
}

test "first set text content" {
    const doc = try z.createDocFromString("<p></p><span>first</span>");
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;

    const p = z.firstChild(body).?;
    const span = z.nextSibling(p).?;
    try z.setContentAsText(p, "new text");
    try z.setContentAsText(span, "second");

    const p_text = z.textContent_zc(p);
    try testing.expectEqualStrings("new text", p_text);

    const span_text = z.textContent_zc(span);
    try testing.expectEqualStrings("second", span_text);
}
