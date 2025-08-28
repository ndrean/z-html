const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;

// html/parser.h
extern "c" fn lxb_html_parser_create() ?*z.HtmlParser;
extern "c" fn lxb_html_parser_init(parser: *z.HtmlParser) c_int;
extern "c" fn lxb_html_parser_destroy(parser: *z.HtmlParser) ?*z.HtmlParser;
extern "c" fn lxb_html_parser_clean(parser: *z.HtmlParser) void;

// Parser configuration - using the actual lexbor API
extern "c" fn lxb_html_parser_scripting_set_noi(parser: *z.HtmlParser, scripting: bool) void;
extern "c" fn lxb_html_parser_scripting_noi(parser: *z.HtmlParser) bool;

// Parse functions - using the actual lexbor API
extern "c" fn lxb_html_parse(parser: *z.HtmlParser, html: [*]const u8, html_len: usize) ?*z.HTMLDocument;

extern "c" fn lxb_html_parse_fragment(parser: *z.HtmlParser, element: *z.HTMLElement, html: [*]const u8, html_len: usize) ?*z.DomNode;

extern "c" fn lxb_html_parse_fragment_by_tag_id(parser: *z.HtmlParser, document: *z.HTMLDocument, tag_id: u32, ns: u32, html: [*]const u8, html_len: usize) ?*z.DomNode;

// Chunk parsing for streaming
extern "c" fn lxb_html_parse_chunk_begin(parser: *z.HtmlParser) ?*z.HTMLDocument;
extern "c" fn lxb_html_parse_chunk_process(parser: *z.HtmlParser, html: [*]const u8, html_len: usize) c_int;
extern "c" fn lxb_html_parse_chunk_end(parser: *z.HtmlParser) c_int;

/// Cached parsed content for templates and fragments
pub const CachedContent = struct {
    allocator: std.mem.Allocator,
    original_html: []const u8,

    // Union to handle different content types
    content: union(z.FragmentContext) {
        template: *z.HTMLTemplateElement,
        fragment: FragmentCache,
        document: *z.HTMLDocument,
    },

    const ContentType = enum { template, fragment, document };
    const FragmentCache = struct {
        document: *z.HTMLDocument,
        root_node: *z.DomNode,
    };

    pub fn deinit(self: *CachedContent) void {
        switch (self.content) {
            .template => |template| z.destroyTemplate(template),
            .fragment => |frag| z.destroyDocument(frag.document),
            .document => |doc| z.destroyDocument(doc),
        }
        self.allocator.free(self.original_html);
    }

    pub fn getTemplate(self: *const CachedContent) ?*z.HTMLTemplateElement {
        return switch (self.content) {
            .template => |t| t,
            else => null,
        };
    }

    pub fn getFragmentRoot(self: *const CachedContent) ?*z.DomNode {
        return switch (self.content) {
            .fragment => |f| f.root_node,
            else => null,
        };
    }

    pub fn getDocument(self: *const CachedContent) ?*z.HTMLDocument {
        return switch (self.content) {
            .document => |d| d,
            .fragment => |f| f.document,
            else => null,
        };
    }
};

