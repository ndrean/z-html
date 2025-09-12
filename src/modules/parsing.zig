//! A module to parse strings. You can parse a string into a document, or create and parse a string into its body.
//!
//! You have `setInnerHTML` and the extended `setInnerHTMLSafe` which allows you to sanitize the input.
//!
//! You have parser engine with provides the same functions using a preloaded parser. It also gives access to a sanitizer process.
//!
//! It includes templates as strings.

const std = @import("std");
const z = @import("../root.zig");
const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;

/// Apply sanitization to a node based on sanitization options
fn applySanitization(allocator: std.mem.Allocator, node: *z.DomNode, sanitizer: z.SanitizeOptions) !void {
    switch (sanitizer) {
        .none => {},
        .minimum => try z.sanitizeWithOptions(allocator, node, .minimum),
        .strict => try z.sanitizeWithOptions(allocator, node, .strict),
        .permissive => try z.sanitizeWithOptions(allocator, node, .permissive),
        .custom => |opts| try z.sanitizeWithOptions(allocator, node, .{ .custom = opts }),
    }
}

test "lexbor escaping behavior" {
    const test_html = "<div>Raw < and > characters</div><script>if (x < 5) alert('test');</script>";

    const doc = try z.createDocFromString(test_html);
    defer z.destroyDocument(doc);

    const body = z.bodyElement(doc).?;
    _ = z.setInnerHTML(body, test_html) catch return error.ParseFailed;

    const result = try z.innerHTML(testing.allocator, body);
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("<div>Raw &lt; and &gt; characters</div><script>if (x < 5) alert('test');</script>", result);
}

const LXB_HTML_SERIALIZE_OPT_UNDEF: c_int = 0x00;

// =================================================================

// setInnerHTML
extern "c" fn lxb_html_element_inner_html_set(
    body: *z.HTMLElement,
    inner: [*]const u8,
    inner_len: usize,
) ?*z.HTMLElement;

// parser
extern "c" fn lxb_html_parser_create() ?*z.HtmlParser;
extern "c" fn lxb_html_parser_destroy(parser: *z.HtmlParser) *z.HtmlParser;
extern "c" fn lxb_html_parser_clean(parser: *z.HtmlParser) void;
extern "c" fn lxb_html_parser_init(parser: *z.HtmlParser) usize;

// creates a document from the given string with a parser
extern "c" fn lxb_html_parse(
    parser: *z.HtmlParser,
    html: [*]const u8,
    size: usize,
) ?*z.HTMLDocument;

// parses the HTML into a given document
extern "c" fn lxb_html_document_parse(
    doc: *z.HTMLDocument,
    html: [*]const u8,
    size: usize,
) usize;

// element-based fragment parsing
extern "c" fn lxb_html_parse_fragment(
    parser: *z.HtmlParser,
    element: *z.HTMLElement,
    html: [*]const u8,
    size: usize,
) ?*z.DomNode;

// document-based fragment parsing (preferred method from fragments.zig)
extern "c" fn lxb_html_document_parse_fragment(
    document: *z.HTMLDocument,
    context_element: *z.HTMLElement,
    html: [*]const u8,
    html_len: usize,
) ?*z.DomNode;

// === Parsing ==========================================================

/// [parse] Parse the HTML string into the `<body>` element of a document.
///
/// You can use `parseString("")` to clear the body content or create an empty body.
/// ## Example
/// ```zig
/// const doc = try z.createDocument();
/// defer z.destroyDocument(doc);
/// try z.parseString(doc, "<p></p>"); //<-- adds a <p> to the body
/// try z.parseString(doc, "<div></div>"); //<-- replaces with a <div>
/// ```
pub fn parseString(doc: *z.HTMLDocument, html: []const u8) !void {
    if (lxb_html_document_parse(doc, html.ptr, html.len) != z._OK) {
        return Err.ParseFailed;
    }
    return;
}

test "parseString" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);
    try parseString(doc, "<p></p>");
    const body = z.bodyNode(doc).?;
    var node = z.firstChild(body).?;

    try testing.expect(z.tagFromElement(z.nodeToElement(node).?) == .p);

    try parseString(doc, "<div></div>");
    node = z.firstChild(body).?;

    try testing.expect(z.tagFromElement(z.nodeToElement(node).?) == .div);
}

/// [parse] Creates a new document and parse HTML string into the document body
///
/// Example: `<head></head><body>[ parsed HTML ]</body>`
///
///Caller must free with `destroyDocument()`.
pub fn createDocFromString(html: []const u8) !*z.HTMLDocument {
    const doc = z.createDocument() catch {
        return Err.DocCreateFailed;
    };
    if (lxb_html_document_parse(doc, html.ptr, html.len) != z._OK) {
        return Err.ParseFailed;
    }
    return doc;
}

test "createDocFromString" {
    const doc = try createDocFromString("<p></p>");
    defer z.destroyDocument(doc);

    const allocator = testing.allocator;
    const html = try z.outerHTML(allocator, z.bodyElement(doc).?);
    defer allocator.free(html);
    try testing.expectEqualStrings("<body><p></p></body>", html);
}

/// [parse] Sets / replaces element's inner HTML with Lexbor's built-in sanitization only.
///
/// This is the primary function for setting inner HTML - fast and efficient.
/// Uses Lexbor's built-in sanitization which handles most security concerns.
/// For 90% of use cases, this is sufficient and recommended.
pub fn setInnerHTML(element: *z.HTMLElement, content: []const u8) !*z.HTMLElement {
    return lxb_html_element_inner_html_set(element, content.ptr, content.len) orelse Err.FragmentParseFailed;
}

test "setInnerHTML & lexbor security sanitation" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const malicious_content = "<script>alert('XSS')</script><img src=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\"><p id=\"1\" phx-click=\"increment\" onclick=\"alert('XSS')\">Click me</p><a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a>";

    const div = try z.createElement(doc, "div");
    _ = try setInnerHTML(div, malicious_content); //<-- lexbor sanitizes this in part

    const outer = try z.innerHTML(allocator, div);
    defer allocator.free(outer);

    const expected = "<script>alert('XSS')</script><img src=\"data:text/html,&lt;script&gt;alert('XSS')&lt;/script&gt;\" alt=\"escaped\"><p id=\"1\" phx-click=\"increment\" onclick=\"alert('XSS')\">Click me</p><a href=\"http://example.org/results?search=&lt;img src=x onerror=alert('hello')&gt;\">URL Escaped</a>";

    try testing.expectEqualStrings(expected, outer);
}

