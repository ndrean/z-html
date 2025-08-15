// compile time safety check
const std = @import("std");
const z = @import("zhtml.zig");

const testing = std.testing;
const print = std.debug.print;

/// [HtmlTag] Optional: Parse string to HtmlTag
pub fn parseTag(name: []const u8) ?HtmlTag {
    inline for (std.meta.fields(HtmlTag)) |field| {
        if (std.mem.eql(u8, field.name, name)) {
            return @enumFromInt(field.value);
        }
    }
    return null;
}

/// [HtmlTag] Convert qualified name (lowercase) to HtmlTag enum
pub inline fn fromQualifiedName(qualified_name: []const u8) ?HtmlTag {
    // Fast path: try direct enum lookup (most common case - lowercase)
    if (parseTag(qualified_name)) |tag| {
        return tag;
    }

    // Handle case-insensitive lookup for uppercase tags
    var lowercase_buf: [64]u8 = undefined;
    if (qualified_name.len >= lowercase_buf.len) return null; // Tag name too long

    const lowercase_name = std.ascii.lowerString(lowercase_buf[0..qualified_name.len], qualified_name);
    if (parseTag(lowercase_name)) |tag| {
        return tag;
    }

    // Handle namespaced elements: "svg:circle" -> null (not in our enum)
    if (std.mem.indexOf(u8, qualified_name, ":")) |_| {
        return null; // Namespaced elements not in standard HTML enum
    }

    return null; // Unknown/custom element
}

/// Helper to parse HTML tag with case conversion
pub fn parseTagInsensitive(allocator: std.mem.Allocator, tag_name: []const u8) !?z.HtmlTag {
    // Convert to lowercase for parsing
    var lowercase_name = try allocator.alloc(u8, tag_name.len);
    defer allocator.free(lowercase_name);

    for (tag_name, 0..) |c, i| {
        lowercase_name[i] = std.ascii.toLower(c);
    }

    return z.parseTag(lowercase_name);
}

/// [HtmlTag] Enum that represents the various HTML tags.
///
///  `self.toString` returns the tag name as a string.
///
/// `self.isVoid` checks if the tag is a self-closing element (e.g., `<br>`, `<img>`).
///
///  `self.isNoEscape` checks if the tag should not have its content escaped.
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

    pub fn toString(self: HtmlTag) []const u8 {
        return @tagName(self);
    }

    pub fn isVoid(self: HtmlTag) bool {
        return VoidTagSet.contains(self);
    }

    /// Check if this tag should not have its text content escaped
    pub fn isNoEscape(self: HtmlTag) bool {
        return NoEscapeTagSet.contains(self);
    }
};

/// [HtmlTag] Set of self-closing elements
const VoidTagSet = struct {
    /// Fast inline check if a tag is void (self-closing)
    pub inline fn contains(tag: HtmlTag) bool {
        return switch (tag) {
            .area, .base, .br, .col, .embed, .hr, .img, .input, .link, .meta, .source, .track, .wbr => true,
            else => false,
        };
    }
};

/// [HtmlTag] Set of tags that should not be escaped (modern approach)
const NoEscapeTagSet = struct {
    /// Fast inline check if a tag should not be escaped
    pub inline fn contains(tag: HtmlTag) bool {
        return switch (tag) {
            .script, .style, .iframe => true,
            else => false,
        };
    }
};

/// [HtmlTag] Fast check if element is void/self-closing (FAST enum version)
/// Uses qualified name from lexbor and enum-based lookup for maximum performance
pub fn isVoidElementFast(qualified_name: []const u8) bool {
    const tag = fromQualifiedName(qualified_name) orelse return false;
    return VoidTagSet.contains(tag);
}

/// [HtmlTag] Fast check if element should not have its content escaped
///
/// Uses qualified name from lexbor and enum-based lookup
pub fn isNoEscapeElementFast(qualified_name: []const u8) bool {
    const tag = fromQualifiedName(qualified_name) orelse return false;
    return NoEscapeTagSet.contains(tag);
}

/// [HtmlTag] Extended check for no-escape elements including custom elements
/// Use this if you have custom elements that contain raw code
pub fn isNoEscapeElementExtended(qualified_name: []const u8, custom_no_escape_tags: []const []const u8) bool {
    // First check standard HTML5 tags
    if (isNoEscapeElementFast(qualified_name)) {
        return true;
    }

    // Then check custom tags
    for (custom_no_escape_tags) |custom_tag| {
        if (std.mem.eql(u8, qualified_name, custom_tag)) {
            return true;
        }
    }

    return false;
}
// =================================================================
// === Tests ===

test "fromQualifiedName enum conversion" {
    // Test standard HTML tags
    try testing.expect(fromQualifiedName("div").? == HtmlTag.div);
    try testing.expect(fromQualifiedName("p").? == HtmlTag.p);
    try testing.expect(fromQualifiedName("script").? == HtmlTag.script);

    // Test custom elements
    try testing.expect(fromQualifiedName("custom-element") == null);
    try testing.expect(fromQualifiedName("my-widget") == null);

    // Test namespaced elements
    try testing.expect(fromQualifiedName("svg:circle") == null);
    try testing.expect(fromQualifiedName("math:equation") == null);
}

