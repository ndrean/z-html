const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const testing = std.testing;
// const print = std.debug.print;
const print = std.debug.print;

const HtmlParser = opaque {};
const HtmlTree = opaque {};
const LXB_HTML_SERIALIZE_OPT_UNDEF: c_int = 0x00;

// setInnerHTML
extern "c" fn lxb_html_element_inner_html_set(body: *z.HTMLElement, inner: [*]const u8, inner_len: usize) ?*z.HTMLElement;

// parser
extern "c" fn lxb_html_parser_create() ?*HtmlParser;
extern "c" fn lxb_html_parser_destroy(parser: *HtmlParser) *HtmlParser;
extern "c" fn lxb_html_parser_clean(parser: *HtmlParser) void;
extern "c" fn lxb_html_parser_init(parser: *HtmlParser) usize;

// creates a document from the given string with a parser
extern "c" fn lxb_html_parse(
    parser: *HtmlParser,
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
    parser: *HtmlParser,
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

extern "c" fn lxb_dom_document_create_document_fragment(doc: *z.HTMLDocument) ?*z.DocumentFragment;
extern "c" fn lxb_dom_document_fragment_interface_destroy(document_fragment: *z.DocumentFragment) *z.DocumentFragment;

// ================================================================

/// [fragment] Get the underlying DOM node from a fragment
pub fn fragmentToNode(fragment: *z.DocumentFragment) *z.DomNode {
    return z.objectToNode(fragment);
}

/// [fragment] Create a document fragment and returns a DocumentFragment
///
/// Document fragments are lightweight containers that can hold multiple nodes. Useful for batch DOM operations.
///
/// Browser spec: when you append a fragment to the DOM, only its children are added, not the fragment itself which is destroyed.
///
/// Use `appendFragment()` at insert the fragment into the DOM.
pub fn createDocumentFragment(doc: *z.HTMLDocument) !*z.DocumentFragment {
    return lxb_dom_document_create_document_fragment(doc) orelse Err.FragmentCreateFailed;
}

/// [fragment] Destroys a document fragment
pub fn destroyDocumentFragment(fragment: *z.DocumentFragment) void {
    _ = lxb_dom_document_fragment_interface_destroy(fragment);
    return;
}

test "creation DF" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);
    const fragment = try createDocumentFragment(doc);
    try testing.expect(z.isNodeEmpty(z.fragmentToNode(fragment)));
    destroyDocumentFragment(fragment);
}

/// [fragment] Append all children from a document fragment to a parent node
///
/// The fragment is emptied: the fragment children are moved into the DOM, not copied
pub fn appendFragment(parent: *z.DomNode, fragment: *z.DomNode) void {
    var fragment_child = z.firstChild(fragment);
    while (fragment_child != null) {
        const next_sibling = z.nextSibling(fragment_child.?);
        z.appendChild(parent, fragment_child.?);
        fragment_child = next_sibling;
    }
}

// ==========================================================

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

// [Serialize] Sets / replaces element's inner HTML with some security controls.
pub fn setInnerHTML(element: *z.HTMLElement, content: []const u8) !*z.HTMLElement {
    return lxb_html_element_inner_html_set(element, content.ptr, content.len) orelse Err.FragmentParseFailed;
}

