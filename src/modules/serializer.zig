//! Serialization, innerHTML
// =============================================================================
// Serialization Nodes and Elements
// =============================================================================

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

pub const print = std.debug.print;

const testing = std.testing;

const LXB_HTML_SERIALIZE_OPT_UNDEF: c_int = 0x00;

const lxbString = extern struct {
    data: ?[*]u8, // Pointer to string data
    length: usize, // String length
    size: usize, // lexbor Allocated size
};

// extern "c" fn lxb_html_serialize_str(node: *z.DomNode, str: *lxbString) c_int;

// innerHTML
extern "c" fn lxb_html_serialize_deep_str(node: *z.DomNode, str: *lxbString) c_int;
//outerHTML
extern "c" fn lxb_html_serialize_tree_str(node: *z.DomNode, str: *lxbString) usize;

extern "c" fn lxb_html_serialize_pretty_tree_cb(
    node: *z.DomNode,
    opt: usize,
    indent: usize,
    cb: *const fn ([*:0]const u8, len: usize, ctx: *anyopaque) callconv(.c) c_int,
    ctx: ?*anyopaque,
) c_int;

// setInnerHTML
extern "c" fn lxb_html_element_inner_html_set(
    body: *z.HTMLElement,
    inner: [*]const u8,
    inner_len: usize,
) *z.HTMLElement;

pub fn outerNodeHTML(allocator: std.mem.Allocator, node: *z.DomNode) ![]u8 {
    var str = lxbString{
        .data = null,
        .length = 0,
        .size = 0,
    };

    if (lxb_html_serialize_tree_str(node, &str) != z._OK) {
        return Err.SerializeFailed;
    }

    if (str.data == null or str.length == 0) {
        return Err.NoBodyElement;
    }
    const result = try allocator.alloc(u8, str.length);
    @memcpy(result, str.data.?[0..str.length]);

    return result;
}

/// [serializer] Serializes the given DOM node to an owned string
///
/// Caller owns the slice
///
/// OuterHTML === outerHTML
pub fn outerHTML(allocator: std.mem.Allocator, element: *z.HTMLElement) ![]u8 {
    var str = lxbString{
        .data = null,
        .length = 0,
        .size = 0,
    };

    if (lxb_html_serialize_tree_str(z.elementToNode(element), &str) != z._OK) {
        return Err.SerializeFailed;
    }

    if (str.data == null or str.length == 0) {
        return Err.NoBodyElement;
    }
    const result = try allocator.alloc(u8, str.length);
    @memcpy(result, str.data.?[0..str.length]);

    return result;
}

/// [Serialize] Get element's inner HTML
///
/// Caller needs to free the returned slice
pub fn innerHTML(allocator: std.mem.Allocator, element: *z.HTMLElement) ![]u8 {
    if (z.firstElementChild(element) == null) {
        return Err.NoFirstChild;
    }

    var str = lxbString{
        .data = null,
        .length = 0,
        .size = 0,
    };

    const element_node = z.elementToNode(element);

    if (lxb_html_serialize_deep_str(element_node, &str) != z._OK) {
        return Err.SerializeFailed;
    }

    if (str.data == null or str.length == 0) {
        return Err.NoBodyElement;
    }
    const result = try allocator.alloc(u8, str.length);
    @memcpy(result, str.data.?[0..str.length]);
    return result;
}
// ===================================================================================

/// Context used by the "styler" callback
const ProcessCtx = struct {
    indent: usize = 0,
    opt: usize = 0,
    expect_attr_value: bool,
    found_equal: bool,

    pub fn init(
        indent: usize,
    ) @This() {
        return .{
            .indent = indent,
            .opt = 0,
            .expect_attr_value = false,
            .found_equal = false,
        };
    }
};

/// [serializer] Prints the current node in a pretty format
///
/// The styling is defined in the "colours.zig" module.
///
/// It defaults to print to the TTY with `z.Writer.print()`. You can also `log()` into a file.
/// ```
/// try z.Writer.initLog("logfile.log");
/// defer z.Writer.deinitLog();
///
/// const print = z.Writer.log;
/// try z.prettyPrint(body);
///
/// ---
///```
pub fn prettyPrint(node: *z.DomNode) !void {
    const result = prettyPrintOpt(
        node,
        defaultStyler,
        ProcessCtx.init(0),
    );
    if (result != z._OK) {
        return Err.SerializationFailed;
    }
    return;
}

