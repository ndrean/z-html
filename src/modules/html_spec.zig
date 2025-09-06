//! Unified HTML specification for attributes and elements
//!
//! This module provides a single source of truth for HTML element specifications,
//! including allowed attributes and their valid values. Used by both the sanitizer
//! for security validation and the syntax highlighter for visual styling.

const std = @import("std");
const print = std.debug.print;

/// Specification for an HTML attribute
pub const AttrSpec = struct {
    name: []const u8,
    /// If null, any value is allowed. If provided, only these values are valid.
    valid_values: ?[]const []const u8 = null,
    /// Whether this attribute is considered safe for sanitization
    safe: bool = true,
};

/// Specification for an HTML element
pub const ElementSpec = struct {
    tag: []const u8,
    allowed_attrs: []const AttrSpec,
    /// Whether this element is void (self-closing)
    void_element: bool = false,
};

/// Common attributes that are allowed on most elements
pub const common_attrs = [_]AttrSpec{
    .{ .name = "id" },
    .{ .name = "class" },
    .{ .name = "style" },
    .{ .name = "title" },
    .{ .name = "lang" },
    .{ .name = "width" },
    .{ .name = "height" },
    .{ .name = "dir", .valid_values = &[_][]const u8{ "ltr", "rtl", "auto" } },
    .{ .name = "aria" }, // prefix match for aria-* attributes
    .{ .name = "data" }, // prefix match for data-* attributes
    .{ .name = "hidden", .valid_values = &[_][]const u8{""} }, // boolean attribute
    .{ .name = "role" },
    .{ .name = "tabindex" },
    .{ .name = "contenteditable", .valid_values = &[_][]const u8{ "true", "false", "" } },
    .{ .name = "draggable", .valid_values = &[_][]const u8{ "true", "false", "auto" } },
    .{ .name = "spellcheck", .valid_values = &[_][]const u8{ "true", "false" } },
};

/// Table-specific attributes
pub const table_attrs = [_]AttrSpec{
    .{ .name = "scope", .valid_values = &[_][]const u8{ "col", "row", "colgroup", "rowgroup" } },
    .{ .name = "colspan" },
    .{ .name = "rowspan" },
} ++ common_attrs;

/// Form-specific attributes
pub const form_attrs = [_]AttrSpec{
    .{ .name = "action" },
    .{ .name = "method", .valid_values = &[_][]const u8{ "get", "post" } },
    .{ .name = "enctype" },
    .{ .name = "target" },
} ++ common_attrs;

/// Input-specific attributes
pub const input_attrs = [_]AttrSpec{
    .{ .name = "type", .valid_values = &[_][]const u8{ "text", "email", "password", "number", "tel", "url", "search", "submit", "reset", "button", "hidden" } },
    .{ .name = "name" },
    .{ .name = "value" },
    .{ .name = "placeholder" },
    .{ .name = "required", .valid_values = &[_][]const u8{""} }, // boolean attribute
    .{ .name = "minlength" },
    .{ .name = "maxlength" },
    .{ .name = "readonly", .valid_values = &[_][]const u8{""} }, // boolean attribute
} ++ common_attrs;

/// SVG-specific attributes
pub const svg_attrs = [_]AttrSpec{
    .{ .name = "viewBox" },
    .{ .name = "width" },
    .{ .name = "height" },
    .{ .name = "x" },
    .{ .name = "y" },
    .{ .name = "cx" },
    .{ .name = "cy" },
    .{ .name = "r" },
    .{ .name = "rx" },
    .{ .name = "ry" },
    .{ .name = "d" },
    .{ .name = "fill" },
    .{ .name = "stroke" },
    .{ .name = "stroke-width" },
} ++ common_attrs;

/// Image-specific attributes
pub const img_attrs = [_]AttrSpec{
    .{ .name = "src" },
    .{ .name = "alt" },
    .{ .name = "width" },
    .{ .name = "height" },
    .{ .name = "loading", .valid_values = &[_][]const u8{ "lazy", "eager", "auto" } },
    .{ .name = "decoding", .valid_values = &[_][]const u8{ "sync", "async", "auto" } },
    .{ .name = "srcset" },
    .{ .name = "sizes" },
    .{ .name = "crossorigin", .valid_values = &[_][]const u8{ "anonymous", "use-credentials" } },
    .{ .name = "referrerpolicy" },
    .{ .name = "usemap" },
    .{ .name = "ismap", .valid_values = &[_][]const u8{""} }, // boolean
} ++ common_attrs;

pub const iframe_attrs = [_]AttrSpec{ .{ .name = "src" }, .{ .name = "sandbox" }, .{ .name = "srcdoc" }, .{ .name = "name" }, .{ .name = "loading" } } ++ common_attrs;