/// [parse] Sets  / replaces the inner HTML of an element with sanitization options
///
/// Parses HTML fragment, applies sanitization, and replaces the element's content.
/// Uses document-based fragment parsing (lxb_html_document_parse_fragment).
pub fn setInnerHTMLSafe(
    allocator: std.mem.Allocator,
    doc: *z.HTMLDocument,
    html: []const u8,
    context_element: *z.HTMLElement,
    sanitizer: z.SanitizeOptions,
) !void {
    const template_html = try std.fmt.allocPrint(allocator, "<template>{s}</template>", .{html});
    defer allocator.free(template_html);
    // Parse without sanitization first - we'll sanitize the content afterward
    const template_fragment = lxb_html_document_parse_fragment(
        doc,
        context_element,
        template_html.ptr,
        template_html.len,
    ) orelse return Err.ParseFailed;

    defer z.destroyNode(template_fragment);

    const template_node = z.firstChild(template_fragment) orelse return Err.ParseFailed;
    const template_element = z.nodeToElement(template_node) orelse return Err.ParseFailed;
    const template_template = z.elementToTemplate(template_element) orelse return Err.ParseFailed;
    const template_content = z.templateContent(template_template);
    const fragment_root = z.fragmentToNode(template_content);

    // Apply sanitization to the template content (not the wrapper)
    try applySanitization(allocator, fragment_root, sanitizer);

    // const fragment_root = lxb_html_document_parse_fragment(
    //     doc,
    //     context_element,
    //     html.ptr,
    //     html.len,
    // ) orelse return Err.ParseFailed;

    // if (z.firstChild(fragment_root) != null) {
    //     _ = try setInnerHTML(context_element, "");
    //     try z.appendFragment(z.elementToNode(context_element), fragment_root);
    // } else {
    //     return Err.FragmentParseFailed;
    // }

    // Clear existing content and append the new fragment
    _ = try setInnerHTML(context_element, "");
    try z.appendFragment(
        z.elementToNode(context_element),
        fragment_root,
    );
}

test "setInnerHTMLSafe" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("<div></div>");
    defer z.destroyDocument(doc);

    const div = z.getElementByTag(
        z.documentRoot(doc).?,
        .div,
    ).?;

    {
        try setInnerHTMLSafe(
            allocator,
            doc,
            "<p><script> console.log('hi'); </script></p><span></span>",
            div,
            .none,
        );
        const p = z.getElementByTag(
            z.elementToNode(div),
            .p,
        );
        _ = p;

        const inner = try z.innerHTML(allocator, div);
        defer allocator.free(inner);

        try testing.expect(std.mem.indexOf(u8, inner, "<script>") != null);
        try testing.expect(std.mem.indexOf(u8, inner, "<span>") != null);
    }
    {
        try setInnerHTMLSafe(
            allocator,
            doc,
            "<p><script> console.log('hi'); </script></p><span></span>",
            div,
            .strict,
        );

        const inner = try z.innerHTML(allocator, div);
        defer allocator.free(inner);

        try testing.expect(std.mem.indexOf(u8, inner, "<script>") == null);
        try testing.expect(std.mem.indexOf(u8, inner, "<span>") != null);
    }
}

// ===================================================================

