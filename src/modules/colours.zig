//! Terminal Colors and Security Validation for HTML Processing
//!
//! This module provides:
//! 1. ANSI terminal styling for colored HTML pretty-printing
//! 2. Security validation for detecting potentially malicious HTML attributes and values
//!
//! ## XSS Prevention Strategies
//!
//! The security functions in this module detect common XSS attack vectors:
//!
//! ### Dangerous Attribute Values (`isDangerousAttributeValue`):
//! - **Script injection**: `<script>`, `javascript:`, `vbscript:` protocols
//! - **Data URIs**: Base64-encoded content that browsers will decode and execute
//! - **File protocols**: `file:`, `ftp:` for local file access attempts
//! - **Protocol-relative URLs**: `//` that can bypass protocol restrictions
//!
//! ### Attribute Validation (`isKnownAttribute`):
//! - **Allowlist approach**: Only known HTML, ARIA, data-*, and framework attributes
//! - **Event handler rejection**: Blocks `onclick`, `onload`, and similar dangerous handlers
//! - **Framework support**: Recognizes Alpine.js, Vue.js, Phoenix LiveView, HTMX patterns
//!
//! ### Security Philosophy:
//! This module follows a defense-in-depth approach where:
//! 1. Unknown attributes are flagged for visual inspection during pretty-printing
//! 2. Dangerous values are highlighted in red to draw attention
//! 3. The sanitizer module can then remove flagged content based on security policies
//!
//! ## Terminal Styling
//!
//! Provides semantic color mapping for HTML elements to improve readability:
//! - Structure elements (html, body) get distinct background colors
//! - Headings use bold red/magenta hierarchy
//! - Interactive elements (forms, buttons) use green themes
//! - Media elements use purple themes
//! - Security risks are highlighted in red

const std = @import("std");
const z = @import("../root.zig");
const html_spec = @import("html_spec.zig");
const html_tags = @import("html_tags.zig");
const HtmlTag = html_tags.HtmlTag;
const Err = z.Err;
// const print = z.Writer.print;
const print = std.debug.print;
const testing = std.testing;

// ANSI escape codes for styling in the terminal
const AnsiCode = enum(u8) {
    // Text effects
    RESET = 0,
    BOLD = 1,
    DIM = 2,
    ITALIC = 3,
    UNDERLINE = 4,
    SLOW_BLINK = 5,
    RAPID_BLINK = 6,
    REVERSE = 7,
    STRIKETHROUGH = 9,

    // Foreground colors (30-37)
    FG_BLACK = 30,
    FG_RED = 31,
    FG_GREEN = 32,
    FG_YELLOW = 33,
    FG_BLUE = 34,
    FG_MAGENTA = 35,
    FG_CYAN = 36,
    FG_WHITE = 37,

    // Background colors (40-47)
    BG_BLACK = 40,
    BG_RED = 41,
    BG_GREEN = 42,
    BG_YELLOW = 43,
    BG_BLUE = 44,
    BG_MAGENTA = 45,
    BG_CYAN = 46,
    BG_WHITE = 47,
};