pub const HtmlParserEngine = struct {
    allocator: std.mem.Allocator,
    parser: *z.HtmlParser,
    initialized: bool = false,

    // Caches for different content types
    template_cache: std.StringHashMap(CachedContent),
    fragment_cache: std.StringHashMap(CachedContent),
    document_cache: std.StringHashMap(CachedContent),

    // Parser configuration
    scripting_enabled: bool = false,
    sanitize_on_parse: bool = true,
    sanitizer_options: z.SanitizerOptions,

    const Self = @This();

    pub const Config = struct {
        scripting_enabled: bool = false,
        sanitize_on_parse: bool = true,
        sanitizer_options: z.SanitizerOptions = .{},
        max_cache_size: usize = 100,

        // Security policy options
        security_policy: SecurityPolicy = .strict,
    };

    pub const SecurityPolicy = enum {
        /// Remove all dangerous elements completely
        strict,
        /// Use parser scripting=false + selective sanitization
        parser_controlled,
        /// Only use parser scripting control, no sanitization
        parser_only,
        /// No security measures (dangerous - for trusted content only)
        none,

        pub fn getSanitizerOptions(self: SecurityPolicy) z.SanitizerOptions {
            return switch (self) {
                .strict => .{
                    .skip_comments = true,
                    .remove_scripts = true,
                    .remove_styles = true,
                    .strict_uri_validation = true,
                },
                .parser_controlled => .{
                    .skip_comments = true,
                    .remove_scripts = false, // Let parser handle scripts
                    .remove_styles = true, // Still remove styles
                    .strict_uri_validation = true,
                },
                .parser_only => .{
                    .skip_comments = false,
                    .remove_scripts = false,
                    .remove_styles = false,
                    .strict_uri_validation = false,
                },
                .none => .{
                    .skip_comments = false,
                    .remove_scripts = false,
                    .remove_styles = false,
                    .strict_uri_validation = false,
                },
            };
        }

        pub fn getScriptingEnabled(self: SecurityPolicy) bool {
            return switch (self) {
                .strict, .parser_controlled, .parser_only => false,
                .none => true,
            };
        }
    };

    /// Initialize HTML parser engine with configuration
    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        const parser = lxb_html_parser_create() orelse return Err.HtmlParserCreateFailed;

        if (lxb_html_parser_init(parser) != z._OK) {
            _ = lxb_html_parser_destroy(parser);
            return Err.HtmlParserInitFailed;
        }

        // Configure parser based on security policy
        const scripting_enabled = config.security_policy.getScriptingEnabled();
        lxb_html_parser_scripting_set_noi(parser, scripting_enabled);

        // Get sanitizer options from security policy
        const sanitizer_options = config.security_policy.getSanitizerOptions();

        return .{
            .allocator = allocator,
            .parser = parser,
            .initialized = true,
            .template_cache = std.StringHashMap(CachedContent).init(allocator),
            .fragment_cache = std.StringHashMap(CachedContent).init(allocator),
            .document_cache = std.StringHashMap(CachedContent).init(allocator),
            .scripting_enabled = scripting_enabled,
            .sanitize_on_parse = config.sanitize_on_parse,
            .sanitizer_options = sanitizer_options,
        };
    }

    pub fn deinit(self: *Self) void {
        if (!self.initialized) return;

        // Clean up all caches
        self.cleanupCache(&self.template_cache);
        self.cleanupCache(&self.fragment_cache);
        self.cleanupCache(&self.document_cache);

        // Clean and destroy parser
        lxb_html_parser_clean(self.parser);
        _ = lxb_html_parser_destroy(self.parser);
        self.initialized = false;
    }

    fn cleanupCache(self: *Self, cache: *std.StringHashMap(CachedContent)) void {
        _ = self;
        var iterator = cache.iterator();
        while (iterator.next()) |entry| {
            var cached = entry.value_ptr;
            cached.deinit();
        }
        cache.deinit();
    }

    /// Parse and cache a sanitized template for reuse
    pub fn parseTemplate(
        self: *Self,
        html: []const u8,
    ) !*z.HTMLTemplateElement {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        // Check cache first
        if (self.template_cache.get(html)) |cached| {
            return cached.getTemplate().?;
        }

        // Create a document to hold our template
        const doc = lxb_html_parser_create(self.parser, "", 0) orelse
            return Err.HtmlParseDocumentFailed;

        // Create sanitized template
        const template = try z.createSanitizedTemplate(
            self.allocator,
            doc,
            html,
            self.sanitizer_options,
        );

        // Cache it
        const owned_html = try self.allocator.dupe(u8, html);
        const cached_content = CachedContent{
            .allocator = self.allocator,
            .original_html = owned_html,
            .content = .{ .template = template },
        };

        try self.template_cache.put(owned_html, cached_content);
        return template;
    }

    /// Parse and cache a sanitized fragment for reuse
    pub fn parseFragmentByTagId(
        self: *Self,
        html: []const u8,
        tag_id: u32,
        ns_id: u32,
    ) !*z.DomNode {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        // Create cache key with tag context
        const cache_key = try std.fmt.allocPrint(self.allocator, "tag_{}:ns_{}:{s}", .{ tag_id, ns_id, html });
        defer self.allocator.free(cache_key);

        // Check cache
        if (self.fragment_cache.get(cache_key)) |cached| {
            return cached.getFragmentRoot().?;
        }

        // Create a temporary document for parsing
        const temp_doc = lxb_html_parse(self.parser, "", 0) orelse
            return Err.HtmlParseDocumentFailed;

        // Parse fragment using lexbor's tag-based parsing
        const fragment_root = lxb_html_parse_fragment_by_tag_id(
            self.parser,
            temp_doc,
            tag_id,
            ns_id,
            html.ptr,
            html.len,
        ) orelse {
            z.destroyDocument(temp_doc);
            return Err.FragmentParseFailed;
        };

        // Sanitize if configured
        if (self.sanitize_on_parse) {
            try self.sanitizeNode(fragment_root);
        }

        // Cache the result
        const owned_key = try self.allocator.dupe(u8, cache_key);
        const cached_content = CachedContent{
            .allocator = self.allocator,
            .original_html = owned_key,
            .content = .{ .fragment = .{
                .document = temp_doc,
                .root_node = fragment_root,
            } },
        };

        try self.fragment_cache.put(owned_key, cached_content);
        return fragment_root;
    }

    /// Parse fragment with element context (traditional approach)
    pub fn parseFragment(
        self: *Self,
        html: []const u8,
        context: z.FragmentContext,
    ) !*z.DomNode {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        // Create cache key with context
        const cache_key = try std.fmt.allocPrint(self.allocator, "{s}:::{s}", .{ @tagName(context), html });
        defer self.allocator.free(cache_key);

        // Check cache
        if (self.fragment_cache.get(cache_key)) |cached| {
            return cached.getFragmentRoot().?;
        }

        // Create temporary document and context element
        const temp_doc = lxb_html_parse(self.parser, "", 0) orelse
            return Err.HtmlParseDocumentFailed;

        const context_tag = context.toTagName();
        const context_element = try z.createElement(temp_doc, context_tag);

        // Parse using lexbor's element-based fragment parsing
        const fragment_root = lxb_html_parse_fragment(
            self.parser,
            context_element,
            html.ptr,
            html.len,
        ) orelse {
            z.destroyDocument(temp_doc);
            return Err.FragmentParseFailed;
        };

        // Sanitize if configured
        if (self.sanitize_on_parse) {
            try self.sanitizeNode(fragment_root);
        }

        // Cache the result
        const owned_key = try self.allocator.dupe(u8, cache_key);
        const cached_content = CachedContent{
            .allocator = self.allocator,
            .original_html = owned_key,
            .content = .{ .fragment = .{
                .document = temp_doc,
                .root_node = fragment_root,
            } },
        };

        try self.fragment_cache.put(owned_key, cached_content);
        return fragment_root;
    }

    /// Helper to sanitize a node and its children
    fn sanitizeNode(self: *Self, node: *z.DomNode) !void {
        if (z.nodeToElement(node)) |element| {
            try z.sanitizeWithOptions(
                self.allocator,
                element,
                self.sanitizer_options,
            );
        }

        // Recursively sanitize children
        var child = z.firstChild(node);
        while (child != null) {
            const next = z.nextSibling(child.?);
            try self.sanitizeNode(child.?);
            child = next;
        }
    }

    /// High-performance innerHTML using cached fragments
    pub fn setInnerHTMLCached(
        self: *Self,
        element: *z.HTMLElement,
        html: []const u8,
        context: z.FragmentContext,
    ) !void {
        // Get cached fragment
        const fragment_root = try self.parseFragment(html, context);

        // Clear target element
        const element_node = z.elementToNode(element);
        var child = z.firstChild(element_node);
        while (child != null) {
            const next = z.nextSibling(child.?);
            z.removeNode(child.?);
            z.destroyNode(child.?);
            child = next;
        }

        // Clone and append fragment content
        const target_doc = z.ownerDocument(element_node);
        const children = try z.childNodes(self.allocator, fragment_root);
        defer self.allocator.free(children);

        for (children) |child_node| {
            const cloned = z.importNode(child_node, target_doc);
            z.appendChild(element_node, cloned);
        }
    }

    /// High-performance template usage with caching
    pub fn useTemplateCached(
        self: *Self,
        element: *z.HTMLElement,
        template_html: []const u8,
    ) !void {
        const template = try self.parseTemplate(template_html);
        try z.setInnerHTMLFromTemplate(element, template);
    }

    /// Parse complete documents with caching
    pub fn parseDocument(self: *Self, html: []const u8) !*z.HTMLDocument {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        // Check cache
        if (self.document_cache.get(html)) |cached| {
            return cached.getDocument().?;
        }

        // Parse new document using lexbor parser
        const doc = lxb_html_parse(
            self.parser,
            html.ptr,
            html.len,
        ) orelse return Err.HtmlParseDocumentFailed;

        // Sanitize if configured
        if (self.sanitize_on_parse) {
            const body = z.bodyElement(doc) catch |err| switch (err) {
                z.Err.NoBodyElement => {
                    // Create body if it doesn't exist
                    const html_element = try z.createElement(doc);
                    const body_element = try z.createElement(doc, "body");
                    z.appendChild(z.elementToNode(html_element), z.elementToNode(body_element));
                    // body
                },
                else => return err,
            };

            try z.sanitizeWithOptions(self.allocator, body, self.sanitizer_options);
        }

        // Cache result
        const owned_html = try self.allocator.dupe(u8, html);
        const cached_content = CachedContent{
            .allocator = self.allocator,
            .original_html = owned_html,
            .content = .{ .document = doc },
        };

        try self.document_cache.put(owned_html, cached_content);
        return doc;
    }

    /// Get current parser scripting setting
    pub fn getScriptingEnabled(self: *const Self) bool {
        if (!self.initialized) return false;
        return lxb_html_parser_scripting_noi(self.parser);
    }

    /// Update parser scripting setting
    pub fn setScriptingEnabled(self: *Self, enabled: bool) void {
        if (!self.initialized) return;
        lxb_html_parser_scripting_set_noi(self.parser, enabled);
        self.scripting_enabled = enabled;
    }

    /// Stream parsing - begin parsing a large document in chunks
    pub fn parseChunkBegin(self: *Self) !*z.HTMLDocument {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        return lxb_html_parse_chunk_begin(self.parser) orelse
            Err.HtmlParseDocumentFailed;
    }

    /// Stream parsing - process a chunk of HTML
    pub fn parseChunkProcess(self: *Self, html_chunk: []const u8) !void {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        const status = lxb_html_parse_chunk_process(
            self.parser,
            html_chunk.ptr,
            html_chunk.len,
        );

        if (status != z._OK) {
            return Err.HtmlParseChunkFailed;
        }
    }

    /// Stream parsing - finish parsing and get the document
    pub fn parseChunkEnd(self: *Self) !void {
        if (!self.initialized) return Err.HtmlParserNotInitialized;

        const status = lxb_html_parse_chunk_end(self.parser);
        if (status != z._OK) {
            return Err.HtmlParseChunkFailed;
        }
    }

    /// Get cache statistics for debugging/optimization
    pub fn getCacheStats(self: *const Self) struct {
        templates: usize,
        fragments: usize,
        documents: usize,
    } {
        return .{
            .templates = self.template_cache.count(),
            .fragments = self.fragment_cache.count(),
            .documents = self.document_cache.count(),
        };
    }

    /// Clear specific cache type
    pub fn clearCache(self: *Self, cache_type: CachedContent.ContentType) void {
        switch (cache_type) {
            .template => self.cleanupCache(&self.template_cache),
            .fragment => self.cleanupCache(&self.fragment_cache),
            .document => self.cleanupCache(&self.document_cache),
        }
    }
};