/// Anchor-specific attributes
pub const anchor_attrs = [_]AttrSpec{
    .{ .name = "href" },
    .{ .name = "target", .valid_values = &[_][]const u8{ "_blank", "_self", "_parent", "_top" } },
    .{ .name = "rel" },
    .{ .name = "type" },
    .{ .name = "download" },
    .{ .name = "hreflang" },
    .{ .name = "ping" },
    .{ .name = "referrerpolicy" },
} ++ common_attrs;

/// Framework-specific attribute sets (for better organization)
pub const framework_attrs = [_]AttrSpec{
    // Alpine.js attributes
    .{ .name = "x-data" },
    .{ .name = "x-show" },
    .{ .name = "x-model" },
    .{ .name = "x-on" }, // prefix for x-on:*
    .{ .name = "x-bind" }, // prefix for x-bind:*
    .{ .name = "x-if" },
    .{ .name = "x-for" },
    .{ .name = "x-text" },
    .{ .name = "x-html" },
    .{ .name = "x-ref" },
    .{ .name = "x-cloak" },
    .{ .name = "x-ignore" },
    .{ .name = "x-init" },
    .{ .name = "x-transition" },

    // Phoenix LiveView attributes
    .{ .name = "phx-click" },
    .{ .name = "phx-submit" },
    .{ .name = "phx-change" },
    .{ .name = "phx-focus" },
    .{ .name = "phx-blur" },
    .{ .name = "phx-window-focus" },
    .{ .name = "phx-window-blur" },
    .{ .name = "phx-window-keydown" },
    .{ .name = "phx-window-keyup" },
    .{ .name = "phx-key" },
    .{ .name = "phx-value" }, // prefix for phx-value-*
    .{ .name = "phx-disable-with" },
    .{ .name = "phx-loading" },
    .{ .name = "phx-update" },
    .{ .name = "phx-hook" },
    .{ .name = "phx-debounce" },
    .{ .name = "phx-throttle" },
    .{ .name = "phx-target" },

    // Vue.js attributes
    .{ .name = "v-model" },
    .{ .name = "v-if" },
    .{ .name = "v-for" },
    .{ .name = "v-show" },
    .{ .name = "v-on" }, // prefix for v-on:*
    .{ .name = "v-bind" }, // prefix for v-bind:*
    .{ .name = "v-slot" },

    // Angular attributes
    .{ .name = "ng-model" },
    .{ .name = "ng-if" },
    .{ .name = "ng-for" },
    .{ .name = "ng-click" },
    .{ .name = "ng-submit" },
    .{ .name = "ng-change" },
} ++ common_attrs;