test "first tests setInnerHTML" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Create a container element
    var div = try z.createElementAttr(doc, "div", &.{});

    // test 1 --------------
    div = try setInnerHTML(div, "<p id=\"1\">Hello <strong>World</strong></p>");
    const inner1 = try z.innerHTML(allocator, div);
    defer allocator.free(inner1);

    try testing.expectEqualStrings(
        "<p id=\"1\">Hello <strong>World</strong></p>",
        inner1,
    );

    const complex_html =
        \\<h1>Title</h1>
        \\<p class="intro">Introduction paragraph</p>
        \\<article>
        \\  <ul>
        \\    <li>Item 1</li>
        \\    <li>Item 2</li>
        \\  </ul>
        \\</article>
    ;

    // test 2 --------------
    div = try z.setInnerHTML(div, complex_html);

    const inner2 = try z.innerHTML(allocator, div);
    defer allocator.free(inner2);

    const inner3 = try z.outerHTML(allocator, div);
    defer allocator.free(inner3);

    try testing.expect(
        std.mem.indexOf(u8, inner2, "<h1>Title") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, inner2, "<ul>") != null,
    );

    try testing.expect(
        std.mem.indexOf(u8, inner2, "<p class=\"intro\">Intro") != null,
    );
    // check this removed old inner HTML
    try testing.expect(
        std.mem.indexOf(u8, inner2, "<p>Hello World</p>") == null,
    );

    // Test 3: Get outer HTML (includes the div itself) --------------
    const outer = try z.outerHTML(allocator, div);
    defer allocator.free(outer);
    // print("{s}\n", .{outer});

    // Should contain the root div tag
    try testing.expect(
        std.mem.indexOf(u8, outer, "<div>") != null,
    );
    // should could inner HTML
    try testing.expect(
        std.mem.indexOf(u8, outer, "<li>") != null,
    );

    try testing.expect(
        std.mem.indexOf(u8, outer, "</div>") != null,
    );
}
test "behaviour of serializeNode" {
    const allocator = testing.allocator;

    // Test different types of elements
    const test_cases = [_]struct {
        html: []const u8,
        serialized_tree: []const u8,
    }{
        // self-closing tags
        .{
            .html = "<br/>",
            .serialized_tree = "<br>",
        },
        .{
            .html = "<img src=\"my-image\"/>",
            .serialized_tree = "<img src=\"my-image\">",
        },
        .{
            .html = "<p><span></span></p>",
            .serialized_tree = "<p><span></span></p>",
        },
        .{
            .html = "<p></p>",
            .serialized_tree = "<p></p>",
        },
        .{
            .html = "<div data-id=\"myid\" class=\"test\">Simple text</div>",
            .serialized_tree = "<div data-id=\"myid\" class=\"test\">Simple text</div>",
        },
    };

    for (test_cases) |case| {
        const doc = try z.createDocFromString(case.html);
        defer z.destroyDocument(doc);

        const body = z.bodyElement(doc).?;
        const body_node = z.elementToNode(body);
        const element_node = z.firstChild(body_node).?;

        const serialized_tree = try z.outerHTML(allocator, z.nodeToElement(element_node).?);
        defer allocator.free(serialized_tree);

        // try testing.expectEqualStrings(serial_node, case.serialized_node);
        try testing.expectEqualStrings(serialized_tree, case.serialized_tree);
    }
}

test "setInnerHTML lexbor security sanitation" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const malicious_content = "<script>alert('XSS')</script><img src=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\"><a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a>";
    const div = try z.createElement(doc, "div");
    _ = try setInnerHTML(div, malicious_content); //<-- lexbor sanitizes this in part

    const outer = try z.innerHTML(allocator, div);
    defer allocator.free(outer);

    const expected = "<script>alert('XSS')</script><img src=\"data:text/html,&lt;script&gt;alert('XSS')&lt;/script&gt;\" alt=\"escaped\"><a href=\"http://example.org/results?search=&lt;img src=x onerror=alert('hello')&gt;\">URL Escaped</a>";

    try testing.expectEqualStrings(expected, outer);
}

test "sanitized HTML into a fragment given a document" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("");
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;

    const malicious_content = "<div><!-- a comment --><button phx-click=\"go\" onclick=\"alert('XSS')\">Become rich</button><script>alert('XSS')</script><img src=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\"><img src=\"/my-image.jpg\" alt=\"image\"></div>";

    var parser = try z.FragmentParser.init(allocator);
    defer parser.deinit();

    const fragment_root = try parser.parseString(
        malicious_content,
        .div,
        true,
    );
    defer z.destroyNode(fragment_root);

    z.appendFragment(body, fragment_root);
    const html_string = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html_string);

    try testing.expectEqualStrings("<body><div><button phx-click=\"go\">Become rich</button><img alt=\"escaped\"><img src=\"/my-image.jpg\" alt=\"image\"></div></body>", html_string);
}

/// [serialize] Set the inner HTML of an element with safe content
pub fn setInnerSafeHTML(allocator: std.mem.Allocator, element: *z.HTMLElement, content: []const u8) !void {
    const node = z.elementToNode(element);
    const target_doc = z.ownerDocument(node);

    var parser = try z.FragmentParser.init(allocator);
    defer parser.deinit();

    // lexbor sanitization + sanitizer enabled
    const fragment_root = try parser.parseFragmentCore(
        target_doc,
        content,
        .div,
        true,
    );
    parser.appendFragment(node, fragment_root);
}

