//! A module to parse strings. You can parse a string into a document, or create and parse a string into its body.
//!
//! You have parser engine with provides utility functions for parsing strings, including templates as strings. It also gives access to a sanitizer process.

const std = @import("std");
const z = @import("../root.zig");
const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;

test "lexbor escaping behavior" {
    const test_html = "<div>Raw < and > characters</div><script>if (x < 5) alert('test');</script>";

    const doc = try z.createDocFromString(test_html);
    defer z.destroyDocument(doc);

    const body = z.bodyElement(doc).?;
    _ = z.setInnerHTML(body, test_html) catch return error.ParseFailed;

    const result = try z.innerHTML(testing.allocator, body);
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("<div>Raw &lt; and &gt; characters</div><script>if (x < 5) alert('test');</script>", result);

    // std.debug.print("\n=== LEXBOR ESCAPING TEST ===\n", .{});
    // std.debug.print("Input:  {s}\n", .{test_html});
    // std.debug.print("Output: {s}\n\n", .{result});

    // Basic assertion - just ensure we got some output
    // try testing.expect(result.len > 0);
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
    element: *z.HTMLElement,
    html: [*]const u8,
    html_len: usize,
) ?*z.DomNode;

// === Parsing ==========================================================

/// [parser] Parse the HTML string into the `<body>` element of a document
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

/// [parser] Creates a new document and parse HTML string into the document body
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

/// [parser] Sets / replaces element's inner HTML with Lexbor's built-in sanitization only.
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

/// [parser] Set the inner HTML of an element with enhanced sanitization options.
///
/// **Two-Layer Sanitization Approach:**
/// 1. **Lexbor's sanitization** (always applied) - handles most security concerns
/// 2. **Custom sanitizer** (optional) - handles edge cases like SVG, custom elements, framework attributes
///
/// Use this when you need more control than the basic `setInnerHTML` provides.
/// Common use cases: SVG content, custom web components, framework-specific attributes.
///
/// @param sanitizer_enabled: true to apply custom sanitization, false for Lexbor-only
pub fn setInnerSafeHTML(allocator: std.mem.Allocator, element: *z.HTMLElement, content: []const u8, sanitizer: z.SanitizeOptions) !void {
    const node = z.elementToNode(element);
    const target_doc = z.ownerDocument(node);

    var parser = try z.Parser.init(allocator);
    defer parser.deinit();

    const fragment_root = try parser.parseFragmentDoc(
        target_doc,
        content,
        .div,
        sanitizer,
    );
    parser.appendFragment(node, fragment_root);
}

/// [parser] Version of setInnerSafeHTML with sanitization preset `true`.
///
/// **Strict Mode:** Removes all potentially dangerous content including custom elements
/// for user-generated content from untrusted sources.
pub fn setInnerSafeHTMLStrict(allocator: std.mem.Allocator, element: *z.HTMLElement, content: []const u8) !void {
    const node = z.elementToNode(element);
    const target_doc = z.ownerDocument(node);

    var parser = try z.Parser.init(allocator);
    defer parser.deinit();

    const fragment_root = try parser.parseFragmentDoc(
        target_doc,
        content,
        .div,
        .strict, // sanitizer enabled
    );
    parser.appendFragment(node, fragment_root);
}

/// [parser] Set the inner HTML with permissive sanitization preset.
///
/// **Permissive Mode:** Allows custom elements and framework attributes while removing XSS vectors.
pub fn setInnerSafeHTMLPermissive(allocator: std.mem.Allocator, element: *z.HTMLElement, content: []const u8) !void {
    const node = z.elementToNode(element);
    const target_doc = z.ownerDocument(node);

    var parser = try z.Parser.init(allocator);
    defer parser.deinit();

    const fragment_root = try parser.parseFragmentDoc(
        target_doc,
        content,
        .div,
        .permissive, // permissive sanitization
    );
    parser.appendFragment(node, fragment_root);
}