// Escape colour codes
pub const Style = struct {
    pub const RESET = "\x1b[0m";
    // Plain colors
    pub const BLACK = "\x1b[30m";
    pub const RED = "\x1b[31m";
    pub const GREEN = "\x1b[32m";
    pub const YELLOW = "\x1b[33m";
    pub const BLUE = "\x1b[34m";
    pub const MAGENTA = "\x1b[35m";
    pub const CYAN = "\x1b[36m";
    pub const WHITE = "\x1b[37m";
    pub const PURPLE = "\x1b[38;2;102;51;153m";
    pub const ORANGE = "\x1b[38;5;208m";

    // Bold colors (for headings, important elements)
    pub const BOLD_RED = "\x1b[1;31m";
    pub const BOLD_GREEN = "\x1b[1;32m";
    pub const BOLD_YELLOW = "\x1b[1;33m";
    pub const BOLD_BLUE = "\x1b[1;34m";
    pub const BOLD_MAGENTA = "\x1b[1;35m";
    pub const BOLD_CYAN = "\x1b[1;36m";
    pub const BOLD_WHITE = "\x1b[1;37m";
    pub const BOLD_PURPLE = "\x1b[1;38;2;102;51;153m";
    pub const BOLD_ORANGE = "\x1b[1;38;5;208m";

    // Italic colors (for emphasis, attributes)
    pub const ITALIC_RED = "\x1b[3;31m";
    pub const ITALIC_GREEN = "\x1b[3;32m";
    pub const ITALIC_YELLOW = "\x1b[3;33m";
    pub const ITALIC_BLUE = "\x1b[3;34m";
    pub const ITALIC_MAGENTA = "\x1b[3;35m";
    pub const ITALIC_CYAN = "\x1b[3;36m";
    pub const ITALIC_WHITE = "\x1b[3;37m";
    pub const ITALIC_PURPLE = "\x1b[3;38;2;102;51;153m";
    pub const ITALIC_ORANGE = "\x1b[3;38;5;208m";

    // Underlined colors (for links)
    pub const UNDERLINE_RED = "\x1b[4;31m";
    pub const UNDERLINE_GREEN = "\x1b[4;32m";
    pub const UNDERLINE_YELLOW = "\x1b[4;33m";
    pub const UNDERLINE_BLUE = "\x1b[4;34m";
    pub const UNDERLINE_MAGENTA = "\x1b[4;35m";
    pub const UNDERLINE_CYAN = "\x1b[4;36m";
    pub const UNDERLINE_WHITE = "\x1b[4;37m";
    pub const UNDERLINE_PURPLE = "\x1b[4;38;2;102;51;153m";
    pub const UNDERLINE_ORANGE = "\x1b[4;38;5;208m";

    // Inverse colors (for code blocks)
    pub const INVERSE_RED = "\x1b[7;31m";
    pub const INVERSE_GREEN = "\x1b[7;32m";
    pub const INVERSE_YELLOW = "\x1b[7;33m";
    pub const INVERSE_BLUE = "\x1b[7;34m";
    pub const INVERSE_MAGENTA = "\x1b[7;35m";
    pub const INVERSE_CYAN = "\x1b[7;36m";
    pub const INVERSE_WHITE = "\x1b[7;37m";
    pub const INVERSE_PURPLE = "\x1b[7;38;2;102;51;153m";
    pub const INVERSE_ORANGE = "\x1b[7;38;5;208m";

    // Combined effects for special elements
    pub const BOLD_ITALIC_RED = "\x1b[1;3;31m";
    pub const BOLD_ITALIC_GREEN = "\x1b[1;3;32m";
    pub const BOLD_ITALIC_YELLOW = "\x1b[1;3;33m";
    pub const BOLD_ITALIC_BLUE = "\x1b[1;3;34m";
    pub const BOLD_ITALIC_MAGENTA = "\x1b[1;3;35m";
    pub const BOLD_ITALIC_CYAN = "\x1b[1;3;36m";
    pub const BOLD_ITALIC_WHITE = "\x1b[1;3;37m";
    pub const BOLD_ITALIC_PURPLE = "\x1b[1;3;38;2;102;51;153m";
    pub const BOLD_ITALIC_ORANGE = "\x1b[1;3;38;5;208m";

    pub const DIM_RED = "\x1b[2;31m";
    pub const DIM_GREEN = "\x1b[2;32m";
    pub const DIM_YELLOW = "\x1b[2;33m";
    pub const DIM_WHITE = "\x1b[2;37m";

    // with background

    pub const BODY = "\x1b[1;7;37m";
    pub const WHITE_BLACK = "\x1b[1;37;40m";
    pub const YELLOW_BLACK = "\x1b[1;33;40m";
    pub const BLACK_YELLOW = "\x1b[1;30;43m";
    pub const RED_WHITE = "\x1b[1;31;47m";
    pub const MAGENTA_WHITE = "\x1b[1;35;47m";

    // Underline bold for table headers
    pub const UNDERLINE_BOLD_WHITE = "\x1b[4;1;37m";
    pub const UNDERLINE_BOLD_CYAN = "\x1b[4;1;36m";
};