/// **Parser** - HTML fragment parsing engine with configurable sanitization.
/// Thread safe per instance.
///
/// **Two-Layer Approach:**
/// 1. **Lexbor's built-in sanitization** (always applied) - handles most security efficiently
/// 2. **Custom sanitizer** (configurable) - handles SVG, custom elements, framework attributes
///
/// ## Usage Pattern:
/// ```zig
/// // only once
/// var parser = try Parser.init(allocator);
/// defer parser.deinit();
///
/// const doc: *z.HTMLDocument = try parser.parse("<div></div>");
/// defer z.destroyDocument(doc);
/// const template = "<template><p>...</p></template>"
/// try parser.parseAndAppend(target_element, template, .body, .permissive); // Handles templates + fragments
/// ```
///
/// ## Key Methods:
/// **Setup:** `init()`, `deinit()`
/// **Main Methods:** `parse` and `parseAndAppend()` (handles both templates and fragments automatically)
/// **Node Processing:** `parseFragmentNodes()`
pub const Parser = struct {
    allocator: std.mem.Allocator,
    html_parser: *z.HtmlParser,
    initialized: bool,

    /// Create a new parser instance.
    pub fn init(allocator: std.mem.Allocator) !@This() {
        const parser = lxb_html_parser_create() orelse
            return Err.ParserCreateFailed;

        if (lxb_html_parser_init(parser) != z._OK) {
            _ = lxb_html_parser_destroy(parser);
            return Err.ParserInitFailed;
        }

        return .{
            .allocator = allocator,
            .html_parser = parser,
            .initialized = true,
        };
    }

    /// Deinitialize parser and free resources.
    pub fn deinit(self: *Parser) void {
        if (!self.initialized) return;

        lxb_html_parser_clean(self.html_parser);
        _ = lxb_html_parser_destroy(self.html_parser);
        self.initialized = false;
    }

    /// [parser] Parse HTML string into a new document, sanitize, and return the document.
    pub fn parse(self: *Parser, html: []const u8, sanitizer: z.SanitizeOptions) !*z.HTMLDocument {
        const doc = lxb_html_parse(self.html_parser, html.ptr, html.len) orelse return Err.ParseFailed;
        const root = z.documentRoot(doc) orelse return Err.DocumentRootNotFound;

        switch (sanitizer) {
            .none => {}, // No sanitization
            .minimum => {
                try z.sanitizeWithOptions(self.allocator, root, .minimum);
            },
            .strict => {
                try z.sanitizeStrict(self.allocator, root);
            },
            .permissive => {
                try z.sanitizePermissive(self.allocator, root);
            },
            .custom => |opts| {
                try z.sanitizeWithOptions(self.allocator, root, .{ .custom = opts });
            },
        }

        return doc;
    }

    /// Parse HTML string in given context - returns original template content (no cloning)
    /// WARNING: The returned DocumentFragment will be emptied when used with appendFragment!
    /// Only use this when you know the fragment will be consumed immediately.
    pub fn parseStringInContext(
        self: *Parser,
        html: []const u8,
        doc: *z.HTMLDocument,
        context: z.FragmentContext,
        sanitizer: z.SanitizeOptions,
    ) !*z.DomNode {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        // Special template wrapping approach for true DocumentFragments
        if (context != .template) {
            // Wrap in template to get true DocumentFragment
            const template_html = try std.fmt.allocPrint(self.allocator, "<template>{s}</template>", .{html});
            defer self.allocator.free(template_html);

            // Parse in template context to get template element
            const template_fragment = try self.parseStringInContext(
                template_html,
                doc,
                .template,
                .none,
            );
            defer z.destroyNode(template_fragment);

            // Extract template element and its content
            const template_node = z.firstChild(template_fragment) orelse {
                return Err.ParseFailed;
            };
            const template_element = z.nodeToElement(template_node) orelse {
                return Err.ParseFailed;
            };
            const template_template = z.elementToTemplate(template_element) orelse {
                return Err.ParseFailed;
            };

            // Get the true DocumentFragment content (NO CLONING)
            const template_content = z.templateContent(template_template);
            const content_node = z.fragmentToNode(template_content);

            // Apply sanitization to original content
            try applySanitization(self.allocator, content_node, sanitizer);

            return content_node;
        }

        // Original method for template context (no wrapping needed)
        const context_tag = context.toTagName();
        const context_element = try z.createElement(doc, context_tag);
        defer z.destroyNode(z.elementToNode(context_element));

        const fragment_root = lxb_html_parse_fragment(
            self.html_parser,
            context_element,
            html.ptr,
            html.len,
        ) orelse {
            return Err.ParseFailed;
        };

        try applySanitization(self.allocator, fragment_root, sanitizer);

        return fragment_root;
    }

    /// Parse and append HTML fragments using parseStringInContext (no cloning)
    /// [parser] Parse and append regular HTML fragments (private helper)
    fn parseAndAppendFragment(
        self: *Parser,
        element: *z.HTMLElement,
        content: []const u8,
        context: z.FragmentContext,
        sanitizer: z.SanitizeOptions,
    ) !void {
        const node = z.elementToNode(element);
        const target_doc = z.ownerDocument(node);

        const fragment_root = try self.parseStringInContext(
            content,
            target_doc,
            context,
            sanitizer,
        );
        // NOTE: No defer z.destroyNode(fragment_root) because it's original template content

        // Use the unified appendFragment function
        try z.appendFragment(node, fragment_root);
    }

    /// Parse a template string and return the template element (with DocumentFragment content)
    ///
    /// ## Example
    /// ```
    /// parser.parseTemplateString("<template><div>Hello, world!</div></template>", true);
    /// ```
    fn parseTemplateString(
        self: *Parser,
        doc: *z.HTMLDocument,
        html: []const u8,
        sanitizer: z.SanitizeOptions,
    ) !*z.HTMLTemplateElement {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        const fragment_root = try self.parseStringInContext(
            html,
            doc,
            .template,
            sanitizer,
        );

        const template_node = z.firstChild(fragment_root) orelse return Err.ParseFailed;
        const template_element = z.nodeToElement(template_node) orelse return Err.ParseFailed;

        // Remove template from fragment_root to detach it (preserve DocumentFragment structure)
        z.removeNode(template_node);
        z.destroyNode(fragment_root); // Clean up the now-empty container

        return z.elementToTemplate(template_element) orelse return Err.ParseFailed;
    }

    /// Parse a received template string and inject it into the target node with option to sanitize
    pub fn useTemplateString(
        self: *Parser,
        template_html: []const u8,
        target: *z.DomNode,
        sanitizer: z.SanitizeOptions,
    ) !void {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        const doc = z.ownerDocument(target);
        // Parse template
        const template = try self.parseTemplateString(
            doc,
            template_html,
            sanitizer,
        );
        defer z.destroyNode(z.templateToNode(template));

        // Use template (clones content)
        return z.useTemplateElement(
            self.allocator,
            z.templateToElement(template),
            target,
            sanitizer,
        );
    }

    /// [parser] Universal parsing and appending method
    ///
    /// Automatically detects and handles both template strings and regular HTML fragments.
    /// Templates are detected by scanning for `<template` tags in the content.
    /// Templates are processed by cloning their content, regular HTML is parsed and sanitized.
    /// All content is appended to the target element.
    pub fn parseAndAppend(
        self: *Parser,
        target: *z.HTMLElement,
        content: []const u8,
        context: z.FragmentContext,
        sanitizer: z.SanitizeOptions,
    ) !void {
        // Check if content contains template elements
        if (std.mem.indexOf(u8, content, "<template") != null) {
            return self.parseAndAppendTemplates(
                target,
                content,
                context,
                sanitizer,
            );
        } else {
            return self.parseAndAppendFragment(
                target,
                content,
                context,
                sanitizer,
            );
        }
    }

    /// [parser] Parse and append template content (private helper)
    fn parseAndAppendTemplates(
        self: *Parser,
        target: *z.HTMLElement,
        content: []const u8,
        context: z.FragmentContext,
        sanitizer: z.SanitizeOptions,
    ) !void {
        const target_doc = z.ownerDocument(z.elementToNode(target));

        // Parse all templates from the HTML
        const templates = try self.parseTemplates(
            target_doc,
            content,
            sanitizer,
        );
        defer {
            for (templates) |template| {
                z.destroyNode(z.templateToNode(template));
            }
            self.allocator.free(templates);
        }

        // Use each template to inject content into target
        const target_node = z.elementToNode(target);
        for (templates) |template| {
            try z.useTemplateElement(
                self.allocator,
                z.templateToElement(template),
                target_node,
                sanitizer,
            );
        }

        // Also handle any non-template content in the same string
        var temp_content: std.ArrayList(u8) = .empty;
        defer temp_content.deinit(self.allocator);

        // Simple approach: remove template elements and process remaining content
        var start: usize = 0;
        while (std.mem.indexOfPos(u8, content, start, "<template")) |template_start| {
            // Add content before template
            try temp_content.appendSlice(self.allocator, content[start..template_start]);

            // Find end of template
            if (std.mem.indexOfPos(u8, content, template_start, "</template>")) |template_end| {
                start = template_end + "</template>".len;
            } else {
                // Malformed template, skip it
                start = template_start + "<template".len;
            }
        }

        // Add remaining content after last template
        try temp_content.appendSlice(self.allocator, content[start..]);

        // Process any remaining non-template content
        if (temp_content.items.len > 0 and std.mem.trim(u8, temp_content.items, " \t\n\r").len > 0) {
            try self.parseAndAppendFragment(
                target,
                temp_content.items,
                context,
                sanitizer,
            );
        }
    }

    /// [parser] Parse multiple templates from HTML and return them as a slice of template elements
    ///
    /// Each template is parsed individually to ensure proper DocumentFragment content preservation.
    /// The caller is responsible for destroying each returned template with `z.destroyNode(z.templateToNode(template))` and freeing the slice with `allocator.free(templates)`.
    /// See test "parseTemplates - multiple template parsing" for usage example.
    fn parseTemplates(
        self: *Parser,
        doc: *z.HTMLDocument,
        html: []const u8,
        sanitizer: z.SanitizeOptions,
    ) ![]const *z.HTMLTemplateElement {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        const fragment_root = try self.parseStringInContext(
            html,
            doc,
            .template,
            sanitizer,
        );
        defer z.destroyNode(fragment_root);

        var templates: std.ArrayList(*z.HTMLTemplateElement) = .empty;
        defer templates.deinit(self.allocator);

        // Extract template HTML strings and parse each individually
        var child = z.firstChild(fragment_root);
        while (child != null) {
            if (z.nodeType(child.?) == .element) {
                const element = z.nodeToElement(child.?).?;
                if (z.elementToTemplate(element)) |_| {
                    // Get the template as HTML string and parse it individually
                    const template_html = try z.outerHTML(self.allocator, element);
                    defer self.allocator.free(template_html);

                    // Parse this individual template
                    const template = try self.parseTemplateString(
                        doc,
                        template_html,
                        sanitizer,
                    );
                    try templates.append(self.allocator, template);
                }
            }
            child = z.nextSibling(child.?);
        }

        return templates.toOwnedSlice(self.allocator);
    }

    /// Parse HTML fragment and return array of child nodes for immediate inspection and validation
    ///
    /// Use this when you need to count, inspect, or validate individual nodes immediately after parsing.
    /// Note: Returned nodes are tied to the parsing context and should not be stored for later use.
    /// For DOM insertion, use `parseAndAppendFragment` instead. The caller is responsible for freeing the returned array with `allocator.free(nodes)`.
    /// See test "parseFragmentNodes - direct usage of returned nodes" for usage example.
    pub fn parseFragmentNodes(
        self: *Parser,
        allocator: std.mem.Allocator,
        doc: *z.HTMLDocument,
        html: []const u8,
        context: z.FragmentContext,
        sanitizer: z.SanitizeOptions,
    ) ![]*z.DomNode {
        // Parse using Parser's method
        const fragment_root = try self.parseStringInContext(
            html,
            doc,
            context,
            sanitizer,
        );
        defer z.destroyNode(fragment_root);

        return z.childNodes(allocator, fragment_root);
    }
};