test "setInnerSafeHTML" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("");
    defer z.destroyDocument(doc);

    const body_elt = z.bodyElement(doc).?;

    try z.setInnerSafeHTML(
        allocator,
        body_elt,
        "<!-- a comment --><script>alert('XSS')</script><p id=\"1\" phx-click=\"increment\">Click me</p><a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a>",
    );

    const html = try z.innerHTML(allocator, body_elt);
    defer allocator.free(html);

    try testing.expectEqualStrings(
        "<p id=\"1\" phx-click=\"increment\">Click me</p><a href=\"http://example.org/results?search=&lt;img src=x onerror=alert('hello')&gt;\">URL Escaped</a>",
        html,
    );
}

// ===================================================================

/// [parser] HTML Parser structure and methods. Not thread safe.
///
/// Methods: `init`, `deinit`, `parse`, `parseFragment`, `parseFragmentCore`, `parseTemplate`, `parseTemplates`, `useTemplate`, `useTemplateElement`, `insertFragment`, `parseFragmentNodes`
pub const FragmentParser = struct {
    allocator: std.mem.Allocator,
    html_parser: *HtmlParser,
    initialized: bool,

    var temp_doc: ?*z.HTMLDocument = null;
    var temp_frag_doc: ?*z.DocumentFragment = null;

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
    pub fn deinit(self: *FragmentParser) void {
        if (!self.initialized) return;

        if (temp_doc) |doc| {
            z.destroyDocument(doc);
            temp_doc = null;
        }

        lxb_html_parser_clean(self.html_parser);
        _ = lxb_html_parser_destroy(self.html_parser);
        self.initialized = false;
    }

    /// Fragment parsing using a given document
    ///
    /// The return node is the `<html>` node: its children are the parsed elements.
    pub fn parseFragmentCore(
        self: *FragmentParser,
        doc: *z.HTMLDocument,
        html: []const u8,
        context: z.FragmentContext,
        sanitizer_enabled: bool,
    ) !*z.DomNode {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        const context_tag = context.toTagName();
        const context_element = try z.createElement(doc, context_tag);
        defer z.destroyElement(context_element);

        const fragment_root = lxb_html_document_parse_fragment(
            doc,
            context_element,
            html.ptr,
            html.len,
        ) orelse return Err.ParseFailed;

        if (sanitizer_enabled) {
            try z.sanitizeNode(self.allocator, fragment_root);
        }

        return fragment_root;
    }

    /// Parse an HTML fragment string into a DocumentFragment rooted at the context element.
    ///
    /// The returned fragment_root in the `<html>` element; the children are the parsed elements.
    pub fn parseString(
        self: *FragmentParser,
        html: []const u8,
        context: z.FragmentContext,
        sanitizer_enabled: bool,
    ) !*z.DomNode {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        if (FragmentParser.temp_doc == null) {
            temp_doc = try z.createDocument();
        } else {
            z.cleanDocument(temp_doc.?);
        }

        const context_tag = context.toTagName();
        const context_element = try z.createElement(temp_doc.?, context_tag);

        const fragment_root = lxb_html_parse_fragment(
            self.html_parser,
            context_element,
            html.ptr,
            html.len,
        ) orelse {
            return Err.ParseFailed;
        };

        if (sanitizer_enabled) {
            try z.sanitizeNode(self.allocator, fragment_root);
        }

        return fragment_root;
    }

    pub fn appendFragment(_: *FragmentParser, parent: *z.DomNode, fragment_node: *z.DomNode) void {
        var fragment_child = z.firstChild(fragment_node);
        while (fragment_child != null) {
            const next_sibling = z.nextSibling(fragment_child.?);
            z.appendChild(parent, fragment_child.?);
            fragment_child = next_sibling;
        }
        z.destroyNode(fragment_node);
    }

    pub fn setInnerSafeHTML(self: *FragmentParser, element: *z.HTMLElement, content: []const u8) !void {
        const node = z.elementToNode(element);
        const target_doc = z.ownerDocument(node);

        // lexbor sanitization + sanitizer enabled
        const fragment_root = try self.parseFragmentCore(
            target_doc,
            content,
            .div,
            true,
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
        self: *FragmentParser,
        html: []const u8,
        sanitizer_enabled: bool,
    ) !*z.HTMLTemplateElement {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        const fragment_root = try self.parseString(html, .template, sanitizer_enabled);

        // print("{s}\n", .{z.nodeName_zc(z.firstChild(fragment_root).?)});

        const template_node = z.firstChild(fragment_root) orelse return Err.ParseFailed;
        const template_element = z.nodeToElement(template_node) orelse return Err.ParseFailed;
        const template = z.elementToTemplate(template_element) orelse return Err.ParseFailed;

        // Remove template from fragment_root to detach it (preserve DocumentFragment structure)
        z.removeNode(template_node);
        z.destroyNode(fragment_root); // Clean up the now-empty container

        return template;
    }

    /// Parse multiple templates from HTML and return them as a slice of template elements
    pub fn parseTemplates(
        self: *FragmentParser,
        html: []const u8,
        sanitizer_enabled: bool,
    ) ![]const *z.HTMLTemplateElement {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        const fragment_root = try self.parseString(html, .body, sanitizer_enabled);
        defer z.destroyNode(fragment_root);

        var templates: std.ArrayList(*z.HTMLTemplateElement) = .empty;
        defer templates.deinit(self.allocator);

        var child = z.firstChild(fragment_root);
        while (child != null) {
            if (z.nodeType(child.?) == .element) {
                const element = z.nodeToElement(child.?).?;
                if (z.elementToTemplate(element)) |_| {
                    const template_doc = z.ownerDocument(child.?);
                    const cloned_node = z.cloneNode(child.?, template_doc) orelse continue;
                    const cloned_template = z.elementToTemplate(z.nodeToElement(cloned_node).?).?;
                    try templates.append(self.allocator, cloned_template);
                }
            }
            child = z.nextSibling(child.?);
        }

        return templates.toOwnedSlice(self.allocator);
    }

    /// Parse template string and inject it into the target node
    pub fn useTemplateString(
        self: *FragmentParser,
        template_html: []const u8,
        target: *z.DomNode,
        sanitizer_enabled: bool,
    ) !void {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        // Parse template
        const template = try self.parseTemplateString(template_html, sanitizer_enabled);
        defer z.destroyNode(z.templateToNode(template).?);

        // Use template (clones content)
        return z.useTemplateElement(template, target);
    }

    /// Use an existing template element and injects it into target node
    pub fn useTemplateElement(
        self: *FragmentParser,
        template_element: *z.HTMLTemplateElement,
        target: *z.DomNode,
    ) !void {
        _ = self; // Parser not needed for this operation
        return z.useTemplateElement(template_element, target);
    }

    /// Parse HTML fragment string and insert it directly into parent given a context (most common use case)
    pub fn insertFragment(
        self: *FragmentParser,
        parent: *z.DomNode,
        html: []const u8,
        context: z.FragmentContext,
        sanitizer_enabled: bool,
    ) !void {
        const parent_doc = z.ownerDocument(parent);
        const fragment_root = try self.parseFragmentCore(
            parent_doc,
            html,
            context,
            sanitizer_enabled,
        );
        defer z.destroyNode(fragment_root);

        self.appendFragment(parent, fragment_root);
    }

    /// Parse HTML fragment and return array of child nodes
    pub fn parseFragmentNodes(
        self: *FragmentParser,
        allocator: std.mem.Allocator,
        doc: *z.HTMLDocument,
        html: []const u8,
        context: z.FragmentContext,
        sanitizer_enabled: bool,
    ) ![]*z.DomNode {
        const fragment_root = try self.parseFragmentCore(doc, html, context, sanitizer_enabled);
        defer z.destroyNode(fragment_root);

        return z.childNodes(allocator, fragment_root);
    }
};

test "security of parseFragment and appendFragment first test" {
    const doc = try createDocFromString("<div id=\"1\"></div>");
    defer z.destroyDocument(doc);

    const allocator = testing.allocator;

    var parser = try FragmentParser.init(allocator);
    defer parser.deinit();

    const html1 = "<p> some text</p>";
    const frag_root1 = try parser.parseString(
        html1,
        .body,
        false,
    );

    const html2 = "<div> more <i>text</i><span><script>alert(1);</script></span></div>";
    const frag_root2 = try parser.parseString(
        html2,
        .body,
        true,
    );

    const html3 = "<ul><li><script>alert(1);</script></li></ul>";
    const frag_root3 = try parser.parseString(
        html3,
        .body,
        true,
    );

    const html4 = "<a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a>";
    const frag_root4 = try parser.parseString(
        html4,
        .body,
        false,
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

test "Serializer sanitation" {
    const allocator = testing.allocator;

    const malicious_content = "<div><button disabled hidden onclick=\"alert('XSS')\" phx-click=\"increment\">Potentially dangerous, not escaped</button><!-- a comment --><div data-time=\"{@current}\"> The current value is: {@counter} </div> <a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a><a href=\"javascript:alert('XSS')\">Dangerous, not escaped</a><img src=\"javascript:alert('XSS')\" alt=\"not escaped\"><iframe src=\"javascript:alert('XSS')\" alt=\"not escaped\"></iframe><a href=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\">Safe escaped</a><img src=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\"><iframe src=\"data:text/html,<script>alert('XSS')</script>\" >Escaped</iframe><img src=\"data:image/svg+xml,<svg onload=alert('XSS')\" alt=\"escaped\"></svg>\"><img src=\"data:image/svg+xml;base64,PHN2ZyBvbmxvYWQ9YWxlcnQoJ1hTUycpPjwvc3ZnPg==\" alt=\"potential dangerous b64\"><a href=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgnWFNTJyk8L3NjcmlwdD4=\">Potential dangerous b64</a><img src=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgnWFNTJyk8L3NjcmlwdD4=\" alt=\"potential dangerous b64\"><a href=\"file:///etc/passwd\">Dangerous Local file access</a><img src=\"file:///etc/passwd\" alt=\"dangerous local file access\"><p>Hello<i>there</i>, all<strong>good?</strong></p><p>Visit this link: <a href=\"https://example.com\">example.com</a></p></div><link href=\"/shared-assets/misc/link-element-example.css\" rel=\"stylesheet\"><script>console.log(\"hi\");</script><template></template>";

    const doc = try z.createDocFromString("");
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;

    // const fragment = try z.createDocumentFragment(doc);
    // const fragment_node = z.fragmentToNode(fragment);
    // defer z.destroyNode(fragment_node);

    var parser = try z.FragmentParser.init(allocator);
    defer parser.deinit();

    try parser.setInnerSafeHTML(
        z.nodeToElement(body).?,
        malicious_content,
    );

    const final_html = try z.outerNodeHTML(allocator, body);
    defer allocator.free(final_html);

    // try z.prettyPrint(body);
}

test "inserFragment in one go" {
    const doc = try createDocFromString("<div id=\"1\"></div>");
    defer z.destroyDocument(doc);

    const allocator = testing.allocator;

    var parser = try FragmentParser.init(allocator);
    defer parser.deinit();

    const html1 = "<p> some text</p>";
    const html2 = "<div> more <i>text</i><span><script>alert(1);</script></span></div>";
    const html3 = "<ul><li><script>alert(1);</script></li></ul>";

    const div_elt = z.getElementById(z.bodyNode(doc).?, "1").?;
    const div: *z.DomNode = @ptrCast(div_elt);

    // append fragments and check the result
    try parser.insertFragment(div, html1, .div, false);
    try parser.insertFragment(div, html2, .div, true);
    try parser.insertFragment(div, html3, .div, true);

    const result = try z.outerHTML(allocator, div_elt);
    defer allocator.free(result);

    const expected = "<div id=\"1\"><p> some text</p><div> more <i>text</i><span></span></div><ul><li></li></ul></div>";
    try testing.expectEqualStrings(expected, result);
}

test "template parsing and use template element" {
    const allocator = testing.allocator;

    const doc = try z.createDocFromString("<ul id='items'></ul>");
    defer z.destroyDocument(doc);

    var parser = try z.FragmentParser.init(allocator);
    defer parser.deinit();

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
    const template1 = try parser.parseTemplateString(template1_html, false);

    const template2_html = try templateBuilder(allocator, 2, "Second");
    defer allocator.free(template2_html);
    const template2 = try parser.parseTemplateString(template2_html, false);

    const template3_html = try templateBuilder(allocator, 3, "Third");
    defer allocator.free(template3_html);
    const template3 = try parser.parseTemplateString(template3_html, false);

    // Use templates to inject content into the list
    try parser.useTemplateElement(template1, ul_node);
    try parser.useTemplateElement(template2, ul_node);
    try parser.useTemplateElement(template3, ul_node);

    // Test that everything is properly in the body
    const result_html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result_html);

    // print("Final document body: {s}\n", .{result_html});

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

test "useTemplate string reuses same template" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
    defer parser.deinit();

    // Create document with target ul
    try parseString(doc, "<ul id='list'></ul>");
    const body = z.bodyNode(doc).?;
    const ul = z.getElementById(body, "list").?;
    const ul_node = z.elementToNode(ul);

    const template_html = "<template><li>Item</li></template>";

    // Use the same template twice
    try parser.useTemplateString(template_html, ul_node, false);
    try parser.useTemplateString(template_html, ul_node, false);

    // Check result
    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Reused template result: {s}\n", .{result});

    // Should have two <li>Item</li> elements
    var li_count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, result, search_pos, "<li>Item</li>")) |pos| {
        li_count += 1;
        search_pos = pos + 12; // length of "<li>Item</li>"
    }
    try testing.expectEqual(@as(usize, 2), li_count);
}