/// Default colour styles for HTML elements
pub const ElementStyles = struct {
    pub const html = Style.BOLD_CYAN;
    pub const head = Style.INVERSE_CYAN;
    pub const body = Style.INVERSE_GREEN;
    pub const title = Style.BOLD_BLUE;
    pub const meta = Style.BLUE;
    pub const link = Style.UNDERLINE_GREEN;
    pub const script = Style.YELLOW;
    pub const style = Style.YELLOW;

    pub const h1 = Style.BOLD_RED;
    pub const h2 = Style.RED;
    pub const h3 = Style.MAGENTA;
    pub const h4 = Style.MAGENTA;
    pub const h5 = Style.MAGENTA;
    pub const h6 = Style.MAGENTA;

    pub const p = Style.BLUE;
    pub const div = Style.CYAN;
    pub const span = Style.WHITE;
    pub const strong = Style.BOLD_WHITE;
    pub const em = Style.ITALIC_YELLOW;
    pub const i = Style.ITALIC_YELLOW;
    pub const code = Style.INVERSE_ORANGE;
    pub const pre = Style.ORANGE;
    pub const br = Style.WHITE;
    pub const hr = Style.WHITE;

    pub const a = Style.UNDERLINE_BLUE;
    pub const nav = Style.BOLD_BLUE;

    pub const ul = Style.PURPLE;
    pub const ol = Style.PURPLE;
    pub const li = Style.WHITE;

    pub const table = Style.BOLD_CYAN;
    pub const tr = Style.CYAN;
    pub const td = Style.WHITE;
    pub const th = Style.ITALIC_WHITE;

    pub const form = Style.GREEN;
    pub const input = Style.GREEN;
    pub const textarea = Style.GREEN;
    pub const button = Style.BOLD_GREEN;
    pub const select = Style.GREEN;
    pub const option = Style.WHITE;
    pub const label = Style.GREEN;

    pub const header = Style.INVERSE_BLUE;
    pub const footer = Style.BOLD_BLUE;
    pub const main = Style.BOLD_BLUE;
    pub const section = Style.BLUE;
    pub const article = Style.BLUE;
    pub const aside = Style.BLUE;

    pub const img = Style.CYAN;
    pub const video = Style.PURPLE;
    pub const audio = Style.PURPLE;
    pub const canvas = Style.PURPLE;
    pub const svg = Style.PURPLE;
};

/// Enum-based style lookup map for O(1) performance
const StyleMap = std.EnumMap(HtmlTag, []const u8);
const element_style_map = blk: {
    var map = StyleMap{};

    // Document structure
    map.put(.html, ElementStyles.html);
    map.put(.head, ElementStyles.head);
    map.put(.body, ElementStyles.body);
    map.put(.title, ElementStyles.title);
    map.put(.meta, ElementStyles.meta);
    map.put(.link, ElementStyles.link);
    map.put(.script, ElementStyles.script);
    map.put(.style, ElementStyles.style);

    // Headings
    map.put(.h1, ElementStyles.h1);
    map.put(.h2, ElementStyles.h2);
    map.put(.h3, ElementStyles.h3);
    map.put(.h4, ElementStyles.h4);
    map.put(.h5, ElementStyles.h5);
    map.put(.h6, ElementStyles.h6);

    // Text content
    map.put(.p, ElementStyles.p);
    map.put(.div, ElementStyles.div);
    map.put(.span, ElementStyles.span);
    map.put(.strong, ElementStyles.strong);
    map.put(.em, ElementStyles.em);
    map.put(.i, ElementStyles.i);
    map.put(.code, ElementStyles.code);
    map.put(.pre, ElementStyles.pre);
    map.put(.br, ElementStyles.br);
    map.put(.hr, ElementStyles.hr);

    // Links and navigation
    map.put(.a, ElementStyles.a);
    map.put(.nav, ElementStyles.nav);

    // Lists
    map.put(.ul, ElementStyles.ul);
    map.put(.ol, ElementStyles.ol);
    map.put(.li, ElementStyles.li);

    // Tables
    map.put(.table, ElementStyles.table);
    map.put(.tr, ElementStyles.tr);
    map.put(.td, ElementStyles.td);
    map.put(.th, ElementStyles.th);

    // Forms
    map.put(.form, ElementStyles.form);
    map.put(.input, ElementStyles.input);
    map.put(.textarea, ElementStyles.textarea);
    map.put(.button, ElementStyles.button);
    map.put(.select, ElementStyles.select);
    map.put(.option, ElementStyles.option);
    map.put(.label, ElementStyles.label);

    // Semantic elements
    map.put(.header, ElementStyles.header);
    map.put(.footer, ElementStyles.footer);
    map.put(.main, ElementStyles.main);
    map.put(.section, ElementStyles.section);
    map.put(.article, ElementStyles.article);
    map.put(.aside, ElementStyles.aside);

    // Media
    map.put(.img, ElementStyles.img);
    map.put(.video, ElementStyles.video);
    map.put(.audio, ElementStyles.audio);
    map.put(.canvas, ElementStyles.canvas);
    map.put(.svg, ElementStyles.svg);

    break :blk map;
};

/// Default syntax & attributes `Style`
pub const SyntaxStyle = struct {
    pub const brackets = Style.DIM_WHITE;
    pub const attribute = Style.ITALIC_ORANGE;
    // DEFAULT style for ALL attributes
    pub const text = Style.WHITE;
    pub const attr_equal = Style.ITALIC_ORANGE;
    pub const attr_value = Style.MAGENTA;
    pub const danger = Style.INVERSE_RED; // for <script>, <style> content
};