/// Create a reusable HTML parser engine for high-performance operations
pub fn createHtmlParserEngine(
    allocator: std.mem.Allocator,
    config: HtmlParserEngine.Config,
) !HtmlParserEngine {
    return HtmlParserEngine.init(allocator, config);
}

// Example usage and performance tests
test "parser engine with template caching" {
    const allocator = testing.allocator;

    var parser_engine = try createHtmlParserEngine(allocator, .{
        .sanitize_on_parse = true,
        .sanitizer_options = .{
            .remove_scripts = true,
            .skip_comments = true,
        },
    });
    defer parser_engine.deinit();

    const template_html =
        \\<div class="user-card">
        \\  <h3>{{name}}</h3>
        \\  <script>alert('xss')</script>
        \\  <p>{{role}}</p>
        \\</div>
    ;

    // First parse - creates and caches template
    const template1 = try parser_engine.parseTemplate(template_html);

    // Second parse - uses cache (should be much faster)
    const template2 = try parser_engine.parseTemplate(template_html);

    // Should be the same template object (cached)
    try testing.expect(template1 == template2);

    // Verify sanitization worked
    const template_element = z.templateToElement(template1);
    const result = try z.outerHTML(allocator, template_element);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "{{name}}") != null);
    try testing.expect(std.mem.indexOf(u8, result, "script") == null);

    // Check cache stats
    const stats = parser_engine.getCacheStats();
    try testing.expect(stats.templates == 1);
}