test "parser.parse" {
    const allocator = testing.allocator;
    var parser = try z.Parser.init(allocator);
    defer parser.deinit();
    {
        const html = "<p></p>";
        const doc = try parser.parse(
            html,
            .none,
        );
        defer z.destroyDocument(doc);
        const body = z.bodyNode(doc).?;
        const p = z.getElementByTag(body, .p);
        std.debug.assert(p != null);
    }
}

test "parser.parseAndAppendFragment with improved logic" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try z.Parser.init(allocator);
    defer parser.deinit();

    const malicious_content = "<script>alert('XSS')</script><img src=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\"><p id=\"1\" phx-click=\"increment\" onclick=\"alert('XSS')\">Click me</p><a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a><x-widget><button onclick=\"increment\">Click</button></x-widget>";

    const result0 = "<script>alert('XSS')</script><img src=\"data:text/html,&lt;script&gt;alert('XSS')&lt;/script&gt;\" alt=\"escaped\"><p id=\"1\" phx-click=\"increment\" onclick=\"alert('XSS')\">Click me</p><a href=\"http://example.org/results?search=&lt;img src=x onerror=alert('hello')&gt;\">URL Escaped</a><x-widget><button onclick=\"increment\">Click</button></x-widget>";

    const result1 = "<img alt=\"escaped\"><p id=\"1\" phx-click=\"increment\">Click me</p><a href=\"http://example.org/results?search=&lt;img src=x onerror=alert('hello')&gt;\">URL Escaped</a>";

    const result2 = "<img alt=\"escaped\"><p id=\"1\" phx-click=\"increment\">Click me</p><a href=\"http://example.org/results?search=&lt;img src=x onerror=alert('hello')&gt;\">URL Escaped</a><x-widget><button>Click</button></x-widget>";

    const expectations = [_]struct { name: []const u8, result: []const u8, mode: z.SanitizeOptions }{
        .{ .name = "flavor0", .result = result0, .mode = .none },
        .{ .name = "flavor1", .result = result1, .mode = .strict },
        .{ .name = "flavor2", .result = result2, .mode = .permissive },
    };

    for (expectations) |exp| {
        const div_elt = try z.createElement(doc, "div");
        defer z.destroyNode(z.elementToNode(div_elt));

        try parser.parseAndAppendFragment(
            div_elt,
            malicious_content,
            .body,
            exp.mode,
        );
        const inner = try z.innerHTML(allocator, div_elt);
        defer allocator.free(inner);

        try testing.expectEqualStrings(exp.result, inner);
        _ = try setInnerHTML(div_elt, "");
    }
}

test "parseStringInContext + appendFragment with options" {
    const allocator = testing.allocator;

    const doc = try createDocFromString("<div id=\"1\"></div>");
    defer z.destroyDocument(doc);
    const div_elt = z.getElementById(z.bodyNode(doc).?, "1").?;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const html1 = "<p> some text</p>";
    const frag_root1 = try parser.parseStringInContext(
        html1,
        doc,
        .body,
        .strict,
    );

    const html2 = "<div> more <i>text</i><span><script>alert(1);</script></span></div>";
    const frag_root2 = try parser.parseStringInContext(
        html2,
        doc,
        .div,
        .strict,
    );

    const html3 = "<ul><li><script>alert(1);</script></li></ul>";
    const frag_root3 = try parser.parseStringInContext(
        html3,
        doc,
        .div,
        .strict,
    );

    const html4 = "<a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a>";
    const frag_root4 = try parser.parseStringInContext(
        html4,
        doc,
        .div,
        .permissive,
    );

    // append fragments and check the result

    const div: *z.DomNode = @ptrCast(div_elt);
    try z.appendFragment(div, frag_root1);
    try z.appendFragment(div, frag_root2);
    try z.appendFragment(div, frag_root3);
    try z.appendFragment(div, frag_root4);

    const result = try z.outerHTML(allocator, div_elt);
    defer allocator.free(result);

    const expected = "<div id=\"1\"><p> some text</p><div> more <i>text</i><span></span></div><ul><li></li></ul><a href=\"http://example.org/results?search=&lt;img src=x onerror=alert('hello')&gt;\">URL Escaped</a></div>";

    try testing.expectEqualStrings(expected, result);
}

test "all-in-one: parseAndAppendFragment with sanitization option" {
    const allocator = testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();
    const doc = try parser.parse("<div id=\"1\"></div>", .none);
    defer z.destroyDocument(doc);

    const html1 = "<p> some text</p>";
    const html2 = "<div> more <i>text</i><span><script>alert(1);</script></span></div>";
    const html3 = "<ul><li><script>alert(1);</script></li></ul>";

    const div_elt = z.getElementById(z.bodyNode(doc).?, "1").?;
    // const div: *z.DomNode = @ptrCast(div_elt);

    // append fragments and check the result
    try parser.parseAndAppendFragment(div_elt, html1, .div, .permissive);
    try parser.parseAndAppendFragment(div_elt, html2, .div, .strict);
    try parser.parseAndAppendFragment(div_elt, html3, .div, .strict);

    const result = try z.outerHTML(allocator, div_elt);
    defer allocator.free(result);

    const expected = "<div id=\"1\"><p> some text</p><div> more <i>text</i><span></span></div><ul><li></li></ul></div>";
    try testing.expectEqualStrings(expected, result);
}