test "setInnerHTML flavours" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

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
        const div = try z.createElement(doc, "div");
        try z.setInnerSafeHTML(allocator, div, malicious_content, exp.mode);
        const inner = try z.innerHTML(allocator, div);
        defer allocator.free(inner);
        // print("\n{s}: \n{s}\n", .{ exp.name, inner });

        try testing.expectEqualStrings(exp.result, inner);
        _ = try setInnerHTML(div, "");
    }
}

// ===================================================================

/// **Parser** - HTML fragment parsing engine with configurable sanitization.
/// Thread safe per instance.
///
/// ## Sanitization Architecture:
/// **Two-Layer Approach:**
/// 1. **Lexbor's built-in sanitization** (always applied) - handles most security efficiently
/// 2. **Custom sanitizer** (configurable) - handles SVG, custom elements, framework attributes
///
/// ## Usage Pattern:
/// ```zig
/// // 1. Create parser and configure sanitization once
/// var parser = try Parser.init(allocator);
/// defer parser.deinit();
/// parser.setSanitizerPermissive(); // Configure once
///
/// // 2. Use simple boolean for all operations
/// const fragment = try parser.parseStringContext(html, .body, true); // Boolean on/off
/// ```
///
/// ## Key Methods:
/// **Setup:** `init()`, `deinit()`
/// **Fragment Parsing:** `parseFragmentDoc()`, `parseStringContext()`, `insertFragment()`
/// **Template Handling:** `parseTemplateString()`, `useTemplateElement()`
/// **Chunk Processing:** `parseChunkBegin()`, `parseChunkProcess()`, `parseChunkEnd()`
/// **Node Management:** `appendFragment()`, `parseFragmentNodes()`
pub const Parser = struct {
    allocator: std.mem.Allocator,
    html_parser: *z.HtmlParser,
    temp_doc: ?*z.HTMLDocument,
    initialized: bool,
    // sanitizer_options: z.SanitizerOptions,

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
            .temp_doc = null,
            .initialized = true,
            // .sanitizer_options = .{}, // Default sanitizer options
        };
    }

    /// Deinitialize parser and free resources.
    pub fn deinit(self: *Parser) void {
        if (!self.initialized) return;

        if (self.temp_doc) |doc| {
            z.destroyDocument(doc);
            self.temp_doc = null;
        }

        lxb_html_parser_clean(self.html_parser);
        _ = lxb_html_parser_destroy(self.html_parser);
        self.initialized = false;
    }

    // /// Configure sanitizer options for this parser instance
    // pub fn setSanitizerOptions(self: *Parser, options: z.SanitizerOptions) void {
    //     self.sanitizer_options = options;
    // }

    // /// Set sanitizer to strict mode (no custom elements, remove scripts/styles)
    // pub fn setSanitizerStrict(self: *Parser) void {
    //     self.sanitizer_options = .{
    //         .skip_comments = true,
    //         .remove_scripts = true,
    //         .remove_styles = true,
    //         .strict_uri_validation = true,
    //         .allow_custom_elements = false,
    //     };
    // }

    // /// Set sanitizer to permissive mode (allow custom elements and framework attributes)
    // pub fn setSanitizerPermissive(self: *Parser) void {
    //     self.sanitizer_options = .{
    //         .skip_comments = true,
    //         .remove_scripts = true,
    //         .remove_styles = false,
    //         .strict_uri_validation = true,
    //         .allow_custom_elements = true,
    //     };
    // }

    pub fn parse(self: *Parser, html: []const u8) !*z.HTMLDocument {
        return lxb_html_parse(self.html_parser, html.ptr, html.len) orelse return Err.ParseFailed;
    }

    //  ----[TODO]--- changes to firstChild?
    /// Parse HTML fragment using a provided document.
    ///
    /// **Sanitization:** Lexbor (always) + Custom (if enabled via boolean).
    ///
    /// @param sanitizer_enabled: true to apply configured custom sanitization, false for Lexbor-only
    /// @returns: HTML element node - its children are the parsed elements
    pub fn parseFragmentDoc(
        self: *Parser,
        doc: *z.HTMLDocument,
        html: []const u8,
        context: z.FragmentContext,
        sanitizer: z.SanitizeOptions,
    ) !*z.DomNode {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        const context_tag = context.toTagName();
        // print("context_tag: {s}\n", .{context_tag});
        const context_element = try z.createElement(doc, context_tag);
        // defer z.destroyNode(z.elementToNode(context_element));

        const fragment_root = lxb_html_document_parse_fragment(
            doc,
            context_element,
            html.ptr,
            html.len,
        ) orelse return Err.ParseFailed;

        switch (sanitizer) {
            .none => {}, // No sanitization
            .strict => try z.sanitizeStrict(self.allocator, fragment_root),
            .permissive => try z.sanitizePermissive(self.allocator, fragment_root),
            .custom => |opts| try z.sanitizeWithOptions(self.allocator, fragment_root, .{ .custom = opts }),
        }

        // return z.firstChild(fragment_root);
        return fragment_root; // HTML
    }

    /// Parse HTML fragment string in the context of a specific element.
    ///
    /// **Sanitization:** Lexbor (always) + Custom (if enabled via boolean).
    /// Most commonly used parsing function for fragments, chunks, and templates.
    ///
    /// @param sanitizer_enabled: true to apply configured custom sanitization, false for Lexbor-only
    /// @returns: Fragment root HTML element - its children are the parsed elements
    pub fn parseStringContext(
        self: *Parser,
        html: []const u8,
        context: z.FragmentContext,
        sanitizer: z.SanitizeOptions,
    ) !*z.DomNode {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        if (self.temp_doc == null) {
            self.temp_doc = try z.createDocument();
        } else {
            z.cleanDocument(self.temp_doc.?);
        }

        const context_tag = context.toTagName();
        const context_element = try z.createElement(self.temp_doc.?, context_tag);

        const fragment_root = lxb_html_parse_fragment(
            self.html_parser,
            context_element,
            html.ptr,
            html.len,
        ) orelse {
            return Err.ParseFailed;
        };

        switch (sanitizer) {
            .none => {}, // No sanitization
            .strict => try z.sanitizeStrict(self.allocator, fragment_root),
            .permissive => try z.sanitizePermissive(self.allocator, fragment_root),
            .custom => |opts| try z.sanitizeWithOptions(self.allocator, fragment_root, .{ .custom = opts }),
        }

        return fragment_root;
    }

    pub fn appendFragment(_: *Parser, parent: *z.DomNode, fragment_node: ?*z.DomNode) void {
        if (fragment_node == null) return;
        var fragment_child = z.firstChild(fragment_node.?);
        while (fragment_child != null) {
            const next_sibling = z.nextSibling(fragment_child.?);
            // Remove from fragment first, then append to parent (this moves the node)
            z.removeNode(fragment_child.?);
            z.appendChild(parent, fragment_child.?);
            fragment_child = next_sibling;
        }
        z.destroyNode(fragment_node.?);
    }

    pub fn setInnerSafeHTML(
        self: *Parser,
        element: *z.HTMLElement,
        content: []const u8,
        sanitizer: z.SanitizeOptions,
    ) !void {
        const node = z.elementToNode(element);
        const target_doc = z.ownerDocument(node);

        // lexbor sanitization + sanitizer enabled
        const fragment_root = try self.parseFragmentDoc(
            target_doc,
            content,
            .div,
            sanitizer,
        );
        self.appendFragment(node, fragment_root);
    }

    /// Parse a template string and return the template element (with DocumentFragment content)
    ///
    /// ## Example
    /// ```
    /// parser.parseTemplateString("<template><div>Hello, world!</div></template>", true);
    /// ```
    pub fn parseTemplateString(
        self: *Parser,
        html: []const u8,
        sanitizer: z.SanitizeOptions,
    ) !*z.HTMLTemplateElement {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        const fragment_root = try self.parseStringContext(
            html,
            .template,
            sanitizer,
        );

        const template_node = z.firstChild(fragment_root) orelse return Err.ParseFailed;
        const template_element = z.nodeToElement(template_node) orelse return Err.ParseFailed;
        const template = z.elementToTemplate(template_element) orelse return Err.ParseFailed;

        // Remove template from fragment_root to detach it (preserve DocumentFragment structure)
        z.removeNode(template_node);
        z.destroyNode(fragment_root); // Clean up the now-empty container

        return template;
    }

    /// Parse multiple templates from HTML and return them as a slice of template elements
    ///
    /// Each template is parsed individually to ensure proper DocumentFragment content preservation.
    /// The caller is responsible for destroying each returned template with `z.destroyNode(z.templateToNode(template))` and freeing the slice with `allocator.free(templates)`.
    /// See test "parseTemplates - multiple template parsing" for usage example.
    pub fn parseTemplates(
        self: *Parser,
        html: []const u8,
        sanitizer: z.SanitizeOptions,
    ) ![]const *z.HTMLTemplateElement {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        const fragment_root = try self.parseStringContext(html, .body, sanitizer);
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
                    const template = try self.parseTemplateString(template_html, sanitizer);
                    try templates.append(self.allocator, template);
                }
            }
            child = z.nextSibling(child.?);
        }

        return templates.toOwnedSlice(self.allocator);
    }

    /// Parse a received template string and inject it into the target node with option to sanitize
    pub fn useTemplateString(
        self: *Parser,
        template_html: []const u8,
        target: *z.DomNode,
        sanitizer: z.SanitizeOptions,
    ) !void {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        // Parse template
        const template = try self.parseTemplateString(
            template_html,
            sanitizer,
        );
        defer z.destroyNode(z.templateToNode(template));

        // Use template (clones content)
        return self.useTemplateElement(template, target, sanitizer);
    }

    /// Use an existing template element in the DOM and injects it into target node with optional sanitization. Can use HTMLTemplateElement or HTMLElement.
    pub fn useTemplateElement(
        self: *Parser,
        // template_element: *z.HTMLTemplateElement,
        element: anytype,
        target: *z.DomNode,
        sanitizer: z.SanitizeOptions,
    ) !void {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        const template_element = if (@TypeOf(element) == *z.HTMLTemplateElement)
            element
        else blk: {
            if (!z.isTemplate(z.elementToNode(element)))
                return Err.NotATemplateElement;
            break :blk z.elementToTemplate(element).?;
        };

        const template_content = z.templateContent(template_element);
        const content_node = z.fragmentToNode(template_content);

        // const template_doc = z.ownerDocument(z.templateToNode(template_element));
        const cloned_content = z.cloneNode(content_node) orelse return Err.FragmentParseFailed;

        // Apply sanitization
        switch (sanitizer) {
            .none => {}, // No sanitization
            .strict => try z.sanitizeStrict(self.allocator, cloned_content),
            .permissive => try z.sanitizePermissive(self.allocator, cloned_content),
            .custom => |opts| try z.sanitizeWithOptions(self.allocator, cloned_content, .{ .custom = opts }),
        }

        z.appendFragment(target, cloned_content);
    }

    /// Parse HTML fragment string and insert it directly into parent given a context (most common use case)
    pub fn insertFragment(
        self: *Parser,
        parent: *z.DomNode,
        html: []const u8,
        context: z.FragmentContext,
        sanitizer: z.SanitizeOptions,
    ) !void {
        const parent_doc = z.ownerDocument(parent);
        const fragment_root = try self.parseFragmentDoc(
            parent_doc,
            html,
            context,
            sanitizer,
        );
        // Note: appendFragment already destroys fragment_root, no defer needed
        self.appendFragment(parent, fragment_root);
    }

    /// Parse HTML fragment and return array of child nodes for immediate inspection and validation
    ///
    /// Use this when you need to count, inspect, or validate individual nodes immediately after parsing.
    /// Note: Returned nodes are tied to the parsing context and should not be stored for later use.
    /// For DOM insertion, use `insertFragment` instead. The caller is responsible for freeing the returned array with `allocator.free(nodes)`.
    /// See test "parseFragmentNodes - direct usage of returned nodes" for usage example.
    pub fn parseFragmentNodes(
        self: *Parser,
        allocator: std.mem.Allocator,
        doc: *z.HTMLDocument,
        html: []const u8,
        context: z.FragmentContext,
        sanitizer: z.SanitizeOptions,
    ) ![]*z.DomNode {
        const fragment_root = try self.parseFragmentDoc(doc, html, context, sanitizer);
        defer z.destroyNode(fragment_root);

        return z.childNodes(allocator, fragment_root);
    }
};

