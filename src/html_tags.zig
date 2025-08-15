// compile time safety check
const std = @import("std");
const z = @import("zhtml.zig");

const testing = std.testing;
const print = std.debug.print;

/// [HtmlTag] Element tag representation.
///
/// This represents an HTML element tag, which can either be a standard tag (from the enum)
/// or a custom tag (from a string).
///
/// Exposes two helper functions: `fromEnum` and `fromString`
pub const ElementTag = union(enum) {
    tag: HtmlTag,
    custom: []const u8,

    /// Helper to create from enum
    pub fn fromEnum(html_tag: HtmlTag) ElementTag {
        return ElementTag{ .tag = html_tag };
    }

    /// Helper to create from string
    pub fn fromString(tag_name: []const u8) ElementTag {
        return ElementTag{ .custom = tag_name };
    }
};

/// [HtmlTag] Optional: Parse string to HtmlTag
pub fn parseTag(name: []const u8) ?HtmlTag {
    inline for (std.meta.fields(HtmlTag)) |field| {
        if (std.mem.eql(u8, field.name, name)) {
            return @enumFromInt(field.value);
        }
    }
    return null;
}

/// [HtmlTag] FAST: Convert qualified name to HtmlTag enum (optimized for lexbor output)
///
/// This is the key function you wanted! Takes lexbor's qualifiedName result and returns enum.
/// Optimized for the common case where qualified names are lowercase (from lexbor).
pub inline fn fromQualifiedName(qualified_name: []const u8) ?HtmlTag {
    // Fast path: try direct enum lookup (most common case)
    if (parseTag(qualified_name)) |tag| {
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

/// [HtmlTag] Set of self-closing elements (modern approach)
const VoidTagSet = struct {
    /// Fast inline check if a tag is void (self-closing)
    pub inline fn contains(tag: HtmlTag) bool {
        return switch (tag) {
            .area, .base, .br, .col, .embed, .hr, .img, .input, .link, .meta, .source, .track, .wbr => true,
            else => false,
        };
    }
};

/// [HtmlTag] List of self-closing elements (DEPRECATED: use VoidTagSet instead)
const HtmlVoidTag = [_]HtmlTag{ .area, .base, .br, .col, .embed, .hr, .img, .input, .link, .meta, .source, .track, .wbr };

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

/// [HtmlTag] List of tags that should not be escaped (string version - DEPRECATED)
/// Note: Includes obsolete tags like XMP, NOEMBED, NOFRAMES, PLAINTEXT
const no_escape_tags = [_][]const u8{ "script", "style", "xmp", "iframe", "noembed", "noframes", "plaintext" };

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

/// [HtmlTag] DEPRECATED: Check if an element is a void (self-closing) element using string comparison
pub fn isVoidElement(tag: []const u8) bool {
    // Convert to lowercase for parsing (lexbor often returns uppercase)
    var lowercase_buf: [64]u8 = undefined; // Should be enough for any HTML tag
    if (tag.len >= lowercase_buf.len) return false; // Unknown long tag, assume not void

    const lowercase_tag = std.ascii.lowerString(lowercase_buf[0..tag.len], tag);

    if (parseTag(lowercase_tag)) |html_tag| {
        return html_tag.isVoid();
    }
    return false; // Unknown tags are not void
}

/// [HtmlTag] DEPRECATED: Use isNoEscapeElementFast instead
pub fn isNoEscapeElement(tag: []const u8) bool {
    // Convert to lowercase for parsing (lexbor often returns uppercase)
    var lowercase_buf: [64]u8 = undefined; // Should be enough for any HTML tag
    if (tag.len >= lowercase_buf.len) return false; // Unknown long tag, assume not void
    const lowercase_tag = std.ascii.lowerString(lowercase_buf[0..tag.len], tag);

    for (no_escape_tags) |no_escape_tag| {
        if (std.mem.eql(u8, lowercase_tag, no_escape_tag)) {
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

test "FAST enum-based functions vs SLOW string comparison" {
    // Test the FAST enum-based functions
    try testing.expect(isVoidElementFast("br") == true);
    try testing.expect(isVoidElementFast("img") == true);
    try testing.expect(isVoidElementFast("div") == false);

    try testing.expect(isNoEscapeElementFast("script") == true);
    try testing.expect(isNoEscapeElementFast("style") == true);
    try testing.expect(isNoEscapeElementFast("div") == false);

    // Verify void element functions match
    try testing.expect(isVoidElementFast("br") == isVoidElement("br"));
    try testing.expect(isVoidElementFast("img") == isVoidElement("img"));
    try testing.expect(isVoidElementFast("div") == isVoidElement("div"));

    // Note: No-escape functions differ for obsolete tags like XMP, NOEMBED, etc.
    // The fast version only handles modern HTML5 tags, which is usually what you want.
    try testing.expect(isNoEscapeElementFast("script") == true);
    try testing.expect(isNoEscapeElement("script") == true); // Both should agree on modern tags

    // Fast version doesn't handle obsolete tags (returns false)
    try testing.expect(isNoEscapeElementFast("xmp") == false); // Not in HTML5 enum
    try testing.expect(isNoEscapeElement("xmp") == true); // String version handles it
}

test "parseHtmlTag" {
    const good_tag = parseTag("div");
    try testing.expect(good_tag.? == HtmlTag.div);

    const custom_tag = parseTag("custom-element");
    try testing.expect(custom_tag == null);
}

test "elementTag" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Test creating elements from enum
    const div_elt = try z.createElement(doc, "div", &.{});

    const node_name = z.nodeName(z.elementToNode(div_elt));
    const expected_name = HtmlTag.div.toString();

    // Note: DOM names are typically uppercase
    try testing.expect(std.ascii.eqlIgnoreCase(expected_name, node_name));

    // Test creating elements from string
    const custom_elt = try z.createElement(
        doc,
        // .{ .custom = "custom-element" },
        "custom-element",
        &.{},
    );

    const custom_node_name = z.nodeName(z.elementToNode(custom_elt));
    const custom_expected_name = "custom-element";

    // Note: DOM names are typically uppercase
    try testing.expect(std.ascii.eqlIgnoreCase(custom_expected_name, custom_node_name));
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

test "isVoidElement modernized with html_tags" {
    // Test the updated isVoidElement function
    try testing.expect(isVoidElement("br") == true);
    try testing.expect(isVoidElement("img") == true);
    try testing.expect(isVoidElement("div") == false);
    try testing.expect(isVoidElement("custom-element") == false);
    try testing.expect(isVoidElement("BR") == true); // Case insensitive
    try testing.expect(isVoidElement("IMG") == true);
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
    // const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Type-safe enum creation
    const div = try z.createElement(
        doc,
        "div",
        &.{},
    );

    // Flexible string creation (for custom elements)
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

    // Verify they work
    try testing.expectEqualStrings("DIV", z.nodeName(z.elementToNode(div)));
    try testing.expectEqualStrings("MY-CUSTOM-ELEMENT", z.nodeName(z.elementToNode(custom)));
    try testing.expectEqualStrings("X-WIDGET", z.nodeName(z.elementToNode(web_component)));
}
