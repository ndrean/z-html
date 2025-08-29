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
// SetInnerHTML - To finish
// -------------------------------------------------------

/// [Serialize] Sets / replaces element's inner HTML with minimal security controls.
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
    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);
    defer z.destroyDocument(doc);

    // const fragment = try z.createDocumentFragment(doc);
    const malicious_content = "<div><!-- a comment --><button onclick=\"alert('XSS')\">Become rich</button><script>alert('XSS')</script><img src=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\"><img src=\"/my-image.jpg\" alt=\"image\"></div>";

    // const fragment_node = z.fragmentToNode(fragment);
    const fragment_root = try z.parseFragmentSimple(
        body,
        malicious_content,
        .div,
    );
    defer z.destroyNode(fragment_root);

    const fragment_txt = try outerNodeHTML(allocator, fragment_root);
    defer allocator.free(fragment_txt);
    // try prettyPrint(fragment_root);

    try testing.expectEqualStrings("<html><div><!-- a comment --><button onclick=\"alert('XSS')\">Become rich</button><script>alert('XSS')</script><img src=\"data:text/html,&lt;script&gt;alert('XSS')&lt;/script&gt;\" alt=\"escaped\"><img src=\"/my-image.jpg\" alt=\"image\"></div></html>", fragment_txt);

    try z.sanitizeNode(allocator, fragment_root); // <- second sanitation pass
    // try prettyPrint(fragment_root); // <- first check what lexbor sanitzed

    z.appendFragment(body, fragment_root);
    // try z.normalize(allocator, body2_elt);
    const html_string = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html_string);

    try testing.expectEqualStrings("<body><div><button>Become rich</button><img alt=\"escaped\"><img src=\"/my-image.jpg\" alt=\"image\"></div></body>", html_string);

    // try prettyPrint(body2);

    // try z.printDocStruct(doc2);
    // try z.prettyPrint(body2);
}

pub fn setSafeInnerHTML(allocator: std.mem.Allocator, element: *z.HTMLElement, context: z.FragmentContext, content: []const u8) !void {
    const node = z.elementToNode(element);

    const fragment_root = try z.parseFragmentSimple(
        node,
        content,
        context,
    );

    try z.sanitizeNode(allocator, fragment_root);
    z.appendFragment(node, fragment_root);
}

test "setSafeInnerHTML" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("");
    defer z.destroyDocument(doc);

    const body_elt = try z.bodyElement(doc);

    try setSafeInnerHTML(
        allocator,
        body_elt,
        .div,
        "<!-- a comment --><script>alert('XSS')</script><p id=\"1\" phx-click=\"increment\">Click me</p>",
    );
    // try z.prettyPrint(z.elementToNode(body_elt));
}

test "Serializer sanitation" {
    const malicious_content = "<div><button disabled hidden onclick=\"alert('XSS')\" phx-click=\"increment\">Potentially dangerous, not escaped</button><!-- a comment --><div data-time=\"{@current}\"> The current value is: {@counter} </div> <a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a><a href=\"javascript:alert('XSS')\">Dangerous, not escaped</a><img src=\"javascript:alert('XSS')\" alt=\"not escaped\"><iframe src=\"javascript:alert('XSS')\" alt=\"not escaped\"></iframe><a href=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\">Safe escaped</a><img src=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\"><iframe src=\"data:text/html,<script>alert('XSS')</script>\" >Escaped</iframe><img src=\"data:image/svg+xml,<svg onload=alert('XSS')\" alt=\"escaped\"></svg>\"><img src=\"data:image/svg+xml;base64,PHN2ZyBvbmxvYWQ9YWxlcnQoJ1hTUycpPjwvc3ZnPg==\" alt=\"potential dangerous b64\"><a href=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgnWFNTJyk8L3NjcmlwdD4=\">Potential dangerous b64</a><img src=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgnWFNTJyk8L3NjcmlwdD4=\" alt=\"potential dangerous b64\"><a href=\"file:///etc/passwd\">Dangerous Local file access</a><img src=\"file:///etc/passwd\" alt=\"dangerous local file access\"><p>Hello<i>there</i>, all<strong>good?</strong></p><p>Visit this link: <a href=\"https://example.com\">example.com</a></p></div><link href=\"/shared-assets/misc/link-element-example.css\" rel=\"stylesheet\"><script>console.log(\"hi\");</script><template></template>";

    const doc = try z.parseFromString("");
    const body = try z.bodyNode(doc);
    defer z.destroyDocument(doc);

    const fragment = try z.createDocumentFragment(doc);
    const fragment_node = z.fragmentToNode(fragment);
    defer z.destroyNode(fragment_node);
    const new_node = try z.parseFragmentSimple(
        body,
        malicious_content,
        .div,
    );
    // try prettyPrint(new_node);

    const allocator = testing.allocator;
    const fragment_txt = try outerNodeHTML(allocator, new_node);
    defer allocator.free(fragment_txt);
    try z.sanitizeNode(allocator, new_node);
    // try prettyPrint(body);
}

test "web component" {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\  <head>
        \\    <meta charset="utf-8">
        \\    <title>element-details - web component using &lt;template&gt; and &lt;slot&gt;</title>
        \\    <style>
        \\      dl { margin-left: 6px; }
        \\      dt { font-weight: bold; color: #217ac0; font-size: 110% }
        \\      dt { font-family: Consolas, "Liberation Mono", Courier }
        \\      dd { margin-left: 16px }
        \\    </style>
        \\  </head>
        \\ <body>
        \\    <h1>element-details - web component using <code>&lt;template&gt;</code> and <code>&lt;slot&gt;</code></h1>
        \\
        \\    <template id="element-details-template">
        \\      <style>
        \\      details {font-family: "Open Sans Light",Helvetica,Arial}
        \\      .name {font-weight: bold; color: #217ac0; font-size: 120%}
        \\      h4 { margin: 10px 0 -8px 0; }
        \\      h4 span { background: #217ac0; padding: 2px 6px 2px 6px }
        \\      h4 span { border: 1px solid #cee9f9; border-radius: 4px }
        \\      h4 span { color: white }
        \\      .attributes { margin-left: 22px; font-size: 90% }
        \\      .attributes p { margin-left: 16px; font-style: italic }
        \\      </style>
        \\      <details>
        \\        <summary>
        \\          <span>
        \\            <code class="name">&lt;<slot name="element-name">NEED NAME</slot>&gt;</code>
        \\            <i class="desc"><slot name="description">NEED DESCRIPTION</slot></i>
        \\          </span>
        \\        </summary>
        \\        <div class="attributes">
        \\          <h4><span>Attributes</span></h4>
        \\          <slot name="attributes"><p>None</p></slot>
        \\        </div>
        \\      </details>
        \\      <hr>
        \\    </template>
        \\
        \\    <element-details>
        \\      <span slot="element-name">slot</span>
        \\      <span slot="description">A placeholder inside a web
        \\        component that users can fill with their own markup,
        \\        with the effect of composing different DOM trees
        \\        together.</span>
        \\      <dl slot="attributes">
        \\        <dt>name</dt>
        \\        <dd>The name of the slot.</dd>
        \\      </dl>
        \\    </element-details>
        \\
        \\    <element-details>
        \\      <span slot="element-name">template</span>
        \\      <span slot="description">A mechanism for holding client-
        \\        side content that is not to be rendered when a page is
        \\        loaded but may subsequently be instantiated during
        \\        runtime using JavaScript.</span>
        \\    </element-details>
        \\
        \\    <script src="main.js"></script>
        \\  </body>
        \\</html>
    ;
    _ = html;
}