test "Serializer sanitation" {
    const allocator = testing.allocator;

    const malicious_content =
        \\ <div>
        \\  <button disabled hidden onclick=\"alert('XSS')\" phx-click=\"increment\">Potentially dangerous, not escaped</button>
        \\  <!-- a comment -->
        \\  <div data-time=\"{@current}\"> The current value is: {@counter} </div>
        \\  <a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a>
        \\  <a href=\"javascript:alert('XSS')\">Dangerous, not escaped</a>
        \\  <img src=\"javascript:alert('XSS')\" alt=\"not escaped\">
        \\  <iframe src=\"javascript:alert('XSS')\" alt=\"not escaped\"></iframe>
        \\  <a href=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\">Safe escaped</a>
        \\  <img src=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\">
        \\  <iframe src=\"data:text/html,<script>alert('XSS')</script>\" >Escaped</iframe>
        \\  <img src=\"data:image/svg+xml,<svg onload=alert('XSS')\" alt=\"escaped\"></svg>\">
        \\  <img src=\"data:image/svg+xml;base64,PHN2ZyBvbmxvYWQ9YWxlcnQoJ1hTUycpPjwvc3ZnPg==\" alt=\"potential dangerous b64\">
        \\  <a href=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgnWFNTJyk8L3NjcmlwdD4=\">Potential dangerous b64</a>
        \\  <img src=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgnWFNTJyk8L3NjcmlwdD4=\" alt=\"potential dangerous b64\">
        \\  <a href=\"file:///etc/passwd\">Dangerous Local file access</a><img src=\"file:///etc/passwd\" alt=\"dangerous local file access\">
        \\  <p>Hello<i>there</i>, all<strong>good?</strong></p>
        \\  <p>Visit this link: <a href=\"https://example.com\">example.com</a></p>
        \\</div>
        \\<link href=\"/shared-assets/misc/link-element-example.css\" rel=\"stylesheet\">
        \\<script>console.log(\"hi\");</script>
        \\<template><p>Inside template</p></template>
        \\<custom-element><script> console.log("hi");</script></custom-element>
    ;

    var parser = try z.Parser.init(allocator);
    defer parser.deinit();
    var doc = try parser.parse("", .none);
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;

    // Test 1: .strict mode
    {
        try parser.parseAndAppendFragment(
            z.nodeToElement(body).?,
            malicious_content,
            .div,
            .strict,
        );

        const final_html = try z.outerNodeHTML(allocator, body);
        defer allocator.free(final_html);

        // Should remove dangerous content
        try testing.expect(std.mem.indexOf(u8, final_html, "javascript:") == null);
        try testing.expect(std.mem.indexOf(u8, final_html, "onclick") == null);
        try testing.expect(std.mem.indexOf(u8, final_html, "<script>") == null);
        try testing.expect(std.mem.indexOf(u8, final_html, "custom-element") == null); // Custom elements removed in strict

        // Should preserve safe content
        try testing.expect(std.mem.indexOf(u8, final_html, "Hello") != null);
        try testing.expect(std.mem.indexOf(u8, final_html, "example.com") != null);
        try testing.expect(std.mem.indexOf(u8, final_html, "<strong>") != null);
    }
    // Test 2: .strict mode (repeat test)
    {
        doc = try parser.parse("", .none);
        try parser.parseAndAppendFragment(
            z.nodeToElement(body).?,
            malicious_content,
            .div,
            .strict,
        );

        const final_html = try z.outerNodeHTML(allocator, body);
        defer allocator.free(final_html);

        // Verify consistent strict sanitization
        try testing.expect(std.mem.indexOf(u8, final_html, "javascript:") == null);
        try testing.expect(std.mem.indexOf(u8, final_html, "<template>") != null); // Templates are now allowed
    }
    // Test 3: .permissive mode
    {
        doc = try parser.parse("", .none);
        try parser.parseAndAppendFragment(
            z.nodeToElement(body).?,
            malicious_content,
            .div,
            .permissive,
        );

        const final_html = try z.outerNodeHTML(allocator, body);
        defer allocator.free(final_html);

        // Should still remove dangerous content
        try testing.expect(std.mem.indexOf(u8, final_html, "javascript:") == null);
        try testing.expect(std.mem.indexOf(u8, final_html, "onclick") == null);
        try testing.expect(std.mem.indexOf(u8, final_html, "<script>") == null);

        // But should preserve custom elements
        try testing.expect(std.mem.indexOf(u8, final_html, "custom-element") != null);

        // Should preserve safe content and framework attributes
        try testing.expect(std.mem.indexOf(u8, final_html, "phx-click") != null);
        try testing.expect(std.mem.indexOf(u8, final_html, "Hello") != null);
    }
    // Test 4: .none mode
    {
        doc = try parser.parse("", .none);
        try parser.parseAndAppendFragment(
            z.nodeToElement(body).?,
            malicious_content,
            .div,
            .none,
        );

        const final_html = try z.outerNodeHTML(allocator, body);
        defer allocator.free(final_html);

        // Should preserve most content including scripts and custom elements
        try testing.expect(std.mem.indexOf(u8, final_html, "<script>") != null);
        try testing.expect(std.mem.indexOf(u8, final_html, "custom-element") != null);
        try testing.expect(std.mem.indexOf(u8, final_html, "<!-- a comment -->") != null);

        // Should preserve safe content
        try testing.expect(std.mem.indexOf(u8, final_html, "Hello") != null);
        try testing.expect(std.mem.indexOf(u8, final_html, "<template>") != null);
    }
    // Test 5: .custom mode
    {
        doc = try parser.parse("", .none);
        try parser.parseAndAppendFragment(
            z.nodeToElement(body).?,
            malicious_content,
            .div,
            .{
                .custom = .{
                    .allow_custom_elements = true,
                    .skip_comments = false, // Preserve comments
                    .remove_scripts = false, // Allow scripts to demonstrate flexibility
                    .remove_styles = true,
                    .strict_uri_validation = false,
                },
            },
        );

        const final_html = try z.outerNodeHTML(allocator, body);
        defer allocator.free(final_html);

        // Should preserve comments and custom elements
        try testing.expect(std.mem.indexOf(u8, final_html, "<!-- a comment -->") != null);
        try testing.expect(std.mem.indexOf(u8, final_html, "custom-element") != null);

        // Should preserve scripts and allow more URIs (as configured)
        try testing.expect(std.mem.indexOf(u8, final_html, "<script>") != null);
        // javascript: URIs might still be filtered at parser level

        // Should preserve safe content and framework attributes
        try testing.expect(std.mem.indexOf(u8, final_html, "phx-click") != null);
        try testing.expect(std.mem.indexOf(u8, final_html, "Hello") != null);
    }
}

test "parser.parseAndAppendFragment: multiple inserts" {
    const allocator = testing.allocator;

    var parser = try z.Parser.init(allocator);
    defer parser.deinit();
    const doc = try parser.parse("<div><ul></ul></div>", .none);
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;

    const ul_elt = z.getElementByTag(body, .ul).?;
    // const ul = z.elementToNode(ul_elt);

    for (0..10) |i| {
        const li = try std.fmt.allocPrint(
            allocator,
            "<li id=\"item-{}\">Item {}</li>",
            .{ i, i },
        );
        defer allocator.free(li);

        try parser.parseAndAppendFragment(ul_elt, li, .ul, .permissive);
    }

    const ul_html = try z.innerHTML(allocator, ul_elt);
    defer allocator.free(ul_html);

    try testing.expect(std.mem.indexOf(u8, ul_html, "Item 8") != null);
}

test "parser.parseTemplateString & useTemplateElement" {
    const allocator = testing.allocator;

    var parser = try z.Parser.init(allocator);
    defer parser.deinit();

    const doc = try parser.parse("<ul id='items'></ul>", .none);
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;
    const ul = z.getElementById(body, "items").?;
    const ul_node = z.elementToNode(ul);

    // Template builder inline function
    const templateBuilder = struct {
        fn create(alloc: std.mem.Allocator, i: usize, name: []const u8) ![]const u8 {
            return std.fmt.allocPrint(alloc, "<template><li id=\"item-{d}\">Item {d}: {s}</li></template>", .{ i, i, name });
        }
    }.create;

    // Create and parse 3 templates using the parser engine
    const template1_html = try templateBuilder(allocator, 1, "First");
    defer allocator.free(template1_html);
    const template1 = try parser.parseTemplateString(doc, template1_html, .none);

    const template2_html = try templateBuilder(allocator, 2, "Second");
    defer allocator.free(template2_html);
    const template2 = try parser.parseTemplateString(doc, template2_html, .none);

    const template3_html = try templateBuilder(allocator, 3, "Third");
    defer allocator.free(template3_html);
    const template3 = try parser.parseTemplateString(doc, template3_html, .none);

    // Use templates to inject content into the list
    try z.useTemplateElement(
        allocator,
        z.templateToElement(template1),
        ul_node,
        .none,
    );
    try z.useTemplateElement(
        allocator,
        z.templateToElement(template2),
        ul_node,
        .none,
    );
    try z.useTemplateElement(
        allocator,
        z.templateToElement(template3),
        ul_node,
        .none,
    );

    // Test that everything is properly in the body
    const result_html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result_html);

    // Verify all items are present
    try testing.expect(std.mem.indexOf(u8, result_html, "Item 1: First") != null);
    try testing.expect(std.mem.indexOf(u8, result_html, "Item 2: Second") != null);
    try testing.expect(std.mem.indexOf(u8, result_html, "Item 3: Third") != null);

    // Verify structure
    try testing.expect(std.mem.indexOf(u8, result_html, "<ul id=\"items\">") != null);
    try testing.expect(std.mem.indexOf(u8, result_html, "</ul>") != null);

    // Count the li elements (should be 3)
    var li_count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, result_html, search_pos, "<li")) |pos| {
        li_count += 1;
        search_pos = pos + 17;
    }
    try testing.expectEqual(@as(usize, 3), li_count);
}