test "parseFragmentNodes" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
    defer parser.deinit();

    // Create document with target div
    try parseString(doc, "<div id='container'></div>");
    const body = z.bodyNode(doc).?;
    const container = z.getElementById(body, "container").?;
    const container_node = z.elementToNode(container);

    // Test insertFragment - direct parse and insert
    const fragment_html = "<p>Hello</p><span>World</span>";
    try parser.insertFragment(container_node, fragment_html, .body, false);

    // Test parseFragmentNodes - get individual nodes
    const nodes = try parser.parseFragmentNodes(
        allocator,
        doc,
        "<li>Item 1</li><li>Item 2</li>",
        .ul,
        false,
    );
    defer allocator.free(nodes);

    try testing.expect(nodes.len == 2);
    try testing.expectEqualStrings("LI", z.nodeName_zc(nodes[0]));
    try testing.expectEqualStrings("LI", z.nodeName_zc(nodes[1]));

    // Verify insertFragment worked
    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Simplified fragment result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "<p>Hello</p>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<span>World</span>") != null);
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

    const initial_html = try z.normalizeText(allocator, pretty_html, .{});
    defer allocator.free(initial_html);

    const doc = try z.createDocFromString(initial_html);
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
    defer parser.deinit();

    const body = z.bodyNode(doc).?;

    // Get the existing template element from DOM
    const template_elt = z.getElementById(body, "productrow").?;
    const template = z.elementToTemplate(template_elt).?;

    const tbody = z.getElementByTag(body, .tbody).?;
    const tbody_node = z.elementToNode(tbody);

    // Use existing template element twice
    try parser.useTemplateElement(template, tbody_node);
    try parser.useTemplateElement(template, tbody_node);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Template element result: {s}\n", .{result});

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