fn prettyPrintOpt(
    node: *z.DomNode,
    styler: *const fn (data: [*:0]const u8, len: usize, context: ?*anyopaque) callconv(.c) c_int,
    ctx: ProcessCtx,
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

/// debug function to apply a \t between each token to visualize them
fn debugTabber(data: [*:0]const u8, len: usize, context: ?*anyopaque) callconv(.c) c_int {
    _ = context;
    _ = len;
    print("{s}|\t", .{data});
    return 0;
}

/// [serializer] Default styling function for serialized output in TTY
fn defaultStyler(data: [*:0]const u8, len: usize, context: ?*anyopaque) callconv(.c) c_int {
    const ctx_ptr: *ProcessCtx = @ptrCast(@alignCast(context.?));
    if (len == 0) return 0;

    const text = data[0..len];

    if (z.isWhitespaceOnlyText(text)) {
        print("{s}", .{text});
        return 0;
    }
    if (len == 1 and std.mem.eql(u8, text, "\"")) {
        applyStyle(z.Style.DIM_WHITE, text);
        return 0;
    }

    // open & closing symbols
    if (std.mem.eql(u8, text, "<") or std.mem.eql(u8, text, ">") or std.mem.eql(u8, text, "</") or std.mem.eql(u8, text, "/>")) {
        ctx_ptr.expect_attr_value = false; // Reset state
        ctx_ptr.found_equal = false;
        applyStyle(z.SyntaxStyle.brackets, text);
        return 0;
    }

    // Handle tags
    const maybeTagStyle = z.getStyleForElement(text);
    if (maybeTagStyle != null) {
        ctx_ptr.expect_attr_value = false;
        applyStyle(maybeTagStyle.?, text);
        return 0;
    }

    // Handle attributes
    const isAttr = z.isKnownAttribute(text);

    if (isAttr) {
        // ctx_ptr.current_attribute = text;
        ctx_ptr.expect_attr_value = true; // Set flag for potential attr_value
        applyStyle(z.SyntaxStyle.attribute, text);
        return 0;
    }

    // Handle the tricky =" sign to signal a potential following attribute value
    const containsEqualSign = std.mem.endsWith(u8, text, "=\"");

    if (containsEqualSign) {
        ctx_ptr.found_equal = true;
        applyStyle(z.Style.DIM_WHITE, text);
        return 0;
    }

    // text following the =" token with whitelisted attribute
    if (ctx_ptr.expect_attr_value and ctx_ptr.found_equal) {
        ctx_ptr.found_equal = false;
        ctx_ptr.expect_attr_value = false;
        if (z.isDangerousAttributeValue(text)) {
            applyStyle(z.SyntaxStyle.danger, text);
        } else {
            applyStyle(z.SyntaxStyle.attr_value, text); // Normal styling
        }
        return 0;
    }

    // text following the =" token without whitelisted attribute: suspicious attribute case
    if (!ctx_ptr.expect_attr_value and ctx_ptr.found_equal) {
        ctx_ptr.expect_attr_value = false;
        ctx_ptr.found_equal = false;
        applyStyle(z.SyntaxStyle.danger, text);
        return 0;
    }

    ctx_ptr.expect_attr_value = false; // Reset state as attributes may have no value
    applyStyle(z.SyntaxStyle.text, text);
    return 0;
}

fn applyStyle(style: []const u8, text: []const u8) void {
    print("{s}", .{style});
    print("{s}", .{text});
    print("{s}", .{z.Style.RESET});
}

test "what does std.mem.endsWith, std.mem.eql find?" {
    const t1 = "onclick=\"";
    const t2 = "=\"";
    try testing.expect(std.mem.endsWith(u8, t1, "=\""));
    try testing.expect(std.mem.eql(u8, t2, "=\""));
}

// -------------------------------------------------------------------------------
// Set Safe  innerHTML - To finish
// -------------------------------------------------------

/// [Serialize] Sets / replaces element's inner HTML with security controls.
pub fn setInnerHTML(element: *z.HTMLElement, content: []const u8) !*z.HTMLElement {
    // const espaced_html = sanitize(allocator, element)
    return lxb_html_element_inner_html_set(element, content.ptr, content.len);
}

test "innerHTML / setInnerHTML" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Create a container element
    var div = try z.createElementAttr(doc, "div", &.{});

    // test 1 --------------
    div = try setInnerHTML(div, "<p id=\"1\">Hello <strong>World</strong></p>");
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
    div = try setInnerHTML(div, complex_html);

    const inner2 = try innerHTML(allocator, div);
    defer allocator.free(inner2);

    const inner3 = try outerHTML(allocator, div);
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

        const serialized_tree = try outerHTML(allocator, z.nodeToElement(element_node).?);
        defer allocator.free(serialized_tree);

        // try testing.expectEqualStrings(serial_node, case.serialized_node);
        try testing.expectEqualStrings(serialized_tree, case.serialized_tree);
    }
}