/// HTML element specifications
pub const element_specs = [_]ElementSpec{
    // Text elements (commonly used with frameworks)
    .{ .tag = "body", .allowed_attrs = &common_attrs },
    .{ .tag = "p", .allowed_attrs = &framework_attrs },
    .{ .tag = "span", .allowed_attrs = &framework_attrs },
    .{ .tag = "div", .allowed_attrs = &framework_attrs },
    .{ .tag = "h1", .allowed_attrs = &common_attrs },
    .{ .tag = "h2", .allowed_attrs = &common_attrs },
    .{ .tag = "h3", .allowed_attrs = &common_attrs },
    .{ .tag = "h4", .allowed_attrs = &common_attrs },
    .{ .tag = "h5", .allowed_attrs = &common_attrs },
    .{ .tag = "h6", .allowed_attrs = &common_attrs },
    .{ .tag = "strong", .allowed_attrs = &common_attrs },
    .{ .tag = "em", .allowed_attrs = &common_attrs },
    .{ .tag = "i", .allowed_attrs = &common_attrs },
    .{ .tag = "b", .allowed_attrs = &common_attrs },
    .{ .tag = "a", .allowed_attrs = &anchor_attrs },

    // Media elements
    .{ .tag = "img", .allowed_attrs = &img_attrs, .void_element = true },
    .{ .tag = "iframe", .allowed_attrs = &iframe_attrs, .void_element = true },

    // Table elements
    .{ .tag = "table", .allowed_attrs = &table_attrs },
    .{ .tag = "thead", .allowed_attrs = &table_attrs },
    .{ .tag = "tbody", .allowed_attrs = &table_attrs },
    .{ .tag = "tfoot", .allowed_attrs = &table_attrs },
    .{ .tag = "tr", .allowed_attrs = &table_attrs },
    .{ .tag = "th", .allowed_attrs = &table_attrs },
    .{ .tag = "td", .allowed_attrs = &table_attrs },
    .{ .tag = "caption", .allowed_attrs = &table_attrs },

    // Form elements
    .{ .tag = "form", .allowed_attrs = &form_attrs },
    .{ .tag = "input", .allowed_attrs = &input_attrs, .void_element = true },
    .{
        .tag = "button",
        .allowed_attrs = &([_]AttrSpec{
            .{ .name = "type", .valid_values = &[_][]const u8{ "button", "submit", "reset" } },
            .{ .name = "disabled", .valid_values = &[_][]const u8{""} }, // boolean attribute
        } ++ common_attrs),
    },

    // List elements
    .{ .tag = "ul", .allowed_attrs = &common_attrs },
    .{ .tag = "ol", .allowed_attrs = &common_attrs },
    .{ .tag = "li", .allowed_attrs = &common_attrs },

    // Semantic elements
    .{ .tag = "nav", .allowed_attrs = &common_attrs },
    .{ .tag = "header", .allowed_attrs = &common_attrs },
    .{ .tag = "footer", .allowed_attrs = &common_attrs },
    .{ .tag = "main", .allowed_attrs = &common_attrs },
    .{ .tag = "section", .allowed_attrs = &common_attrs },
    .{ .tag = "article", .allowed_attrs = &common_attrs },
    .{ .tag = "aside", .allowed_attrs = &common_attrs },

    // Document elements
    .{ .tag = "html", .allowed_attrs = &common_attrs },
    .{ .tag = "head", .allowed_attrs = &common_attrs },
    .{ .tag = "title", .allowed_attrs = &common_attrs },
    .{ .tag = "meta", .allowed_attrs = &([_]AttrSpec{
        .{ .name = "charset" },
        .{ .name = "name" },
        .{ .name = "content" },
        .{ .name = "http-equiv" },
        .{ .name = "viewport" },
    } ++ common_attrs), .void_element = true },
    .{ .tag = "link", .allowed_attrs = &([_]AttrSpec{
        .{ .name = "rel" },
        .{ .name = "href" },
        .{ .name = "type" },
        .{ .name = "media" },
        .{ .name = "sizes" },
    } ++ common_attrs), .void_element = true },

    // Additional form elements
    .{ .tag = "textarea", .allowed_attrs = &([_]AttrSpec{
        .{ .name = "name" },
        .{ .name = "rows" },
        .{ .name = "cols" },
        .{ .name = "placeholder" },
        .{ .name = "disabled", .valid_values = &[_][]const u8{""} },
        .{ .name = "required", .valid_values = &[_][]const u8{""} },
    } ++ common_attrs) },
    .{ .tag = "select", .allowed_attrs = &([_]AttrSpec{
        .{ .name = "name" },
        .{ .name = "multiple", .valid_values = &[_][]const u8{""} },
        .{ .name = "size" },
        .{ .name = "disabled", .valid_values = &[_][]const u8{""} },
        .{ .name = "required", .valid_values = &[_][]const u8{""} },
    } ++ common_attrs) },
    .{ .tag = "option", .allowed_attrs = &([_]AttrSpec{
        .{ .name = "value" },
        .{ .name = "selected", .valid_values = &[_][]const u8{""} },
        .{ .name = "disabled", .valid_values = &[_][]const u8{""} },
    } ++ common_attrs) },
    .{ .tag = "label", .allowed_attrs = &([_]AttrSpec{
        .{ .name = "for" },
    } ++ common_attrs) },

    // Void elements
    .{ .tag = "br", .allowed_attrs = &common_attrs, .void_element = true },
    .{ .tag = "hr", .allowed_attrs = &common_attrs, .void_element = true },

    // Template elements
    .{ .tag = "template", .allowed_attrs = &common_attrs },

    // SVG elements
    .{ .tag = "svg", .allowed_attrs = &svg_attrs },
    .{ .tag = "circle", .allowed_attrs = &svg_attrs },
    .{ .tag = "rect", .allowed_attrs = &svg_attrs },
    .{ .tag = "path", .allowed_attrs = &svg_attrs },
    .{ .tag = "line", .allowed_attrs = &svg_attrs },
    .{ .tag = "text", .allowed_attrs = &svg_attrs },
};

/// Get the specification for an HTML element by tag name
pub fn getElementSpec(tag: []const u8) ?*const ElementSpec {
    for (&element_specs) |*spec| {
        if (std.mem.eql(u8, spec.tag, tag)) {
            return spec;
        }
    }
    return null;
}