test "sanitizer removes scripts" {
    const allocator = testing.allocator;

    const malicious_html = "<div> more <i>text</i><span><script>alert(1);</script></span></div>";

    var parser = try FragmentParser.init(allocator);
    defer parser.deinit();

    // Test without sanitizer
    const frag_no_sanitizer = try parser.parseString(malicious_html, .body, false);
    const result_no_sanitizer = try z.outerHTML(allocator, z.nodeToElement(frag_no_sanitizer).?);
    defer allocator.free(result_no_sanitizer);

    // Test with sanitizer
    const frag_sanitized = try parser.parseString(malicious_html, .body, true);
    const result_sanitized = try z.outerHTML(allocator, z.nodeToElement(frag_sanitized).?);
    defer allocator.free(result_sanitized);

    // print("No sanitizer: {s}\n", .{result_no_sanitizer});
    // print("Sanitized:    {s}\n", .{result_sanitized});

    // Sanitizer removes script content
    try testing.expect(std.mem.indexOf(u8, result_sanitized, "alert(1);") == null);
    try testing.expect(std.mem.indexOf(u8, result_no_sanitizer, "alert(1);") != null);
}

test "fragment contexts: select options" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
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

    try parser.insertFragment(select_node, options_html, .select, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Select options result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "United States") != null);
    try testing.expect(std.mem.indexOf(u8, result, "optgroup") != null);
    try testing.expect(std.mem.indexOf(u8, result, "United Kingdom") != null);
}

