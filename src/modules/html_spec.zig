//! Unified HTML specification for attributes and elements
//!
//! This module provides a single source of truth for HTML element specifications,
//! including allowed attributes and their valid values. Used by both the sanitizer
//! for security validation and the syntax highlighter for visual styling.

const std = @import("std");
const z = @import("../root.zig");
const html_tags = @import("html_tags.zig");
const HtmlTag = html_tags.HtmlTag;
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
    tag_enum: HtmlTag,
    allowed_attrs: []const AttrSpec,
    /// Whether this element is void (self-closing)
    void_element: bool = false,

    /// Get the string representation of the tag
    pub fn tagName(self: @This()) []const u8 {
        return self.tag_enum.toString();
    }
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
    .{ .tag_enum = .body, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .p, .allowed_attrs = &framework_attrs },
    .{ .tag_enum = .span, .allowed_attrs = &framework_attrs },
    .{ .tag_enum = .div, .allowed_attrs = &framework_attrs },
    .{ .tag_enum = .h1, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .h2, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .h3, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .h4, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .h5, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .h6, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .strong, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .em, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .i, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .b, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .code, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .pre, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .blockquote, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .a, .allowed_attrs = &anchor_attrs },

    // Media elements
    .{ .tag_enum = .img, .allowed_attrs = &img_attrs, .void_element = true },
    .{ .tag_enum = .iframe, .allowed_attrs = &iframe_attrs, .void_element = true },

    // Table elements
    .{ .tag_enum = .table, .allowed_attrs = &table_attrs },
    .{ .tag_enum = .thead, .allowed_attrs = &table_attrs },
    .{ .tag_enum = .tbody, .allowed_attrs = &table_attrs },
    .{ .tag_enum = .tfoot, .allowed_attrs = &table_attrs },
    .{ .tag_enum = .tr, .allowed_attrs = &table_attrs },
    .{ .tag_enum = .th, .allowed_attrs = &table_attrs },
    .{ .tag_enum = .td, .allowed_attrs = &table_attrs },
    .{ .tag_enum = .caption, .allowed_attrs = &table_attrs },

    // Form elements
    .{ .tag_enum = .form, .allowed_attrs = &form_attrs },
    .{ .tag_enum = .input, .allowed_attrs = &input_attrs, .void_element = true },
    .{
        .tag_enum = .button,
        .allowed_attrs = &([_]AttrSpec{
            .{ .name = "type", .valid_values = &[_][]const u8{ "button", "submit", "reset" } },
            .{ .name = "disabled", .valid_values = &[_][]const u8{""} }, // boolean attribute
        } ++ common_attrs),
    },
    .{ .tag_enum = .textarea, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "name" },
        .{ .name = "rows" },
        .{ .name = "cols" },
        .{ .name = "placeholder" },
        .{ .name = "disabled", .valid_values = &[_][]const u8{""} },
        .{ .name = "required", .valid_values = &[_][]const u8{""} },
    } ++ common_attrs) },
    .{ .tag_enum = .select, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "name" },
        .{ .name = "multiple", .valid_values = &[_][]const u8{""} },
        .{ .name = "size" },
        .{ .name = "disabled", .valid_values = &[_][]const u8{""} },
        .{ .name = "required", .valid_values = &[_][]const u8{""} },
    } ++ common_attrs) },
    .{ .tag_enum = .option, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "value" },
        .{ .name = "selected", .valid_values = &[_][]const u8{""} },
        .{ .name = "disabled", .valid_values = &[_][]const u8{""} },
    } ++ common_attrs) },
    .{ .tag_enum = .optgroup, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "label" },
        .{ .name = "disabled", .valid_values = &[_][]const u8{""} },
    } ++ common_attrs) },
    .{ .tag_enum = .fieldset, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "disabled", .valid_values = &[_][]const u8{""} },
        .{ .name = "form" },
        .{ .name = "name" },
    } ++ common_attrs) },
    .{ .tag_enum = .legend, .allowed_attrs = &common_attrs },

    // List elements
    .{ .tag_enum = .ul, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .ol, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .li, .allowed_attrs = &common_attrs },

    // Definition list elements
    .{ .tag_enum = .dl, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .dt, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .dd, .allowed_attrs = &common_attrs },

    // Media elements
    .{ .tag_enum = .video, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "src" },
        .{ .name = "controls", .valid_values = &[_][]const u8{""} },
        .{ .name = "autoplay", .valid_values = &[_][]const u8{""} },
        .{ .name = "loop", .valid_values = &[_][]const u8{""} },
        .{ .name = "muted", .valid_values = &[_][]const u8{""} },
        .{ .name = "poster" },
        .{ .name = "preload", .valid_values = &[_][]const u8{ "none", "metadata", "auto" } },
        .{ .name = "width" },
        .{ .name = "height" },
    } ++ common_attrs) },
    .{ .tag_enum = .audio, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "src" },
        .{ .name = "controls", .valid_values = &[_][]const u8{""} },
        .{ .name = "autoplay", .valid_values = &[_][]const u8{""} },
        .{ .name = "loop", .valid_values = &[_][]const u8{""} },
        .{ .name = "muted", .valid_values = &[_][]const u8{""} },
        .{ .name = "preload", .valid_values = &[_][]const u8{ "none", "metadata", "auto" } },
    } ++ common_attrs) },
    .{ .tag_enum = .source, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "src" },
        .{ .name = "type" },
        .{ .name = "media" },
        .{ .name = "sizes" },
        .{ .name = "srcset" },
    } ++ common_attrs), .void_element = true },
    .{ .tag_enum = .track, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "src" },
        .{ .name = "kind", .valid_values = &[_][]const u8{ "subtitles", "captions", "descriptions", "chapters", "metadata" } },
        .{ .name = "srclang" },
        .{ .name = "label" },
        .{ .name = "default", .valid_values = &[_][]const u8{""} },
    } ++ common_attrs), .void_element = true },

    // Semantic elements
    .{ .tag_enum = .nav, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .header, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .footer, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .main, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .section, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .article, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .aside, .allowed_attrs = &common_attrs },

    // Interactive elements
    .{ .tag_enum = .details, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "open", .valid_values = &[_][]const u8{""} },
    } ++ common_attrs) },
    .{ .tag_enum = .summary, .allowed_attrs = &common_attrs },

    // Figure elements
    .{ .tag_enum = .figure, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .figcaption, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .picture, .allowed_attrs = &common_attrs },

    // Map elements
    .{ .tag_enum = .map, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "name" },
    } ++ common_attrs) },
    .{ .tag_enum = .area, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "alt" },
        .{ .name = "coords" },
        .{ .name = "shape", .valid_values = &[_][]const u8{ "default", "rect", "circle", "poly" } },
        .{ .name = "href" },
        .{ .name = "target", .valid_values = &[_][]const u8{ "_blank", "_self", "_parent", "_top" } },
    } ++ common_attrs), .void_element = true },

    // Document elements
    .{ .tag_enum = .html, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .head, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .title, .allowed_attrs = &common_attrs },
    .{ .tag_enum = .meta, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "charset" },
        .{ .name = "name" },
        .{ .name = "content" },
        .{ .name = "http-equiv" },
        .{ .name = "viewport" },
    } ++ common_attrs), .void_element = true },
    .{ .tag_enum = .link, .allowed_attrs = &([_]AttrSpec{
        .{ .name = "rel" },
        .{ .name = "href" },
        .{ .name = "type" },
        .{ .name = "media" },
        .{ .name = "sizes" },
    } ++ common_attrs), .void_element = true },

    // Void elements
    .{ .tag_enum = .br, .allowed_attrs = &common_attrs, .void_element = true },
    .{ .tag_enum = .hr, .allowed_attrs = &common_attrs, .void_element = true },

    // Template elements
    .{ .tag_enum = .template, .allowed_attrs = &common_attrs },

    // SVG elements
    .{ .tag_enum = .svg, .allowed_attrs = &svg_attrs },
    .{ .tag_enum = .circle, .allowed_attrs = &svg_attrs },
    .{ .tag_enum = .rect, .allowed_attrs = &svg_attrs },
    .{ .tag_enum = .path, .allowed_attrs = &svg_attrs },
    .{ .tag_enum = .line, .allowed_attrs = &svg_attrs },
    .{ .tag_enum = .text, .allowed_attrs = &svg_attrs },
};