test "custom elements and web components" {
    // Standard HTML5 elements
    try testing.expect(isVoidElementFast("br") == true);
    try testing.expect(isNoEscapeElementFast("script") == true);

    // Custom elements/Web components (safe defaults)
    try testing.expect(isVoidElementFast("my-widget") == false); // Not void
    try testing.expect(isNoEscapeElementFast("my-widget") == false); // DO escape (safer)
    try testing.expect(isVoidElementFast("custom-button") == false);
    try testing.expect(isNoEscapeElementFast("custom-button") == false);

    // Web component naming conventions
    try testing.expect(isVoidElementFast("x-calendar") == false);
    try testing.expect(isNoEscapeElementFast("x-calendar") == false);

    // Extended function with custom no-escape tags
    const custom_no_escape = [_][]const u8{ "code-editor", "syntax-highlighter" };
    try testing.expect(isNoEscapeElementExtended("script", &custom_no_escape) == true); // Standard
    try testing.expect(isNoEscapeElementExtended("code-editor", &custom_no_escape) == true); // Custom
    try testing.expect(isNoEscapeElementExtended("my-widget", &custom_no_escape) == false); // Regular custom
}

test "FAST enum-based functions" {
    // Test the FAST enum-based functions
    try testing.expect(isVoidElementFast("br") == true);
    try testing.expect(isVoidElementFast("img") == true);
    try testing.expect(isVoidElementFast("div") == false);

    try testing.expect(isNoEscapeElementFast("script") == true);
    try testing.expect(isNoEscapeElementFast("style") == true);
    try testing.expect(isNoEscapeElementFast("div") == false);

    // Test case insensitivity
    try testing.expect(isVoidElementFast("BR") == true);
    try testing.expect(isVoidElementFast("IMG") == true);
    try testing.expect(isNoEscapeElementFast("SCRIPT") == true);

    // Fast version doesn't handle obsolete tags (returns false)
    try testing.expect(isNoEscapeElementFast("xmp") == false); // Not in HTML5 enum
}

test "parseHtmlTag" {
    const good_tag = parseTag("div");
    try testing.expect(good_tag.? == HtmlTag.div);

    const custom_tag = parseTag("custom-element");
    try testing.expect(custom_tag == null);
}

test "isVoid tag" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Test all void tags
    const void_tags = [_]HtmlTag{ .area, .base, .br };

    for (void_tags) |tag| {
        try testing.expect(tag.isVoid());
    }

    const non_void_tags = [_]HtmlTag{ .div, .p, .span, .a };

    for (non_void_tags) |tag| {
        try testing.expect(!tag.isVoid());
    }
}

test "isVoidElementFast with various tags" {
    // Test the updated isVoidElementFast function
    try testing.expect(isVoidElementFast("br") == true);
    try testing.expect(isVoidElementFast("img") == true);
    try testing.expect(isVoidElementFast("div") == false);
    try testing.expect(isVoidElementFast("custom-element") == false);
    try testing.expect(isVoidElementFast("BR") == true); // Case insensitive
    try testing.expect(isVoidElementFast("IMG") == true);
}
test "lexbor NODENAME and self.toString" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Test all enum variants work
    const tags = [_]z.HtmlTag{ .div, .p, .span, .a, .img, .br };

    for (tags) |tag| {
        const element = try z.createElement(doc, tag.toString(), &.{});
        const node_name = z.nodeName(z.elementToNode(element));
        const expected_name = tag.toString();

        // Note: DOM names are typically uppercase
        try testing.expect(std.ascii.eqlIgnoreCase(expected_name, node_name));
    }
}

test "mixing enum and string creation" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const div = try z.createElement(
        doc,
        "div",
        &.{},
    );

    const custom = try z.createElement(
        doc,
        "my-custom-element",
        &.{},
    );
    const web_component = try z.createElement(
        doc,
        "x-widget",
        &.{},
    );

    try testing.expectEqualStrings("DIV", z.nodeName(z.elementToNode(div)));
    try testing.expectEqualStrings("MY-CUSTOM-ELEMENT", z.nodeName(z.elementToNode(custom)));
    try testing.expectEqualStrings("X-WIDGET", z.nodeName(z.elementToNode(web_component)));
    try testing.expectEqualStrings("DIV", z.tagName(div));
    try testing.expectEqualStrings("MY-CUSTOM-ELEMENT", z.tagName(custom));
    try testing.expectEqualStrings("X-WIDGET", z.tagName(web_component));

    const allocator = testing.allocator;

    const qcustom = try z.qualifiedName(allocator, custom);
    defer allocator.free(qcustom);
    try testing.expectEqualStrings("my-custom-element", qcustom);

    const qdiv = try z.qualifiedName(allocator, div);
    defer allocator.free(qdiv);
    try testing.expectEqualStrings("div", qdiv);
}