test "parser.useTemplateString: templates can be reused" {
    const allocator = testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const doc = try parser.parse("<ul id='list'></ul>", .none);
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;
    const ul = z.getElementById(body, "list").?;
    const ul_node = z.elementToNode(ul);

    const template_html = "<template><li>Item</li></template>";

    // Use the same template twice
    try parser.useTemplateString(template_html, ul_node, .permissive);
    try parser.useTemplateString(template_html, ul_node, .permissive);
    try parser.useTemplateString(template_html, ul_node, .permissive);
    try parser.useTemplateString(template_html, ul_node, .permissive);
    try parser.useTemplateString(template_html, ul_node, .permissive);
    try parser.useTemplateString(template_html, ul_node, .permissive);
    try parser.useTemplateString(template_html, ul_node, .permissive);
    try parser.useTemplateString(template_html, ul_node, .permissive);
    try parser.useTemplateString(template_html, ul_node, .permissive);
    try parser.useTemplateString(template_html, ul_node, .permissive);

    // Check result
    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // Should have two <li>Item</li> elements
    var li_count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, result, search_pos, "<li>Item</li>")) |pos| {
        li_count += 1;
        search_pos = pos + 12; // length of "<li>Item</li>"
    }
    try testing.expectEqual(@as(usize, 10), li_count);
}

test "parseFragmentNodes - direct usage of returned nodes" {
    const allocator = testing.allocator;

    const doc = try z.createDocFromString("<ul id='high'></ul><ul id='low'></ul>");
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    // Parse task list and get individual nodes
    const task_html = "<li data-priority='high'>Critical fix</li><li data-priority='low'>Update docs</li><li data-priority='high'>Deploy</li>";

    const nodes = try parser.parseFragmentNodes(
        allocator,
        doc,
        task_html,
        .ul,
        .permissive,
    );
    defer allocator.free(nodes);
    std.debug.assert(nodes.len == 3);

    // Get target containers
    const body = z.bodyNode(doc).?;
    const high_ul = z.getElementById(body, "high").?;
    const low_ul = z.getElementById(body, "low").?;

    for (nodes) |node| {
        if (z.nodeType(node) == .element) {
            const element = z.nodeToElement(node).?;

            const priority = z.getAttribute_zc(element, "data-priority");

            if (std.mem.eql(u8, priority orelse "", "high")) {
                z.appendChild(z.elementToNode(high_ul), node);
            } else {
                z.appendChild(z.elementToNode(low_ul), node);
            }
        }
    }

    // Verify the nodes were actually inserted
    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // Check if our nodes made it into the document
    try testing.expect(std.mem.indexOf(u8, result, "Critical fix") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Update docs") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Deploy") != null);
}

test "simple parseFragment with SVG" {
    const allocator = testing.allocator;

    const doc = try z.createDocFromString("");
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    // Mixed HTML + SVG content
    const mixed_html_svg =
        \\<div class="icon-wrapper">
        \\  <svg width="24" height="24" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
        \\    <rect x="2" y="2" width="20" height="20" fill="blue" stroke="black" stroke-width="1"/>
        \\    <circle cx="12" cy="12" r="6" fill="red"/>
        \\    <path d="M8 12 L12 8 L16 12 L12 16 Z" fill="white"/>
        \\  </svg>
        \\</div>
        \\<p>Regular HTML paragraph</p>
        \\<svg class="standalone" width="16" height="16" viewBox="0 0 16 16">
        \\  <circle cx="8" cy="8" r="7" fill="green" stroke="darkgreen"/>
        \\  <text x="8" y="12" text-anchor="middle" fill="white" font-size="8">OK</text>
        \\</svg>
    ;

    try parser.parseAndAppendFragment(
        z.bodyElement(doc).?,
        mixed_html_svg,
        .body,
        .permissive, // Use permissive to preserve SVG
    );
    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);
    const svg = z.getElementByTag(body, .svg);
    try testing.expect(svg != null);
}