test "setInnerHTML lexbor security sanitation" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const malicious_content = "<script>alert('XSS')</script><img src=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\"><a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a>";
    const div = try z.createElement(doc, "div");
    _ = try setInnerHTML(div, malicious_content); //<-- lexbor sanitizes this in part

    const outer = try outerHTML(allocator, div);
    defer allocator.free(outer);

    const expected = "<div><script>alert('XSS')</script><img src=\"data:text/html,&lt;script&gt;alert('XSS')&lt;/script&gt;\" alt=\"escaped\"><a href=\"http://example.org/results?search=&lt;img src=x onerror=alert('hello')&gt;\">URL Escaped</a></div>";
    try testing.expectEqualStrings(expected, outer);
}

test "sanitized HTML into a fragment" {
    const allocator = testing.allocator;
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const fragment = try z.createDocumentFragment(doc);
    const malicious_content = "<div><button onclick=\"alert('XSS')\">Become rich</button><script>alert('XSS')</script><img src=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\"><img src=\"/my-image.jpg\" alt=\"image\"></div>";

    const fragment_node = z.fragmentToNode(fragment);
    defer z.destroyNode(fragment_node);
    const new_node = try z.parseFragmentSimple(fragment_node, malicious_content, .div);
    const fragment_txt = try outerNodeHTML(allocator, new_node);
    defer allocator.free(fragment_txt);

    // try prettyPrint(new_node); // <- first check what lexbor sanitzed

    try testing.expectEqualStrings("<html><div><button onclick=\"alert('XSS')\">Become rich</button><script>alert('XSS')</script><img src=\"data:text/html,&lt;script&gt;alert('XSS')&lt;/script&gt;\" alt=\"escaped\"><img src=\"/my-image.jpg\" alt=\"image\"></div></html>", fragment_txt);

    try z.sanitizeNode(allocator, new_node); // <- second sanitation pass

    const doc2 = try z.parseFromString("<html><body></body></html>");
    defer z.destroyDocument(doc2);
    const body2 = try z.bodyNode(doc2);
    z.appendFragment(body2, new_node);
    const body2_elt = z.nodeToElement(body2).?;
    // try z.normalize(allocator, body2_elt);
    const html_string = try z.outerHTML(allocator, body2_elt);
    defer allocator.free(html_string);

    try testing.expectEqualStrings("<body><div><button>Become rich</button><img alt=\"escaped\"><img src=\"/my-image.jpg\" alt=\"image\"></div></body>", html_string);

    // try prettyPrint(body2);

    // try z.printDocStruct(doc2);
    // try z.prettyPrint(body2);
}

test "Serializer sanitation" {
    const doc = try z.parseFromString("<div><button disabled hidden onclick=\"alert('XSS')\" phx-click=\"increment\">Potentially dangerous, not escaped</button><!-- a comment --><div> The current value is: {@counter} </div> <a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a><a href=\"javascript:alert('XSS')\">Dangerous, not escaped</a><img src=\"javascript:alert('XSS')\" alt=\"not escaped\"><iframe src=\"javascript:alert('XSS')\" alt=\"not escaped\"></iframe><a href=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\">Safe escaped</a><img src=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\"><iframe src=\"data:text/html,<script>alert('XSS')</script>\" >Escaped</iframe><img src=\"data:image/svg+xml,<svg onload=alert('XSS')\" alt=\"escaped\"></svg>\"><img src=\"data:image/svg+xml;base64,PHN2ZyBvbmxvYWQ9YWxlcnQoJ1hTUycpPjwvc3ZnPg==\" alt=\"potential dangerous b64\"><a href=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgnWFNTJyk8L3NjcmlwdD4=\">Potential dangerous b64</a><img src=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgnWFNTJyk8L3NjcmlwdD4=\" alt=\"potential dangerous b64\"><a href=\"file:///etc/passwd\">Dangerous Local file access</a><img src=\"file:///etc/passwd\" alt=\"dangerous local file access\"><p>Hello<i>there</i>, all<strong>good?</strong></p><p>Visit this link: <a href=\"https://example.com\">example.com</a></p></div><link href=\"/shared-assets/misc/link-element-example.css\" rel=\"stylesheet\"><script>console.log(\"hi\");</script>");

    defer z.destroyDocument(doc);

    // try prettyPrint(body);
}