test "security policies comparison" {
    const allocator = testing.allocator;

    const dangerous_html =
        \\<div>
        \\  <script>alert('XSS')</script>
        \\  <p onclick="steal()">Click me</p>
        \\  <style>body { display: none; }</style>
        \\  <p>Safe content</p>
        \\  <a href="javascript:void(0)">Bad link</a>
        \\</div>
    ;

    // Test 1: Strict policy (complete removal)
    {
        var strict_engine = try createHtmlParserEngine(allocator, .{
            .security_policy = .strict,
        });
        defer strict_engine.deinit();

        const doc = try strict_engine.parseDocument(dangerous_html);
        defer z.destroyDocument(doc);

        const body = try z.bodyElement(doc);
        const result = try z.innerHTML(allocator, body);
        defer allocator.free(result);

        // Should remove scripts, styles, dangerous attributes completely
        try testing.expect(std.mem.indexOf(u8, result, "script") == null);
        try testing.expect(std.mem.indexOf(u8, result, "style") == null);
        try testing.expect(std.mem.indexOf(u8, result, "onclick") == null);
        try testing.expect(std.mem.indexOf(u8, result, "javascript:") == null);
        try testing.expect(std.mem.indexOf(u8, result, "Safe content") != null);
    }

    // Test 2: Parser-controlled policy (scripts disabled but present)
    {
        var parser_engine = try createHtmlParserEngine(allocator, .{
            .security_policy = .parser_controlled,
        });
        defer parser_engine.deinit();

        const doc = try parser_engine.parseDocument(dangerous_html);
        defer z.destroyDocument(doc);

        const body = try z.bodyElement(doc);
        const result = try z.innerHTML(allocator, body);
        defer allocator.free(result);

        // Scripts should still be present (but disabled by parser)
        // Styles should be removed by sanitizer
        // Event handlers should be removed
        try testing.expect(std.mem.indexOf(u8, result, "script") != null); // Present but disabled
        try testing.expect(std.mem.indexOf(u8, result, "style") == null); // Removed by sanitizer
        try testing.expect(std.mem.indexOf(u8, result, "onclick") == null); // Removed
        try testing.expect(parser_engine.getScriptingEnabled() == false);
    }

    // Test 3: Parser-only policy (relying on parser scripting control)
    {
        var parser_only_engine = try createHtmlParserEngine(allocator, .{
            .security_policy = .parser_only,
        });
        defer parser_only_engine.deinit();

        const doc = try parser_only_engine.parseDocument(dangerous_html);
        defer z.destroyDocument(doc);

        const body = try z.bodyElement(doc);
        const result = try z.innerHTML(allocator, body);
        defer allocator.free(result);

        // Everything should be present but scripts disabled by parser
        try testing.expect(std.mem.indexOf(u8, result, "script") != null);
        try testing.expect(std.mem.indexOf(u8, result, "style") != null);
        try testing.expect(std.mem.indexOf(u8, result, "onclick") != null);
        try testing.expect(parser_only_engine.getScriptingEnabled() == false);
    }
}