test "parseFragmentNodes - moving SVG elements" {
    const allocator = testing.allocator;

    const doc = try z.createDocFromString("<div id='icons'></div><div id='graphics'></div>");
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    // Mixed HTML + SVG content
    const mixed_html_svg =
        \\<div class="icon-wrapper"><svg></svg>
        \\</div>
        \\<p>Regular HTML paragraph</p>
        \\<svg class="standalone" width="16" height="16" viewBox="0 0 16 16">
        \\  <circle cx="8" cy="8" r="7" fill="green" stroke="darkgreen"/>
        \\  <path d="M8 12 L12 8 L16 12 L12 16 Z" fill="white"/>
        \\</svg>
    ;

    // remove the 2 #text nodes by normalizing the input
    const normed = try z.normalizeHtmlString(allocator, mixed_html_svg);
    defer allocator.free(normed);

    const nodes = try parser.parseFragmentNodes(
        allocator,
        doc,
        normed,
        .div,
        .permissive,
    );
    defer allocator.free(nodes);

    try testing.expect(nodes.len == 3); // div, p, svg

    // Get target containers
    const body = z.bodyNode(doc).?;
    const icons_div = z.getElementById(
        body,
        "icons",
    ).?;
    const graphics_div = z.getElementById(
        body,
        "graphics",
    ).?;

    var svg_count: usize = 0;
    var regular_html_count: usize = 0;

    for (nodes) |node| {
        if (z.isTypeElement(node)) {
            const element = z.nodeToElement(node).?;
            if (z.tagFromElement(element) == .svg) {
                svg_count += 1;

                // Route to graphics container
                const cloned_svg = z.cloneNode(node).?;
                z.appendChild(
                    z.elementToNode(graphics_div),
                    cloned_svg,
                );
            } else if (z.tagFromElement(element) == .div and z.hasClass(element, "icon-wrapper")) {
                regular_html_count += 1;
                // Route to icons container
                const cloned = z.cloneNode(node).?;
                z.appendChild(z.elementToNode(icons_div), cloned);
            } else {
                regular_html_count += 1;
                // Route to icons container (default)
                const cloned = z.cloneNode(node).?;
                z.appendChild(z.elementToNode(icons_div), cloned);
            }
        }
    }

    try testing.expect(svg_count == 1);
    try testing.expect(regular_html_count == 2);

    // Verify the results
    const result = try z.outerHTML(
        allocator,
        z.nodeToElement(body).?,
    );
    defer allocator.free(result);

    // // Test that SVG elements were preserved with their attributes
    try testing.expect(std.mem.indexOf(u8, result, "<svg") != null);
    try testing.expect(std.mem.indexOf(u8, result, "width=\"16\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "viewBox=\"0 0 16 16\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<circle") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<path") != null);
    try testing.expect(std.mem.indexOf(u8, result, "fill=\"green\"") != null);
}

test "fragment contexts: select options" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);
    try parseString(doc, "<select id='countries'></select>");

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const body = z.bodyNode(doc).?;
    const select = z.getElementById(body, "countries").?;
    const select_node = z.elementToNode(select);

    const options_html =
        \\<option value="us">United States</option>
        \\<option value="ca">Canada</option>
        \\<optgroup label="Europe">
        \\  <option value="uk">United Kingdom</option>
        \\  <option value="fr">France</option>
        \\</optgroup>
    ;

    try parser.parseAndAppendFragment(z.nodeToElement(select_node).?, options_html, .select, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "United States") != null);
    try testing.expect(std.mem.indexOf(u8, result, "optgroup") != null);
    try testing.expect(std.mem.indexOf(u8, result, "United Kingdom") != null);
}

test "fragment contexts: table rows" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<table><tbody id='employees'></tbody></table>");
    const body = z.bodyNode(doc).?;
    const tbody = z.getElementById(body, "employees").?;
    // const tbody_node = z.elementToNode(tbody);

    const rows_html =
        \\<tr>
        \\  <td>John</td>
        \\  <td>Designer</td>
        \\  <td>$85,000</td>
        \\</tr>
        \\<tr>
        \\  <td>Jane</td>
        \\  <td>Developer</td>
        \\  <td>$95,000</td>
        \\</tr>
    ;

    try parser.parseAndAppendFragment(tbody, rows_html, .tbody, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "<td>John</td>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<td>Jane</td>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Developer") != null);
}

test "fragment contexts: list items" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<ul id='tasks'></ul>");
    const body = z.bodyNode(doc).?;
    const ul_elt = z.getElementById(body, "tasks").?;

    const items_html =
        \\<li>Complete project documentation</li>
        \\<li>Review pull requests</li>
        \\<li>Update deployment scripts</li>
    ;

    try parser.parseAndAppendFragment(ul_elt, items_html, .ul, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "Complete project") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Review pull") != null);
    try testing.expect(std.mem.indexOf(u8, result, "deployment scripts") != null);
}

test "fragment contexts: form elements" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<form id='login'></form>");
    const body = z.bodyNode(doc).?;
    const form = z.getElementById(body, "login").?;

    const form_html =
        \\<label for="email">Email:</label>
        \\<input type="email" id="email" name="email" required>
        \\<label for="password">Password:</label>
        \\<input type="password" id="password" name="password" required>
        \\<button type="submit">Login</button>
    ;

    try parser.parseAndAppendFragment(form, form_html, .form, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "type=\"email\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "type=\"password\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Login</button>") != null);
}

test "fragment contexts: definition lists" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<dl id='glossary'></dl>");
    const body = z.bodyNode(doc).?;
    const dl = z.getElementById(body, "glossary").?;

    const dl_html =
        \\<dt>HTML</dt>
        \\<dd>HyperText Markup Language</dd>
        \\<dt>CSS</dt>  
        \\<dd>Cascading Style Sheets</dd>
        \\<dt>JS</dt>
        \\<dd>JavaScript programming language</dd>
    ;

    try parser.parseAndAppendFragment(dl, dl_html, .dl, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "<dt>HTML</dt>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "HyperText Markup") != null);
    try testing.expect(std.mem.indexOf(u8, result, "JavaScript programming") != null);
}

test "fragment contexts: media elements" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<video id='demo' controls></video>");
    const body = z.bodyNode(doc).?;
    const video = z.getElementById(body, "demo").?;

    const media_html =
        \\<source src="/video.webm" type="video/webm">
        \\<source src="/video.mp4" type="video/mp4">
        \\<track kind="captions" src="/captions.vtt" srclang="en" label="English">
        \\<p>Your browser doesn't support HTML5 video.</p>
    ;

    try parser.parseAndAppendFragment(video, media_html, .video, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "video.webm") != null);
    try testing.expect(std.mem.indexOf(u8, result, "captions.vtt") != null);
    try testing.expect(std.mem.indexOf(u8, result, "HTML5 video") != null);
}

test "fragment contexts: malformed HTML recovery" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<div id='content'></div>");
    const body = z.bodyNode(doc).?;
    const div = z.getElementById(body, "content").?;

    const malformed_html =
        \\<div class="card">
        \\  <h3>Title</h3>
        \\  <p>Missing closing tags
        \\      <span>More content
        \\</div>
    ;

    try parser.parseAndAppendFragment(div, malformed_html, .body, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // lexbor should auto-fix the malformed HTML
    try testing.expect(std.mem.indexOf(u8, result, "<h3>Title</h3>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Missing closing") != null);
    try testing.expect(std.mem.indexOf(u8, result, "More content") != null);
}

test "fragment contexts: fieldset legend" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<fieldset id='contact'></fieldset>");
    const body = z.bodyNode(doc).?;
    const fieldset = z.getElementById(body, "contact").?;

    const fieldset_html =
        \\<legend>Contact Information</legend>
        \\<label for="name">Name:</label>
        \\<input type="text" id="name" name="name">
        \\<label for="phone">Phone:</label>
        \\<input type="tel" id="phone" name="phone">
    ;

    try parser.parseAndAppendFragment(fieldset, fieldset_html, .fieldset, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "<legend>Contact Information</legend>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "type=\"text\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "type=\"tel\"") != null);
}

test "fragment contexts: details summary" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<details id='faq'></details>");
    const body = z.bodyNode(doc).?;
    const details = z.getElementById(body, "faq").?;

    const details_html =
        \\<summary>Click to expand FAQ</summary>
        \\<p>This content is hidden by default</p>
        \\<ul>
        \\  <li>Question 1 answer</li>
        \\  <li>Question 2 answer</li>
        \\</ul>
    ;

    try parser.parseAndAppendFragment(details, details_html, .details, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "<summary>Click to expand") != null);
    try testing.expect(std.mem.indexOf(u8, result, "hidden by default") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Question 1 answer") != null);
}

