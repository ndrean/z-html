//! Serialization functions: `innerHTML`, `outerHTML` and a `prettyPrint` utility function.

// =============================================================================
// Serialization Nodes and Elements
// =============================================================================

const std = @import("std");
const z = @import("../root.zig");
const html_spec = @import("html_spec.zig");
const html_tags = @import("html_tags.zig");
const HtmlTag = html_tags.HtmlTag;
const Err = z.Err;

pub const print = std.debug.print;

const testing = std.testing;

const LXB_HTML_SERIALIZE_OPT_UNDEF: c_int = 0x00;

const lxbString = extern struct {
    data: ?[*]u8, // Pointer to string data
    length: usize, // String length
    size: usize, // lexbor Allocated size
};

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

// ==================================================================

/// [Serialize] Serializes the given DOM node to an owned string
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

/// [serializer] Serializes the given element to an owned string
///
/// Caller owns the slice
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

test "inner/outerHTML" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("<p>hi</p>");
    defer z.destroyDocument(doc);
    const body = z.bodyElement(doc).?;

    const outer = try z.outerHTML(allocator, body);
    defer allocator.free(outer);
    try testing.expectEqualStrings("<body><p>hi</p></body>", outer);

    const inner = try z.innerHTML(allocator, body);
    defer allocator.free(inner);
    try testing.expectEqualStrings("<p>hi</p>", inner);
}

// ===================================================================================

/// Context used by the "styler" callback
const ProcessCtx = struct {
    indent: usize = 0,
    opt: usize = 0,
    expect_attr_value: bool,
    found_equal: bool,
    current_element_tag: ?[]const u8 = null,
    current_attribute: ?[]const u8 = null,
    expect_element_next: bool = false, // Next token after < should be element name

    pub fn init(
        indent: usize,
    ) @This() {
        return .{
            .indent = indent,
            .opt = 0,
            .expect_attr_value = false,
            .found_equal = false,
            .current_element_tag = null,
            .current_attribute = null,
            .expect_element_next = false,
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
pub fn prettyPrint(allocator: std.mem.Allocator, node: *z.DomNode) !void {
    // First, apply aggressive normalization for clean TTY display
    if (z.nodeToElement(node)) |element| {
        z.normalizeDOMForDisplay(allocator, element) catch {
            // If normalization fails, continue with original content
        };
    }

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
    if (std.mem.eql(u8, text, "<") or std.mem.eql(u8, text, "</")) {
        // Opening bracket - next token should be element name
        ctx_ptr.expect_element_next = true;
        ctx_ptr.expect_attr_value = false;
        ctx_ptr.found_equal = false;
        applyStyle(z.SyntaxStyle.brackets, text);
        return 0;
    }

    if (std.mem.eql(u8, text, ">") or std.mem.eql(u8, text, "/>")) {
        // Closing bracket - done parsing this element and its attributes
        ctx_ptr.expect_element_next = false;
        ctx_ptr.current_element_tag = null;
        ctx_ptr.expect_attr_value = false;
        ctx_ptr.found_equal = false;
        applyStyle(z.SyntaxStyle.brackets, text);
        return z._CONTINUE;
    }

    // Handle element names (only immediately after < or </)
    if (ctx_ptr.expect_element_next) {
        // Convert string to enum once for better performance
        const tag_enum = z.stringToEnum(z.HtmlTag, text);
        if (tag_enum) |tag| {
            // Use direct enum-based style lookup - O(1) performance
            const tag_style = z.getStyleForElementEnum(tag);
            if (tag_style) |style| {
                ctx_ptr.expect_element_next = false;
                ctx_ptr.current_element_tag = text; // Track current element for attribute validation
                applyStyle(style, text);
                return z._CONTINUE;
            }
        }
    }

    // Handle attributes using unified specification (with intelligent fallback)
    const isAttr = if (ctx_ptr.current_element_tag) |element_tag|
        html_spec.isAttributeAllowed(element_tag, text)
    else
        z.isKnownAttribute(text);

    if (isAttr) {
        ctx_ptr.current_attribute = text; // Track current attribute for value validation
        ctx_ptr.expect_attr_value = true; // Set flag for potential attr_value
        applyStyle(z.SyntaxStyle.attribute, text);
        return z._CONTINUE;
    }

    // Handle the tricky =" sign to signal a potential following attribute value
    const containsEqualSign = std.mem.endsWith(u8, text, "=\"");

    if (containsEqualSign) {
        ctx_ptr.found_equal = true;
        applyStyle(z.Style.DIM_WHITE, text);
        return z._CONTINUE;
    }

    // text following the =" token with whitelisted attribute
    if (ctx_ptr.expect_attr_value and ctx_ptr.found_equal) {
        ctx_ptr.found_equal = false;
        ctx_ptr.expect_attr_value = false;

        // Enhanced attribute value validation using unified specification
        const is_dangerous = z.isDangerousAttributeValue(text);
        var is_valid = true;

        if (ctx_ptr.current_element_tag) |element_tag| {
            if (ctx_ptr.current_attribute) |attr_name| {
                is_valid = html_spec.isAttributeValueValid(element_tag, attr_name, text);
            }
        }

        if (is_dangerous) {
            applyStyle(z.SyntaxStyle.danger, text);
        } else if (!is_valid) {
            // Invalid attribute value - use warning style (yellow)
            applyStyle(z.Style.YELLOW, text);
        } else {
            applyStyle(z.SyntaxStyle.attr_value, text); // Normal styling
        }

        // Reset attribute context
        ctx_ptr.current_attribute = null;
        return z._CONTINUE;
    }

    // text following the =" token without whitelisted attribute: suspicious attribute case
    if (!ctx_ptr.expect_attr_value and ctx_ptr.found_equal) {
        ctx_ptr.expect_attr_value = false;
        ctx_ptr.found_equal = false;
        applyStyle(z.SyntaxStyle.danger, text);
        return z._CONTINUE;
    }

    ctx_ptr.expect_attr_value = false; // Reset state as attributes may have no value
    applyStyle(z.SyntaxStyle.text, text);
    return z._CONTINUE;
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

/// [tree] Debug: Walk and print DOM tree
fn walkTree(node: *z.DomNode, depth: u8) void {
    var child = z.firstChild(node);
    while (child != null) {
        const name = if (z.isTypeElement(child.?)) z.qualifiedName_zc(z.nodeToElement(child.?).?) else z.nodeName_zc(child.?);

        // Convert string to enum and use fast lookup
        const tag_enum = z.stringToEnum(z.HtmlTag, name);
        const ansi_colour = if (tag_enum) |tag| z.getStyleForElementEnum(tag) orelse z.Style.DIM_WHITE else z.Style.DIM_WHITE;
        const ansi_reset = z.Style.RESET;
        const indent = switch (@min(depth, 10)) {
            0 => "",
            1 => "  ",
            2 => "    ",
            3 => "      ",
            4 => "        ",
            5 => "          ",
            else => "            ",
        };
        print("{s}{s}{s}{s}\n", .{ indent, ansi_colour, name, ansi_reset });

        walkTree(child.?, depth + 1);
        child = z.nextSibling(child.?);
    }
}

/// [tree] Debug: print document structure (for debugging)
pub fn printDocStruct(doc: *z.HTMLDocument) !void {
    const root = z.documentRoot(doc).?;
    walkTree(root, 0);
}