test "fragment contexts: table rows" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
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

    try parser.insertFragment(tbody_node, rows_html, .tbody, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Table rows result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "<td>John</td>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<td>Jane</td>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Developer") != null);
}

test "fragment contexts: list items" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
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

    try parser.insertFragment(ul_node, items_html, .ul, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("List items result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "Complete project") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Review pull") != null);
    try testing.expect(std.mem.indexOf(u8, result, "deployment scripts") != null);
}

test "fragment contexts: form elements" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
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

    try parser.insertFragment(form_node, form_html, .form, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Form elements result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "type=\"email\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "type=\"password\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Login</button>") != null);
}

test "fragment contexts: definition lists" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
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

    try parser.insertFragment(dl_node, dl_html, .dl, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Definition list result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "<dt>HTML</dt>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "HyperText Markup") != null);
    try testing.expect(std.mem.indexOf(u8, result, "JavaScript programming") != null);
}

test "fragment contexts: media elements" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
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

    try parser.insertFragment(video_node, media_html, .video, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Media elements result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "video.webm") != null);
    try testing.expect(std.mem.indexOf(u8, result, "captions.vtt") != null);
    try testing.expect(std.mem.indexOf(u8, result, "HTML5 video") != null);
}

test "fragment contexts: malformed HTML recovery" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
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

    try parser.insertFragment(div_node, malformed_html, .body, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Malformed HTML recovery: {s}\n", .{result});

    // lexbor should auto-fix the malformed HTML
    try testing.expect(std.mem.indexOf(u8, result, "<h3>Title</h3>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Missing closing") != null);
    try testing.expect(std.mem.indexOf(u8, result, "More content") != null);
}