test "fragment contexts: optgroup nested options" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<optgroup id='states' label='US States'></optgroup>");
    const body = z.bodyNode(doc).?;
    const optgroup = z.getElementById(body, "states").?;

    const options_html =
        \\<option value="ny">New York</option>
        \\<option value="ca">California</option>
        \\<option value="tx">Texas</option>
        \\<option value="fl">Florida</option>
    ;

    try parser.parseAndAppendFragment(optgroup, options_html, .optgroup, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "New York") != null);
    try testing.expect(std.mem.indexOf(u8, result, "California") != null);
    try testing.expect(std.mem.indexOf(u8, result, "value=\"tx\"") != null);
}

test "fragment contexts: map areas" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<map id='imagemap' name='navigation'></map>");
    const body = z.bodyNode(doc).?;
    const map = z.getElementById(body, "imagemap").?;

    const areas_html =
        \\<area shape="rect" coords="0,0,100,100" href="/section1" alt="Section 1">
        \\<area shape="circle" coords="150,75,50" href="/section2" alt="Section 2">
        \\<area shape="poly" coords="200,0,250,50,200,100,150,50" href="/section3" alt="Section 3">
    ;

    try parser.parseAndAppendFragment(map, areas_html, .map, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "shape=\"rect\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "shape=\"circle\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "shape=\"poly\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "href=\"/section1\"") != null);
}

test "fragment contexts: figure caption" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<figure id='chart'></figure>");
    const body = z.bodyNode(doc).?;
    const figure = z.getElementById(body, "chart").?;

    const figure_html =
        \\<img src="/sales-chart.png" alt="Sales Chart" width="400" height="300">
        \\<figcaption>Monthly sales performance for Q4 2024 showing 15% growth</figcaption>
    ;

    try parser.parseAndAppendFragment(figure, figure_html, .figure, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "sales-chart.png") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<figcaption>Monthly sales") != null);
    try testing.expect(std.mem.indexOf(u8, result, "15% growth") != null);
}

test "fragment contexts: picture responsive" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<picture id='hero'></picture>");
    const body = z.bodyNode(doc).?;
    const picture = z.getElementById(body, "hero").?;

    const picture_html =
        \\<source media="(min-width: 800px)" srcset="/hero-large.jpg">
        \\<source media="(min-width: 400px)" srcset="/hero-medium.jpg">
        \\<img src="/hero-small.jpg" alt="Hero image" loading="lazy">
    ;

    try parser.parseAndAppendFragment(picture, picture_html, .picture, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "hero-large.jpg") != null);
    try testing.expect(std.mem.indexOf(u8, result, "min-width: 800px") != null);
    try testing.expect(std.mem.indexOf(u8, result, "loading=\"lazy\"") != null);
}

test "parseAndAppend - unified API for templates and fragments" {
    const allocator = testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const doc = try parser.parse("<div id='container'></div>", .none);
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;
    const container = z.getElementById(body, "container").?;

    // Test 1: Regular HTML fragments
    try parser.parseAndAppend(container, "<p>Hello World</p>", .div, .permissive);

    // Test 2: Template content
    const template_content = "<template><span>Template Content</span></template>";
    try parser.parseAndAppend(container, template_content, .div, .permissive);

    // Test 3: Mixed content (template + regular HTML)
    const mixed_content = "<div>Before template</div><template><strong>Template</strong></template><div>After template</div>";
    try parser.parseAndAppend(container, mixed_content, .div, .permissive);

    // Verify all content was added
    const result = try z.innerHTML(allocator, container);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "Hello World") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Template Content") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Before template") != null);
    try testing.expect(std.mem.indexOf(u8, result, "After template") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<strong>Template</strong>") != null);
}

test "parseTemplates - multiple template parsing" {
    const allocator = testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const multiple_templates_html =
        \\<template id="item-template">
        \\  <li class="item">Template Item</li>
        \\</template>
        \\<div>Some other content</div>
        \\<template id="card-template">
        \\  <div class="card">
        \\    <h3>Card Title</h3>
        \\    <p>Card content</p>
        \\  </div>
        \\</template>
        \\<template id="button-template">
        \\  <button class="btn">Click me</button>
        \\</template>
    ;

    const test_doc = try z.createDocument();
    defer z.destroyDocument(test_doc);

    const templates = try parser.parseTemplates(test_doc, multiple_templates_html, .permissive);
    defer {
        // Clean up each template and its document
        for (templates) |template| {
            z.destroyNode(z.templateToNode(template));
        }
        allocator.free(templates);
    }

    try testing.expect(templates.len == 3);

    // Create a test document to inject templates into
    const doc = try z.createDocFromString("<ul id='items'></ul><div id='cards'></div><div id='buttons'></div>");
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;
    const ul = z.getElementById(body, "items").?;
    const cards_div = z.getElementById(body, "cards").?;
    const buttons_div = z.getElementById(body, "buttons").?;

    // Use each template to inject content into different containers
    // Template 0: item-template -> inject into <ul>
    try z.useTemplateElement(allocator, z.templateToElement(templates[0]), z.elementToNode(ul), .permissive);
    try z.useTemplateElement(allocator, z.templateToElement(templates[0]), z.elementToNode(ul), .permissive); // Use twice

    // Template 1: card-template -> inject into cards div
    try z.useTemplateElement(allocator, z.templateToElement(templates[1]), z.elementToNode(cards_div), .permissive);

    // Template 2: button-template -> inject into buttons div
    try z.useTemplateElement(allocator, z.templateToElement(templates[2]), z.elementToNode(buttons_div), .permissive);

    // Verify the results
    const final_html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(final_html);

    // Verify each template was injected correctly
    try testing.expect(std.mem.indexOf(u8, final_html, "<li class=\"item\">Template Item</li>") != null);
    try testing.expect(std.mem.indexOf(u8, final_html, "<h3>Card Title</h3>") != null);
    try testing.expect(std.mem.indexOf(u8, final_html, "<p>Card content</p>") != null);
    try testing.expect(std.mem.indexOf(u8, final_html, "<button class=\"btn\">Click me</button>") != null);

    // Count that item template was used twice
    var item_count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, final_html, search_pos, "<li class=\"item\">")) |pos| {
        item_count += 1;
        search_pos = pos + 17;
    }
    try testing.expectEqual(@as(usize, 2), item_count);
}

test "fragment contexts: audio sources" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<audio id='podcast' controls></audio>");
    const body = z.bodyNode(doc).?;
    const audio = z.getElementById(body, "podcast").?;

    const audio_html =
        \\<source src="/podcast.ogg" type="audio/ogg">
        \\<source src="/podcast.mp3" type="audio/mp3">
        \\<track kind="descriptions" src="/descriptions.vtt" srclang="en">
        \\<p>Your browser doesn't support HTML5 audio.</p>
    ;

    try parser.parseAndAppendFragment(audio, audio_html, .audio, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "podcast.ogg") != null);
    try testing.expect(std.mem.indexOf(u8, result, "podcast.mp3") != null);
    try testing.expect(std.mem.indexOf(u8, result, "descriptions.vtt") != null);
    try testing.expect(std.mem.indexOf(u8, result, "HTML5 audio") != null);
}