test "security policy recommendations" {
    const allocator = testing.allocator;

    // For user-generated content - use strict
    var strict_engine = try createHtmlParserEngine(allocator, .{
        .security_policy = .strict,
    });
    defer strict_engine.deinit();

    // For trusted templates with variables - parser_controlled might be acceptable
    var template_engine = try createHtmlParserEngine(allocator, .{
        .security_policy = .parser_controlled,
    });
    defer template_engine.deinit();

    // For internal, fully trusted content - parser_only
    var trusted_engine = try createHtmlParserEngine(allocator, .{
        .security_policy = .parser_only,
    });
    defer trusted_engine.deinit();

    // Verify configurations
    try testing.expect(strict_engine.sanitize_on_parse == true);
    try testing.expect(template_engine.sanitize_on_parse == true);
    try testing.expect(trusted_engine.sanitize_on_parse == true);

    // All should have scripting disabled for security
    try testing.expect(!strict_engine.getScriptingEnabled());
    try testing.expect(!template_engine.getScriptingEnabled());
    try testing.expect(!trusted_engine.getScriptingEnabled());
}

test "fragment parsing by tag ID" {
    const allocator = testing.allocator;

    var parser_engine = try createHtmlParserEngine(allocator, .{
        .sanitize_on_parse = true,
    });
    defer parser_engine.deinit();

    const table_content =
        \\<tr><td>Cell 1</td><td>Cell 2</td></tr>
        \\<tr><td onclick="hack()">Cell 3</td><td>Cell 4</td></tr>
    ;

    // Parse as table body content (using tag ID for tbody context)
    const tbody_tag_id: u32 = z.LXB_TAG_TBODY; // Assuming this constant exists
    const html_ns_id: u32 = z.LXB_NS_HTML; // HTML namespace

    const fragment_root = try parser_engine.parseFragmentByTagId(
        table_content,
        tbody_tag_id,
        html_ns_id,
    );

    // Verify content was parsed and sanitized
    const children = try z.childNodes(allocator, fragment_root);
    defer allocator.free(children);

    try testing.expect(children.len == 2); // Two <tr> elements

    // Convert back to HTML to verify sanitization
    const result_html = try z.outerNode(allocator, fragment_root);
    defer allocator.free(result_html);

    try testing.expect(std.mem.indexOf(u8, result_html, "Cell 1") != null);
    try testing.expect(std.mem.indexOf(u8, result_html, "onclick") == null); // Sanitized
}
