const std = @import("std");
const z = @import("../root.zig");
const html_spec = @import("html_spec.zig");
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

pub fn getStyleForElement(element_name: []const u8) ?[]const u8 {
    // First check if element exists in HTML specification
    if (html_spec.getElementSpec(element_name) == null) {
        // Element not recognized in HTML spec, no styling
        return null;
    }

    // Apply specific styling for elements (all elements from HTML spec get some styling)
    if (std.mem.eql(u8, element_name, "html")) return ElementStyles.html;
    if (std.mem.eql(u8, element_name, "head")) return ElementStyles.head;
    if (std.mem.eql(u8, element_name, "body")) return ElementStyles.body;
    if (std.mem.eql(u8, element_name, "title")) return ElementStyles.title;
    if (std.mem.eql(u8, element_name, "meta")) return ElementStyles.meta;
    if (std.mem.eql(u8, element_name, "link")) return ElementStyles.link;
    if (std.mem.eql(u8, element_name, "script")) return ElementStyles.script;
    if (std.mem.eql(u8, element_name, "style")) return ElementStyles.style;
    if (std.mem.eql(u8, element_name, "h4")) return ElementStyles.h4;
    if (std.mem.eql(u8, element_name, "h5")) return ElementStyles.h5;
    if (std.mem.eql(u8, element_name, "h6")) return ElementStyles.h6;
    if (std.mem.eql(u8, element_name, "p")) return ElementStyles.p;
    if (std.mem.eql(u8, element_name, "div")) return ElementStyles.div;
    if (std.mem.eql(u8, element_name, "span")) return ElementStyles.span;
    if (std.mem.eql(u8, element_name, "img")) return ElementStyles.img;
    if (std.mem.eql(u8, element_name, "br")) return ElementStyles.br;
    if (std.mem.eql(u8, element_name, "hr")) return ElementStyles.hr;
    if (std.mem.eql(u8, element_name, "form")) return ElementStyles.form;
    if (std.mem.eql(u8, element_name, "input")) return ElementStyles.input;
    if (std.mem.eql(u8, element_name, "textarea")) return ElementStyles.textarea;
    if (std.mem.eql(u8, element_name, "button")) return ElementStyles.button;
    if (std.mem.eql(u8, element_name, "select")) return ElementStyles.select;
    if (std.mem.eql(u8, element_name, "option")) return ElementStyles.option;
    if (std.mem.eql(u8, element_name, "label")) return ElementStyles.label;
    if (std.mem.eql(u8, element_name, "nav")) return ElementStyles.nav;
    if (std.mem.eql(u8, element_name, "header")) return ElementStyles.header;
    if (std.mem.eql(u8, element_name, "footer")) return ElementStyles.footer;
    if (std.mem.eql(u8, element_name, "main")) return ElementStyles.main;
    if (std.mem.eql(u8, element_name, "section")) return ElementStyles.section;
    if (std.mem.eql(u8, element_name, "article")) return ElementStyles.article;
    if (std.mem.eql(u8, element_name, "h3")) return ElementStyles.h3;
    if (std.mem.eql(u8, element_name, "h4")) return ElementStyles.h4;
    if (std.mem.eql(u8, element_name, "h5")) return ElementStyles.h5;
    if (std.mem.eql(u8, element_name, "h6")) return ElementStyles.h6;

    if (std.mem.eql(u8, element_name, "a")) return ElementStyles.a;
    if (std.mem.eql(u8, element_name, "link")) return ElementStyles.link;

    if (std.mem.eql(u8, element_name, "strong")) return ElementStyles.strong;
    if (std.mem.eql(u8, element_name, "em")) return ElementStyles.em;
    if (std.mem.eql(u8, element_name, "code")) return ElementStyles.code;
    if (std.mem.eql(u8, element_name, "pre")) return ElementStyles.pre;
    if (std.mem.eql(u8, element_name, "ul")) return ElementStyles.ul;
    if (std.mem.eql(u8, element_name, "ol")) return ElementStyles.ol;
    if (std.mem.eql(u8, element_name, "li")) return ElementStyles.li;
    if (std.mem.eql(u8, element_name, "table")) return ElementStyles.table;
    if (std.mem.eql(u8, element_name, "tr")) return ElementStyles.tr;
    if (std.mem.eql(u8, element_name, "td")) return ElementStyles.td;
    if (std.mem.eql(u8, element_name, "th")) return ElementStyles.th;
    if (std.mem.eql(u8, element_name, "i")) return ElementStyles.i;

    if (std.mem.eql(u8, element_name, "html")) return Style.BOLD_CYAN;
    if (std.mem.eql(u8, element_name, "head")) return Style.CYAN;
    if (std.mem.eql(u8, element_name, "title")) return Style.BOLD_BLUE;
    if (std.mem.eql(u8, element_name, "meta")) return Style.BLUE;
    if (std.mem.eql(u8, element_name, "link")) return Style.BLUE;
    if (std.mem.eql(u8, element_name, "script")) return Style.BLACK_YELLOW;
    if (std.mem.eql(u8, element_name, "style")) return Style.YELLOW_BLACK;
    if (std.mem.eql(u8, element_name, "h4")) return Style.MAGENTA;
    if (std.mem.eql(u8, element_name, "h5")) return Style.MAGENTA;
    if (std.mem.eql(u8, element_name, "h6")) return Style.MAGENTA;
    if (std.mem.eql(u8, element_name, "span")) return Style.WHITE;
    if (std.mem.eql(u8, element_name, "img")) return Style.CYAN;
    if (std.mem.eql(u8, element_name, "br")) return Style.WHITE;
    if (std.mem.eql(u8, element_name, "hr")) return Style.WHITE;
    if (std.mem.eql(u8, element_name, "form")) return Style.GREEN;
    if (std.mem.eql(u8, element_name, "input")) return Style.GREEN;
    if (std.mem.eql(u8, element_name, "textarea")) return Style.GREEN;
    if (std.mem.eql(u8, element_name, "button")) return Style.BOLD_GREEN;
    if (std.mem.eql(u8, element_name, "select")) return Style.GREEN;
    if (std.mem.eql(u8, element_name, "option")) return Style.WHITE;
    if (std.mem.eql(u8, element_name, "label")) return Style.GREEN;
    if (std.mem.eql(u8, element_name, "nav")) return Style.BOLD_BLUE;
    if (std.mem.eql(u8, element_name, "header")) return Style.BOLD_BLUE;
    if (std.mem.eql(u8, element_name, "footer")) return Style.BOLD_BLUE;
    if (std.mem.eql(u8, element_name, "main")) return Style.BOLD_BLUE;
    if (std.mem.eql(u8, element_name, "section")) return Style.BLUE;
    if (std.mem.eql(u8, element_name, "article")) return Style.BLUE;
    if (std.mem.eql(u8, element_name, "aside")) return Style.BLUE;
    if (std.mem.eql(u8, element_name, "details")) return Style.BLUE;
    if (std.mem.eql(u8, element_name, "summary")) return Style.BOLD_BLUE;
    if (std.mem.eql(u8, element_name, "video")) return Style.PURPLE;
    if (std.mem.eql(u8, element_name, "audio")) return Style.PURPLE;
    if (std.mem.eql(u8, element_name, "canvas")) return Style.PURPLE;
    if (std.mem.eql(u8, element_name, "svg")) return Style.PURPLE;

    // Add missing anchor element
    if (std.mem.eql(u8, element_name, "a")) return Style.UNDERLINE_BLUE;

    // Default styling for any element that's in HTML spec but not explicitly styled above
    // This ensures all valid HTML elements get context tracking for attribute validation
    return Style.WHITE;
}

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