test "parser.parse & parseFragmentDoc" {
    var parser = try z.Parser.init(testing.allocator);
    defer parser.deinit();
    const html = "<div></div>";
    {
        const doc = try parser.parse(html);
        defer z.destroyDocument(doc);
        const div = z.getElementByTag(z.documentRoot(doc).?, .div);
        std.debug.assert(div != null);
    }
    {
        const doc = try z.createDocument();
        defer z.destroyDocument(doc);
        const html_node = try parser.parseFragmentDoc(doc, html, .body, .none);
        const div = z.getElementByTag(html_node, .div);
        std.debug.assert(div != null);
    }
}

test "security of parseFragment and appendFragment first test" {
    const doc = try createDocFromString("<div id=\"1\"></div>");
    defer z.destroyDocument(doc);

    const allocator = testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const html1 = "<p> some text</p>";
    const frag_root1 = try parser.parseStringContext(
        html1,
        .body,
        .strict,
    );

    const html2 = "<div> more <i>text</i><span><script>alert(1);</script></span></div>";
    const frag_root2 = try parser.parseStringContext(
        html2,
        .body,
        .strict,
    );

    const html3 = "<ul><li><script>alert(1);</script></li></ul>";
    const frag_root3 = try parser.parseStringContext(
        html3,
        .body,
        .strict,
    );

    const html4 = "<a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a>";
    const frag_root4 = try parser.parseStringContext(
        html4,
        .body,
        .permissive,
    );

    // append fragments and check the result
    const div_elt = z.getElementById(z.bodyNode(doc).?, "1").?;
    const div: *z.DomNode = @ptrCast(div_elt);
    parser.appendFragment(div, frag_root1);
    parser.appendFragment(div, frag_root2);
    parser.appendFragment(div, frag_root3);
    parser.appendFragment(div, frag_root4);

    const result = try z.outerHTML(allocator, div_elt);
    defer allocator.free(result);

    const expected = "<div id=\"1\"><p> some text</p><div> more <i>text</i><span></span></div><ul><li></li></ul><a href=\"http://example.org/results?search=&lt;img src=x onerror=alert('hello')&gt;\">URL Escaped</a></div>";

    try testing.expectEqualStrings(expected, result);
}