/// Get the specification for an HTML element by tag name (legacy - prefer getElementSpecFast)
pub fn getElementSpec(tag: []const u8) ?*const ElementSpec {
    // First try fast enum-based lookup
    if (html_tags.tagFromQualifiedName(tag)) |tag_enum| {
        return getElementSpecByEnum(tag_enum);
    }

    // Fallback: Linear search for custom elements not in enum
    // This should rarely be used in practice
    for (&element_specs) |*spec| {
        if (std.mem.eql(u8, spec.tagName(), tag)) {
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

    var attrs: std.ArrayList([]const u8) = .empty;
    for (spec.allowed_attrs) |attr_spec| {
        try attrs.append(allocator, attr_spec.name);
    }
    return attrs.toOwnedSlice(allocator);
}

// === ENUM-BASED LOOKUPS FOR PERFORMANCE ===

/// Create enum-based hash map for O(1) lookups
pub const ElementSpecMap = std.EnumMap(HtmlTag, *const ElementSpec);
const element_spec_map = blk: {
    var map = ElementSpecMap{};
    for (&element_specs) |*spec| {
        map.put(spec.tag_enum, spec);
    }
    break :blk map;
};

/// Fast enum-based element specification lookup (O(1))
pub fn getElementSpecByEnum(tag: HtmlTag) ?*const ElementSpec {
    return element_spec_map.get(tag);
}

/// Fast enum-based attribute validation
pub fn isAttributeAllowedEnum(tag: HtmlTag, attr_name: []const u8) bool {
    const spec = getElementSpecByEnum(tag) orelse return false;

    for (spec.allowed_attrs) |attr_spec| {
        if (std.mem.eql(u8, attr_spec.name, attr_name)) {
            return attr_spec.safe;
        }
        // Handle prefix matches for framework and data attributes
        if ((std.mem.eql(u8, attr_spec.name, "aria") and std.mem.startsWith(u8, attr_name, "aria-")) or
            (std.mem.eql(u8, attr_spec.name, "data") and std.mem.startsWith(u8, attr_name, "data-")) or
            (std.mem.eql(u8, attr_spec.name, "x-on") and std.mem.startsWith(u8, attr_name, "x-on:")) or
            (std.mem.eql(u8, attr_spec.name, "x-bind") and std.mem.startsWith(u8, attr_name, "x-bind:")) or
            (std.mem.eql(u8, attr_spec.name, "phx-value") and std.mem.startsWith(u8, attr_name, "phx-value-")) or
            (std.mem.eql(u8, attr_spec.name, "v-on") and std.mem.startsWith(u8, attr_name, "v-on:")) or
            (std.mem.eql(u8, attr_spec.name, "v-bind") and std.mem.startsWith(u8, attr_name, "v-bind:")))
        {
            return attr_spec.safe;
        }
    }
    return false;
}

/// Fast enum-based void element check
pub fn isVoidElementEnum(tag: HtmlTag) bool {
    return switch (tag) {
        .area, .base, .br, .col, .embed, .hr, .img, .input, .link, .meta, .source, .track, .wbr => true,
        else => false,
    };
}

/// Bridge function: Convert string to enum and use fast lookup
pub fn getElementSpecFast(tag_name: []const u8) ?*const ElementSpec {
    if (html_tags.tagFromQualifiedName(tag_name)) |tag| {
        return getElementSpecByEnum(tag);
    }
    // Fallback to string-based lookup for custom elements
    return getElementSpec(tag_name);
}

/// Bridge function: Convert string to enum and use fast validation
pub fn isAttributeAllowedFast(element_tag: []const u8, attr_name: []const u8) bool {
    if (html_tags.tagFromQualifiedName(element_tag)) |tag| {
        return isAttributeAllowedEnum(tag, attr_name);
    }
    // Fallback to string-based validation for custom elements
    return isAttributeAllowed(element_tag, attr_name);
}

// === INTEGRATION BRIDGES ===

/// Get element specification from DOM element (integrates with html_tags.zig)
pub fn getElementSpecFromElement(element: *z.HTMLElement) ?*const ElementSpec {
    if (html_tags.tagFromElement(element)) |tag| {
        return getElementSpecByEnum(tag);
    }
    // Fallback for custom elements
    const tag_name = z.qualifiedName_zc(element);
    return getElementSpec(tag_name);
}

/// Check if element is void using unified specification
pub fn isVoidElementFromSpec(element: *z.HTMLElement) bool {
    if (html_tags.tagFromElement(element)) |tag| {
        return isVoidElementEnum(tag);
    }
    // Fallback for custom elements (they are never void)
    return false;
}

/// Validate element and attribute combination from DOM element
pub fn validateElementAttributeFromElement(element: *z.HTMLElement, attr_name: []const u8) bool {
    if (html_tags.tagFromElement(element)) |tag| {
        return isAttributeAllowedEnum(tag, attr_name);
    }
    // Fallback for custom elements
    const tag_name = z.qualifiedName_zc(element);
    return isAttributeAllowed(tag_name, attr_name);
}

/// Get all allowed attributes for a DOM element
pub fn getAllowedAttributesFromElement(allocator: std.mem.Allocator, element: *z.HTMLElement) ![][]const u8 {
    if (z.tagFromElement(element)) |tag| {
        if (getElementSpecByEnum(tag)) |spec| {
            var attrs: std.ArrayList([]const u8) = .empty;
            for (spec.allowed_attrs) |attr_spec| {
                try attrs.append(allocator, attr_spec.name);
            }
            return attrs.toOwnedSlice(allocator);
        }
    }
    // Fallback for custom elements
    const tag_name = z.qualifiedName_zc(element);
    return getAllowedAttributes(allocator, tag_name);
}

const testing = std.testing;

test "element spec lookup" {
    // Test enum-based lookup (fast path)
    const table_spec = getElementSpec("table");
    try testing.expect(table_spec != null);
    try testing.expectEqualStrings("table", table_spec.?.tagName());

    // Test unknown element
    const unknown_spec = getElementSpec("unknown-element");
    try testing.expect(unknown_spec == null);

    // Test that fast path and legacy path return same result for known elements
    const div_spec_legacy = getElementSpec("div");
    const div_spec_fast = getElementSpecFast("div");
    try testing.expect(div_spec_legacy != null);
    try testing.expect(div_spec_fast != null);
    try testing.expect(div_spec_legacy == div_spec_fast); // Same pointer
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

test "enum-based functions" {
    // Test getElementSpecByEnum
    const table_spec = getElementSpecByEnum(.table);
    try testing.expect(table_spec != null);
    try testing.expectEqualStrings("table", table_spec.?.tagName());

    // Test isAttributeAllowedEnum
    try testing.expect(isAttributeAllowedEnum(.table, "scope"));
    try testing.expect(isAttributeAllowedEnum(.th, "scope"));
    try testing.expect(!isAttributeAllowedEnum(.table, "onclick"));

    // Test isVoidElementEnum
    try testing.expect(isVoidElementEnum(.img));
    try testing.expect(isVoidElementEnum(.br));
    try testing.expect(isVoidElementEnum(.input));
    try testing.expect(!isVoidElementEnum(.div));
    try testing.expect(!isVoidElementEnum(.table));
}

test "fast bridge functions" {
    // Test getElementSpecFast (string to enum conversion)
    const table_spec = getElementSpecFast("table");
    try testing.expect(table_spec != null);
    try testing.expectEqualStrings("table", table_spec.?.tagName());

    // Test unknown element
    const unknown_spec = getElementSpecFast("unknown-element");
    try testing.expect(unknown_spec == null);

    // Test isAttributeAllowedFast
    try testing.expect(isAttributeAllowedFast("table", "scope"));
    try testing.expect(!isAttributeAllowedFast("table", "onclick"));
    try testing.expect(isAttributeAllowedFast("div", "aria-label"));
}

test "DOM element integration functions" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Create test elements
    const table_element = try z.createElement(doc, "table");
    const img_element = try z.createElement(doc, "img");
    const div_element = try z.createElement(doc, "div");

    // Test getElementSpecFromElement
    const table_spec = getElementSpecFromElement(table_element);
    try testing.expect(table_spec != null);
    try testing.expectEqualStrings("table", table_spec.?.tagName());

    // Test isVoidElementFromSpec
    try testing.expect(isVoidElementFromSpec(img_element));
    try testing.expect(!isVoidElementFromSpec(table_element));
    try testing.expect(!isVoidElementFromSpec(div_element));

    // Test validateElementAttributeFromElement
    try testing.expect(validateElementAttributeFromElement(table_element, "scope"));
    try testing.expect(!validateElementAttributeFromElement(table_element, "onclick"));
    try testing.expect(validateElementAttributeFromElement(div_element, "class"));

    // Test getAllowedAttributesFromElement
    const attrs = try getAllowedAttributesFromElement(testing.allocator, table_element);
    defer testing.allocator.free(attrs);
    try testing.expect(attrs.len > 0);

    // Check that "scope" is in the allowed attributes for table
    var found_scope = false;
    for (attrs) |attr| {
        if (std.mem.eql(u8, attr, "scope")) {
            found_scope = true;
            break;
        }
    }
    try testing.expect(found_scope);
}