/// Check if an attribute is allowed for a given element
pub fn isAttributeAllowed(element_tag: []const u8, attr_name: []const u8) bool {
    const spec = getElementSpec(element_tag) orelse return false;

    for (spec.allowed_attrs) |attr_spec| {
        if (std.mem.eql(u8, attr_spec.name, attr_name)) {
            return attr_spec.safe;
        }
        // Handle aria-* attributes (prefix match)
        if (std.mem.eql(u8, attr_spec.name, "aria") and std.mem.startsWith(u8, attr_name, "aria-")) {
            return attr_spec.safe;
        }
        // Handle data-* attributes (prefix match)
        if (std.mem.eql(u8, attr_spec.name, "data") and std.mem.startsWith(u8, attr_name, "data-")) {
            return attr_spec.safe;
        }
        // Handle x-* attributes (Alpine.js prefix match)
        if (std.mem.eql(u8, attr_spec.name, "x-on") and std.mem.startsWith(u8, attr_name, "x-on:")) {
            return attr_spec.safe;
        }
        if (std.mem.eql(u8, attr_spec.name, "x-bind") and std.mem.startsWith(u8, attr_name, "x-bind:")) {
            return attr_spec.safe;
        }
        // Handle phx-value-* attributes (Phoenix prefix match)
        if (std.mem.eql(u8, attr_spec.name, "phx-value") and std.mem.startsWith(u8, attr_name, "phx-value-")) {
            return attr_spec.safe;
        }
        // Handle v-* attributes (Vue.js prefix match)
        if (std.mem.eql(u8, attr_spec.name, "v-on") and std.mem.startsWith(u8, attr_name, "v-on:")) {
            return attr_spec.safe;
        }
        if (std.mem.eql(u8, attr_spec.name, "v-bind") and std.mem.startsWith(u8, attr_name, "v-bind:")) {
            return attr_spec.safe;
        }
    }
    return false;
}

/// Check if an attribute value is valid for a given element and attribute
pub fn isAttributeValueValid(element_tag: []const u8, attr_name: []const u8, attr_value: []const u8) bool {
    const spec = getElementSpec(element_tag) orelse return false;

    for (spec.allowed_attrs) |attr_spec| {
        if (std.mem.eql(u8, attr_spec.name, attr_name)) {
            if (attr_spec.valid_values) |valid_values| {
                for (valid_values) |valid_value| {
                    if (std.mem.eql(u8, valid_value, attr_value)) {
                        return true;
                    }
                }
                return false; // Has restrictions but value doesn't match
            }
            return true; // No restrictions on values
        }
        // Handle prefix matches for aria-*, data-*, and framework attributes
        if ((std.mem.eql(u8, attr_spec.name, "aria") and std.mem.startsWith(u8, attr_name, "aria-")) or
            (std.mem.eql(u8, attr_spec.name, "data") and std.mem.startsWith(u8, attr_name, "data-")) or
            (std.mem.eql(u8, attr_spec.name, "x-on") and std.mem.startsWith(u8, attr_name, "x-on:")) or
            (std.mem.eql(u8, attr_spec.name, "x-bind") and std.mem.startsWith(u8, attr_name, "x-bind:")) or
            (std.mem.eql(u8, attr_spec.name, "phx-value") and std.mem.startsWith(u8, attr_name, "phx-value-")) or
            (std.mem.eql(u8, attr_spec.name, "v-on") and std.mem.startsWith(u8, attr_name, "v-on:")) or
            (std.mem.eql(u8, attr_spec.name, "v-bind") and std.mem.startsWith(u8, attr_name, "v-bind:")))
        {
            // Prefix attributes generally allow any values
            return true;
        }
    }
    return false; // Attribute not found
}

/// Get all allowed attributes for an element (useful for autocomplete, etc.)
pub fn getAllowedAttributes(allocator: std.mem.Allocator, element_tag: []const u8) ![][]const u8 {
    const spec = getElementSpec(element_tag) orelse return &[_][]const u8{};

    var attrs = std.ArrayList([]const u8).init(allocator);
    for (spec.allowed_attrs) |attr_spec| {
        try attrs.append(attr_spec.name);
    }
    return attrs.toOwnedSlice(allocator);
}

const testing = std.testing;

test "element spec lookup" {
    const table_spec = getElementSpec("table");
    try testing.expect(table_spec != null);
    try testing.expectEqualStrings("table", table_spec.?.tag);
}

test "attribute validation" {
    // Test allowed attribute
    try testing.expect(isAttributeAllowed("table", "scope"));
    try testing.expect(isAttributeAllowed("th", "scope"));

    // Test disallowed attribute
    try testing.expect(!isAttributeAllowed("table", "onclick"));

    // Test aria attributes
    try testing.expect(isAttributeAllowed("div", "aria-label"));
    try testing.expect(isAttributeAllowed("div", "aria-expanded"));
}

test "attribute value validation" {
    // Test valid scope values
    try testing.expect(isAttributeValueValid("th", "scope", "col"));
    try testing.expect(isAttributeValueValid("th", "scope", "row"));

    // Test invalid scope value
    try testing.expect(!isAttributeValueValid("th", "scope", "invalid"));

    // Test unrestricted attribute (id)
    try testing.expect(isAttributeValueValid("div", "id", "any-value"));

    // Test title attribute on anchor element (should be allowed)
    try testing.expect(isAttributeAllowed("a", "title"));
    try testing.expect(isAttributeValueValid("a", "title", "any title text"));
}