/// Check if the attribute is a known HTML attribute,
///
/// Check if attribute is known, including ARIA, data-*, or framework attributes (Phoenix, Alpine, Vue, HTMX)
/// This is a fallback function when no element context is available
pub fn isKnownAttribute(attr: []const u8) bool {
    // Primary: Use unified specification
    if (isStandardHtmlAttribute(attr)) {
        return true;
    }

    // Fallback: Handle dynamic framework attribute patterns when no element context available
    // These are now mostly covered by the unified spec, but kept for backwards compatibility

    // ARIA and data attributes (handled by unified spec prefix matching)
    if (std.mem.startsWith(u8, attr, "aria-") and attr.len > 5) {
        return true; // aria-*
    }
    if (std.mem.startsWith(u8, attr, "data-") and attr.len > 5) {
        return true; // data-*
    }

    // Framework dynamic attributes (x-on:click, v-bind:value, etc.)
    if (std.mem.startsWith(u8, attr, "x-on:") or std.mem.startsWith(u8, attr, "x-bind:")) {
        return true; // Alpine.js dynamic
    }
    if (std.mem.startsWith(u8, attr, "v-on:") or std.mem.startsWith(u8, attr, "v-bind:")) {
        return true; // Vue.js dynamic
    }
    if (std.mem.startsWith(u8, attr, "phx-value-")) {
        return true; // Phoenix dynamic
    }

    // HTMX (not yet in unified spec)
    if (std.mem.startsWith(u8, attr, "hx-") and attr.len > 3) {
        return true; // hx-*
    }

    // Explicitly reject dangerous event handlers
    if (std.mem.startsWith(u8, attr, "on") and attr.len > 2) {
        return false; // onclick, onload, etc.
    }

    return false;
}

/// Check if an attribute is a standard HTML attribute used across any element
/// This uses the unified specification to determine validity
pub fn isStandardHtmlAttribute(attr: []const u8) bool {
    // Check all element specs to see if this attribute is used anywhere
    for (html_spec.element_specs) |spec| {
        for (spec.allowed_attrs) |attr_spec| {
            if (std.mem.eql(u8, attr_spec.name, attr)) {
                return true;
            }
            // Handle aria-* attributes (prefix match)
            if (std.mem.eql(u8, attr_spec.name, "aria") and std.mem.startsWith(u8, attr, "aria-")) {
                return true;
            }
        }
    }
    return false;
}

/// Enum-based style lookup - O(1) performance
pub fn getStyleForElementEnum(tag: HtmlTag) ?[]const u8 {
    return element_style_map.get(tag) orelse Style.WHITE; // Default style for valid elements
}

// /// String-based style lookup (legacy - converts to enum internally)
// pub fn getStyleForElement(element_name: []const u8) ?[]const u8 {
//     // First check if element exists in HTML specification
//     if (html_spec.getElementSpec(element_name) == null) {
//         // Element not recognized in HTML spec, no styling
//         return null;
//     }

//     // Convert string to enum and use fast lookup
//     const tag = html_tags.stringToEnum(HtmlTag, element_name) orelse return Style.WHITE;
//     return getStyleForElementEnum(tag);
// }

pub fn isDangerousAttributeValue(value: []const u8) bool {
    // clean quotes if any
    const clean_value = if (std.mem.startsWith(u8, value, "\"") and std.mem.endsWith(u8, value, "\"") and value.len > 2)
        value[1 .. value.len - 1]
    else
        value;

    var lowercase_buf: [1024]u8 = undefined;
    if (clean_value.len > lowercase_buf.len) return false;

    for (clean_value, 0..) |c, i| {
        lowercase_buf[i] = std.ascii.toLower(c);
    }
    const clean_lower = lowercase_buf[0..clean_value.len];

    // Check for script injection patterns
    if (std.mem.indexOf(u8, clean_lower, "<script") != null) return true;
    if (std.mem.indexOf(u8, clean_lower, "</script") != null) return true;
    if (std.mem.indexOf(u8, clean_lower, "javascript:") != null) return true;
    if (std.mem.indexOf(u8, clean_lower, "vbscript:") != null) return true;

    // lexbor escape most of data:text/html and data:text/javascript, so don't worry about them
    // only signal potentially dangerous b64 encoded data as the browser decodes it

    // if (std.mem.indexOf(u8, clean_lower, "data:text/javascript") != null) return true;
    // if (std.mem.indexOf(u8, clean_lower, "data:text/html") != null) return true;
    if (std.mem.startsWith(u8, clean_lower, "data:") and
        std.mem.indexOf(u8, clean_lower, "base64") != null) return true;

    if (std.mem.startsWith(u8, clean_lower, "file:")) return true;
    if (std.mem.startsWith(u8, clean_lower, "ftp:")) return true;
    if (std.mem.startsWith(u8, clean_lower, "//")) return true;

    return false;
}