test "fragment contexts: fieldset legend" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
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

    try parser.insertFragment(fieldset_node, fieldset_html, .fieldset, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Fieldset result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "<legend>Contact Information</legend>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "type=\"text\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "type=\"tel\"") != null);
}

test "fragment contexts: details summary" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
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

    try parser.insertFragment(details_node, details_html, .details, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Details result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "<summary>Click to expand") != null);
    try testing.expect(std.mem.indexOf(u8, result, "hidden by default") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Question 1 answer") != null);
}

test "fragment contexts: optgroup nested options" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
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

    try parser.insertFragment(optgroup_node, options_html, .optgroup, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Optgroup result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "New York") != null);
    try testing.expect(std.mem.indexOf(u8, result, "California") != null);
    try testing.expect(std.mem.indexOf(u8, result, "value=\"tx\"") != null);
}

test "fragment contexts: map areas" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
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

    try parser.insertFragment(map_node, areas_html, .map, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Map areas result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "shape=\"rect\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "shape=\"circle\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "shape=\"poly\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "href=\"/section1\"") != null);
}

test "fragment contexts: figure caption" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
    defer parser.deinit();

    try parseString(doc, "<figure id='chart'></figure>");
    const body = z.bodyNode(doc).?;
    const figure = z.getElementById(body, "chart").?;
    const figure_node = z.elementToNode(figure);

    const figure_html =
        \\<img src="/sales-chart.png" alt="Sales Chart" width="400" height="300">
        \\<figcaption>Monthly sales performance for Q4 2024 showing 15% growth</figcaption>
    ;

    try parser.insertFragment(figure_node, figure_html, .figure, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Figure result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "sales-chart.png") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<figcaption>Monthly sales") != null);
    try testing.expect(std.mem.indexOf(u8, result, "15% growth") != null);
}

test "fragment contexts: picture responsive" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
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

    try parser.insertFragment(picture_node, picture_html, .picture, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Picture result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "hero-large.jpg") != null);
    try testing.expect(std.mem.indexOf(u8, result, "min-width: 800px") != null);
    try testing.expect(std.mem.indexOf(u8, result, "loading=\"lazy\"") != null);
}

test "fragment contexts: audio sources" {
    const allocator = testing.allocator;

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    var parser = try FragmentParser.init(allocator);
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

    try parser.insertFragment(audio_node, audio_html, .audio, false);

    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);

    // print("Audio result: {s}\n", .{result});

    try testing.expect(std.mem.indexOf(u8, result, "podcast.ogg") != null);
    try testing.expect(std.mem.indexOf(u8, result, "podcast.mp3") != null);
    try testing.expect(std.mem.indexOf(u8, result, "descriptions.vtt") != null);
    try testing.expect(std.mem.indexOf(u8, result, "HTML5 audio") != null);
}