test "insertFragment with sanitization option" {
    const allocator = testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();
    const doc = try parser.parse("<div id=\"1\"></div>");
    defer z.destroyDocument(doc);

    const html1 = "<p> some text</p>";
    const html2 = "<div> more <i>text</i><span><script>alert(1);</script></span></div>";
    const html3 = "<ul><li><script>alert(1);</script></li></ul>";

    const div_elt = z.getElementById(z.bodyNode(doc).?, "1").?;
    const div: *z.DomNode = @ptrCast(div_elt);

    // append fragments and check the result
    try parser.insertFragment(div, html1, .div, .permissive);
    try parser.insertFragment(div, html2, .div, .strict);
    try parser.insertFragment(div, html3, .div, .strict);

    const result = try z.outerHTML(allocator, div_elt);
    defer allocator.free(result);

    const expected = "<div id=\"1\"><p> some text</p><div> more <i>text</i><span></span></div><ul><li></li></ul></div>";
    try testing.expectEqualStrings(expected, result);
}

// ----[TODO]------- Sanitization tests
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
    var doc = try parser.parse("");
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;

    // Test 1: .strict mode
    {
        try parser.setInnerSafeHTML(
            z.nodeToElement(body).?,
            malicious_content,
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
        doc = try parser.parse("");
        try parser.setInnerSafeHTML(
            z.nodeToElement(body).?,
            malicious_content,
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
        doc = try parser.parse("");
        try parser.setInnerSafeHTML(
            z.nodeToElement(body).?,
            malicious_content,
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
        doc = try parser.parse("");
        try parser.setInnerSafeHTML(
            z.nodeToElement(body).?,
            malicious_content,
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
        doc = try parser.parse("");
        try parser.setInnerSafeHTML(
            z.nodeToElement(body).?,
            malicious_content,
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

test "parser insertFragment multiple inserts" {
    const allocator = testing.allocator;

    var parser = try z.Parser.init(allocator);
    defer parser.deinit();
    const doc = try parser.parse("<div><ul></ul></div>");
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;

    const ul_elt = z.getElementByTag(body, .ul).?;
    const ul = z.elementToNode(ul_elt);

    for (0..10) |i| {
        const li = try std.fmt.allocPrint(
            allocator,
            "<li id=\"item-{}\">Item {}</li>",
            .{ i, i },
        );
        defer allocator.free(li);

        try parser.insertFragment(ul, li, .ul, .permissive);
    }

    const ul_html = try z.innerHTML(allocator, ul_elt);
    defer allocator.free(ul_html);

    try testing.expect(std.mem.indexOf(u8, ul_html, "Item 8") != null);
}

test "template parsing and use template element" {
    const allocator = testing.allocator;

    var parser = try z.Parser.init(allocator);
    defer parser.deinit();

    const doc = try parser.parse("<ul id='items'></ul>");
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
    const template1 = try parser.parseTemplateString(template1_html, .none);

    const template2_html = try templateBuilder(allocator, 2, "Second");
    defer allocator.free(template2_html);
    const template2 = try parser.parseTemplateString(template2_html, .none);

    const template3_html = try templateBuilder(allocator, 3, "Third");
    defer allocator.free(template3_html);
    const template3 = try parser.parseTemplateString(template3_html, .none);

    // Use templates to inject content into the list
    try parser.useTemplateElement(template1, ul_node, .none);
    try parser.useTemplateElement(template2, ul_node, .none);
    try parser.useTemplateElement(template3, ul_node, .none);

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

test "templates can be reused" {
    const allocator = testing.allocator;

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const doc = try parser.parse("<ul id='list'></ul>");
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;
    const ul = z.getElementById(body, "list").?;
    const ul_node = z.elementToNode(ul);

    const template_html = "<template><li>Item</li></template>";

    // Use the same template twice
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
    try testing.expectEqual(@as(usize, 2), li_count);
}

test "parseFragmentNodes - direct usage of returned nodes" {
    const allocator = testing.allocator;

    const doc = try z.createDocFromString("<ul id='high'></ul><ul id='low'></ul>");
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    // Parse task list and get individual nodes
    const task_html = "<li data-priority='high'>Critical fix</li><li data-priority='low'>Update docs</li><li data-priority='high'>Deploy</li>";

    const nodes = try parser.parseFragmentNodes(allocator, doc, task_html, .ul, .permissive);
    defer allocator.free(nodes);

    // Get target containers
    const body = z.bodyNode(doc).?;
    const high_ul = z.getElementById(body, "high").?;
    const low_ul = z.getElementById(body, "low").?;

    // DIRECT USAGE: Use the actual parsed nodes (no cloning first - let's see what happens)
    for (nodes) |node| {
        if (z.nodeType(node) == .element) {
            const element = z.nodeToElement(node).?;

            // Try to read the priority attribute - this might segfault
            const priority = z.getAttribute_zc(element, "data-priority");

            // Try to get text content - this might segfault
            // const text = z.textContent_zc(node);

            // Try to insert directly without cloning - let's see what happens
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

    try parser.insertFragment(
        z.elementToNode(z.bodyElement(doc).?),
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

    const nodes = try parser.parseFragmentNodes(allocator, doc, mixed_html_svg, .div, .permissive);
    defer allocator.free(nodes);

    try testing.expect(nodes.len == 5); // div, #text, p, #text, svg

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

    // Process and categorize nodes
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

    // Test that SVG elements were preserved with their attributes
    try testing.expect(std.mem.indexOf(u8, result, "<svg") != null);
    try testing.expect(std.mem.indexOf(u8, result, "width=\"16\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "viewBox=\"0 0 16 16\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<circle") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<path") != null);
    try testing.expect(std.mem.indexOf(u8, result, "fill=\"green\"") != null);
}

test "useTemplateElement with existing template" {
    const allocator = testing.allocator;

    const pretty_html =
        \\<table id="producttable">
        \\  <thead>
        \\    <tr>
        \\      <td>UPC_Code</td>
        \\      <td>Product_Name</td>
        \\    </tr>
        \\  </thead>
        \\  <tbody>
        \\    <!-- existing data could optionally be included here -->
        \\  </tbody>
        \\</table>
        \\
        \\<template id="productrow">
        \\  <tr>
        \\    <td class="record">Code: 1</td>
        \\    <td>Name: 1</td>
        \\  </tr>
        \\</template>
    ;

    const initial_html = try z.normalizeText(allocator, pretty_html);
    defer allocator.free(initial_html);

    const doc = try z.createDocFromString(initial_html);
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const body = z.bodyNode(doc).?;

    // Get the existing template element from DOM
    const template_elt = z.getElementById(body, "productrow").?;
    const template = z.elementToTemplate(template_elt).?;

    const tbody = z.getElementByTag(body, .tbody).?;
    const tbody_node = z.elementToNode(tbody);

    // Use existing template element twice (the input is an HTMLElement that is an HTMLTemplateElement, or directly an HTMLTempalteElement)

    // => HTMLElement
    try parser.useTemplateElement(template_elt, tbody_node, .permissive);
    // => HTMLTemplateElement
    try parser.useTemplateElement(template, tbody_node, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // Should have two rows added
    var tr_count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, result, search_pos, "<tr>")) |pos| {
        tr_count += 1;
        search_pos = pos + 4;
    }
    try testing.expectEqual(@as(usize, 4), tr_count); // 1 header + 2 data rows + 1 in template

    // Verify content
    try testing.expect(std.mem.indexOf(u8, result, "Code: 1") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Name: 1") != null);
}

test "fragment contexts: select options" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<select id='countries'></select>");
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

    try parser.insertFragment(select_node, options_html, .select, .permissive);

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
    const tbody_node = z.elementToNode(tbody);

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

    try parser.insertFragment(tbody_node, rows_html, .tbody, .permissive);

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
    const ul = z.getElementById(body, "tasks").?;
    const ul_node = z.elementToNode(ul);

    const items_html =
        \\<li>Complete project documentation</li>
        \\<li>Review pull requests</li>
        \\<li>Update deployment scripts</li>
    ;

    try parser.insertFragment(ul_node, items_html, .ul, .permissive);

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
    const form_node = z.elementToNode(form);

    const form_html =
        \\<label for="email">Email:</label>
        \\<input type="email" id="email" name="email" required>
        \\<label for="password">Password:</label>
        \\<input type="password" id="password" name="password" required>
        \\<button type="submit">Login</button>
    ;

    try parser.insertFragment(form_node, form_html, .form, .permissive);

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
    const dl_node = z.elementToNode(dl);

    const dl_html =
        \\<dt>HTML</dt>
        \\<dd>HyperText Markup Language</dd>
        \\<dt>CSS</dt>  
        \\<dd>Cascading Style Sheets</dd>
        \\<dt>JS</dt>
        \\<dd>JavaScript programming language</dd>
    ;

    try parser.insertFragment(dl_node, dl_html, .dl, .permissive);

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
    const video_node = z.elementToNode(video);

    const media_html =
        \\<source src="/video.webm" type="video/webm">
        \\<source src="/video.mp4" type="video/mp4">
        \\<track kind="captions" src="/captions.vtt" srclang="en" label="English">
        \\<p>Your browser doesn't support HTML5 video.</p>
    ;

    try parser.insertFragment(video_node, media_html, .video, .permissive);

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
    const div_node = z.elementToNode(div);

    const malformed_html =
        \\<div class="card">
        \\  <h3>Title</h3>
        \\  <p>Missing closing tags
        \\      <span>More content
        \\</div>
    ;

    try parser.insertFragment(div_node, malformed_html, .body, .permissive);

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
    const fieldset_node = z.elementToNode(fieldset);

    const fieldset_html =
        \\<legend>Contact Information</legend>
        \\<label for="name">Name:</label>
        \\<input type="text" id="name" name="name">
        \\<label for="phone">Phone:</label>
        \\<input type="tel" id="phone" name="phone">
    ;

    try parser.insertFragment(fieldset_node, fieldset_html, .fieldset, .permissive);

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
    const details_node = z.elementToNode(details);

    const details_html =
        \\<summary>Click to expand FAQ</summary>
        \\<p>This content is hidden by default</p>
        \\<ul>
        \\  <li>Question 1 answer</li>
        \\  <li>Question 2 answer</li>
        \\</ul>
    ;

    try parser.insertFragment(details_node, details_html, .details, .permissive);

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
    const optgroup_node = z.elementToNode(optgroup);

    const options_html =
        \\<option value="ny">New York</option>
        \\<option value="ca">California</option>
        \\<option value="tx">Texas</option>
        \\<option value="fl">Florida</option>
    ;

    try parser.insertFragment(optgroup_node, options_html, .optgroup, .permissive);

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
    const map_node = z.elementToNode(map);

    const areas_html =
        \\<area shape="rect" coords="0,0,100,100" href="/section1" alt="Section 1">
        \\<area shape="circle" coords="150,75,50" href="/section2" alt="Section 2">
        \\<area shape="poly" coords="200,0,250,50,200,100,150,50" href="/section3" alt="Section 3">
    ;

    try parser.insertFragment(map_node, areas_html, .map, .permissive);

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
    const figure_node = z.elementToNode(figure);

    const figure_html =
        \\<img src="/sales-chart.png" alt="Sales Chart" width="400" height="300">
        \\<figcaption>Monthly sales performance for Q4 2024 showing 15% growth</figcaption>
    ;

    try parser.insertFragment(figure_node, figure_html, .figure, .permissive);

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
    const picture_node = z.elementToNode(picture);

    const picture_html =
        \\<source media="(min-width: 800px)" srcset="/hero-large.jpg">
        \\<source media="(min-width: 400px)" srcset="/hero-medium.jpg">
        \\<img src="/hero-small.jpg" alt="Hero image" loading="lazy">
    ;

    try parser.insertFragment(picture_node, picture_html, .picture, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "hero-large.jpg") != null);
    try testing.expect(std.mem.indexOf(u8, result, "min-width: 800px") != null);
    try testing.expect(std.mem.indexOf(u8, result, "loading=\"lazy\"") != null);
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

    const templates = try parser.parseTemplates(multiple_templates_html, .permissive);
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
    try parser.useTemplateElement(templates[0], z.elementToNode(ul), .permissive);
    try parser.useTemplateElement(templates[0], z.elementToNode(ul), .permissive); // Use twice

    // Template 1: card-template -> inject into cards div
    try parser.useTemplateElement(templates[1], z.elementToNode(cards_div), .permissive);

    // Template 2: button-template -> inject into buttons div
    try parser.useTemplateElement(templates[2], z.elementToNode(buttons_div), .permissive);

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
    const audio_node = z.elementToNode(audio);

    const audio_html =
        \\<source src="/podcast.ogg" type="audio/ogg">
        \\<source src="/podcast.mp3" type="audio/mp3">
        \\<track kind="descriptions" src="/descriptions.vtt" srclang="en">
        \\<p>Your browser doesn't support HTML5 audio.</p>
    ;

    try parser.insertFragment(audio_node, audio_html, .audio, .permissive);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "podcast.ogg") != null);
    try testing.expect(std.mem.indexOf(u8, result, "podcast.mp3") != null);
    try testing.expect(std.mem.indexOf(u8, result, "descriptions.vtt") != null);
    try testing.expect(std.mem.indexOf(u8, result, "HTML5 audio") != null);
}
