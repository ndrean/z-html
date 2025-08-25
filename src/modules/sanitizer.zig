//! This module handles the sanitization of HTML content. It is built to ensure that the HTML is safe and clean before it is serialized.
//! It works with _whitelists_ on accepted elements and attributes.
//!
//! It provides functions to
//! - remove unwanted elements
//! - validate and sanitize attributes
//! - ensure safe URI usage
const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;
const print = z.Writer.print;

const testing = std.testing;

// Your existing simple_walk extern
extern "c" fn lxb_dom_node_simple_walk(
    root: *z.DomNode,
    walker_cb: *const fn (*z.DomNode, ?*anyopaque) callconv(.C) c_int,
    ctx: ?*anyopaque,
) void;

/// Your existing castContext helper
fn castContext(comptime T: type, ctx: ?*anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(ctx.?)));
}

// Whitelist definitions
pub const AttrSet = std.StaticStringMap(void);

pub const allowed_a = AttrSet.initComptime(.{
    .{ "href", {} },
    .{ "title", {} },
    .{ "target", {} },
    .{ "class", {} },
    .{ "id", {} },
});

pub const allowed_img = AttrSet.initComptime(.{
    .{ "src", {} },
    .{ "alt", {} },
    .{ "title", {} },
    .{ "class", {} },
    .{ "id", {} },
});

pub const allowed_common = AttrSet.initComptime(.{
    .{ "class", {} },
    .{ "id", {} },
});

pub const TagWhitelist = std.StaticStringMap(*const AttrSet);

pub const ALLOWED_TAGS = TagWhitelist.initComptime(.{
    .{ "a", &allowed_a },
    .{ "img", &allowed_img },
    .{ "div", &allowed_common },
    .{ "span", &allowed_common },
    .{ "p", &allowed_common },
    .{ "ul", &allowed_common },
    .{ "ol", &allowed_common },
    .{ "li", &allowed_common },
    .{ "strong", &allowed_common },
    .{ "em", &allowed_common },
    .{ "br", &allowed_common },
    .{ "h1", &allowed_common },
    .{ "h2", &allowed_common },
    .{ "h3", &allowed_common },
    .{ "h4", &allowed_common },
    .{ "h5", &allowed_common },
    .{ "h6", &allowed_common },
    .{ "blockquote", &allowed_common },
});

/// [sanitize] Can be improved with lexbor URL module
pub fn isSafeUri(value: []const u8) bool {
    return std.mem.startsWith(u8, value, "http://") or
        std.mem.startsWith(u8, value, "https://") or
        std.mem.startsWith(u8, value, "mailto:") or
        std.mem.startsWith(u8, value, "/") or // relative URLs
        std.mem.startsWith(u8, value, "#"); // anchors
}

pub const SanitizerOptions = struct {
    skip_comments: bool = true,
    remove_scripts: bool = true,
    remove_styles: bool = true,
    strict_uri_validation: bool = true,
};

const AttributeAction = struct {
    element: *z.HTMLElement,
    attr_name: []u8, // owned copy for deferred removal
};

// Context for sanitization - following your normalize pattern
const SanitizeContext = struct {
    allocator: std.mem.Allocator,
    options: SanitizerOptions,

    // Collections for post-walk operations
    nodes_to_remove: std.ArrayList(*z.DomNode),
    attributes_to_remove: std.ArrayList(AttributeAction),
    template_nodes: std.ArrayList(*z.DomNode),

    fn init(alloc: std.mem.Allocator, opts: SanitizerOptions) @This() {
        return .{
            .allocator = alloc,
            .options = opts,
            .nodes_to_remove = std.ArrayList(*z.DomNode).init(alloc),
            .attributes_to_remove = std.ArrayList(AttributeAction).init(alloc),
            .template_nodes = std.ArrayList(*z.DomNode).init(alloc),
        };
    }

    fn deinit(self: *@This()) void {
        // Free owned attribute names
        for (self.attributes_to_remove.items) |action| {
            self.allocator.free(action.attr_name);
        }
        self.attributes_to_remove.deinit();
        self.nodes_to_remove.deinit();
        self.template_nodes.deinit();
    }
};

/// Sanitization collector callback - follows your collectorCallBack pattern
fn sanitizeCollectorCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) c_int {
    const context_ptr: *SanitizeContext = castContext(SanitizeContext, ctx);

    switch (z.nodeType(node)) {
        .comment => {
            if (context_ptr.options.skip_comments) {
                context_ptr.nodes_to_remove.append(node) catch {
                    return z.Action.STOP.toInt();
                };
            }
        },
        .element => {
            if (z.isTemplate(node)) {
                // Handle templates separately, like in your normalize code
                context_ptr.template_nodes.append(node) catch {
                    return z.Action.STOP.toInt();
                };
                return z.Action.CONTINUE.toInt();
            }

            const element = z.nodeToElement(node) orelse return z.Action.CONTINUE.toInt();

            // Get tag name using your existing z functions
            const tag_name = z.qualifiedName_zc(element);
            const tag = z.tagFromQualifiedName(tag_name) orelse {
                // Unknown tag - remove it
                context_ptr.nodes_to_remove.append(node) catch {
                    return z.Action.STOP.toInt();
                };
                return z.Action.CONTINUE.toInt();
            };

            // Check for dangerous tags
            if (shouldRemoveTag(context_ptr.options, tag)) {
                context_ptr.nodes_to_remove.append(node) catch {
                    return z.Action.STOP.toInt();
                };
                return z.Action.CONTINUE.toInt();
            }

            // Check if tag is in whitelist
            const tag_str = @tagName(tag);
            if (ALLOWED_TAGS.get(tag_str) == null) {
                // Tag not allowed - remove
                context_ptr.nodes_to_remove.append(node) catch {
                    return z.Action.STOP.toInt();
                };
                return z.Action.CONTINUE.toInt();
            }

            // Collect dangerous attributes for removal
            collectDangerousAttributes(context_ptr, element, tag_str) catch {
                return z.Action.STOP.toInt();
            };
        },
        .text => {
            // Text nodes are generally safe - no action needed
        },
        else => {},
    }

    return z.Action.CONTINUE.toInt();
}

fn shouldRemoveTag(options: SanitizerOptions, tag: z.HtmlTag) bool {
    return switch (tag) {
        .script => options.remove_scripts,
        .style => options.remove_styles,
        .iframe, .object, .embed, .form, .input, .button, .select, .textarea => true,
        else => false,
    };
}

fn collectDangerousAttributes(
    context: *SanitizeContext,
    element: *z.HTMLElement,
    tag_name: []const u8,
) !void {
    const allowed_attrs = ALLOWED_TAGS.get(tag_name) orelse return;

    // Use your existing getAttributes function to get all attributes
    const attrs = z.getAttributes(context.allocator, element) catch return;
    defer {
        // Free the attribute pairs as per your API
        for (attrs) |attr| {
            context.allocator.free(attr.name);
            context.allocator.free(attr.value);
        }
        context.allocator.free(attrs);
    }

    for (attrs) |attr_pair| {
        var should_remove = false;

        // Check if attribute is in whitelist
        if (!allowed_attrs.has(attr_pair.name)) {
            should_remove = true;
        } else {
            // Additional validation for specific attributes
            if (std.mem.eql(u8, attr_pair.name, "href") or std.mem.eql(u8, attr_pair.name, "src")) {
                if (context.options.strict_uri_validation and !isSafeUri(attr_pair.value)) {
                    should_remove = true;
                }
            } else if (std.mem.eql(u8, attr_pair.name, "target")) {
                if (!isValidTarget(attr_pair.value)) {
                    should_remove = true;
                }
            } else if (std.mem.startsWith(u8, attr_pair.name, "on")) {
                // Remove all event handlers (onclick, onload, etc.)
                should_remove = true;
            } else if (std.mem.eql(u8, attr_pair.name, "style")) {
                // Remove inline styles (could contain javascript: URLs)
                should_remove = true;
            } else if (std.mem.startsWith(u8, attr_pair.value, "javascript:") or
                std.mem.startsWith(u8, attr_pair.value, "data:") or
                std.mem.startsWith(u8, attr_pair.value, "vbscript:"))
            {
                // Remove dangerous URI schemes in any attribute value
                should_remove = true;
            }
        }

        if (should_remove) {
            const owned_name = try context.allocator.dupe(u8, attr_pair.name);
            try context.attributes_to_remove.append(.{
                .element = element,
                .attr_name = owned_name,
            });
        }
    }
}

fn isValidTarget(value: []const u8) bool {
    return std.mem.eql(u8, value, "_blank") or
        std.mem.eql(u8, value, "_self") or
        std.mem.eql(u8, value, "_parent") or
        std.mem.eql(u8, value, "_top");
}

/// Post-walk operations - follows your PostWalkOperations pattern
fn sanitizePostWalkOperations(
    allocator: std.mem.Allocator,
    context: *SanitizeContext,
    options: SanitizerOptions,
) (std.mem.Allocator.Error || z.Err)!void {
    // Remove dangerous attributes using your removeAttribute function
    for (context.attributes_to_remove.items) |action| {
        try z.removeAttribute(action.element, action.attr_name);
    }

    // Remove dangerous nodes
    for (context.nodes_to_remove.items) |node| {
        z.removeNode(node);
        z.destroyNode(node);
    }

    // Process templates (following your template handling pattern)
    for (context.template_nodes.items) |template_node| {
        try sanitizeTemplateContent(allocator, template_node, options);
    }
}

/// Template sanitization - follows your normalizeTemplateContent pattern
fn sanitizeTemplateContent(
    allocator: std.mem.Allocator,
    template_node: *z.DomNode,
    options: SanitizerOptions,
) (std.mem.Allocator.Error || z.Err)!void {
    const template = z.nodeToTemplate(template_node) orelse return;
    const content = z.templateContent(template);
    const content_node = z.fragmentToNode(content);

    var template_context = SanitizeContext.init(allocator, options);
    defer template_context.deinit();

    lxb_dom_node_simple_walk(
        content_node,
        sanitizeCollectorCallback,
        &template_context,
    );

    try sanitizePostWalkOperations(allocator, &template_context, options);
}

/// Main sanitization function - follows your normalizeWithOptions pattern
pub fn sanitizeWithOptions(
    allocator: std.mem.Allocator,
    root_elt: *z.HTMLElement,
    options: SanitizerOptions,
) (std.mem.Allocator.Error || z.Err)!void {
    var context = SanitizeContext.init(allocator, options);
    defer context.deinit();

    lxb_dom_node_simple_walk(
        z.elementToNode(root_elt),
        sanitizeCollectorCallback,
        &context,
    );

    try sanitizePostWalkOperations(allocator, &context, options);
}

/// Default sanitization function
pub fn sanitize(
    allocator: std.mem.Allocator,
    root_elt: *z.HTMLElement,
) (std.mem.Allocator.Error || z.Err)!void {
    return sanitizeWithOptions(allocator, root_elt, .{});
}

/// Sanitize and return serialized HTML string
pub fn sanitizeToString(
    allocator: std.mem.Allocator,
    root_elt: *z.HTMLElement,
    options: SanitizerOptions,
) (std.mem.Allocator.Error || z.Err)![]u8 {
    try sanitizeWithOptions(allocator, root_elt, options);
    return z.serializeElement(allocator, root_elt);
}

test "comprehensive sanitization with your API" {
    const allocator = testing.allocator;

    const malicious_html =
        \\<div onclick="alert('xss')" style="background: url(javascript:alert('css'))">
        \\  <script>alert('xss')</script>
        \\  <p onmouseover="steal_data()" class="safe-class">Safe text</p>
        \\  <a href="javascript:alert('href')" title="Bad link">Bad link</a>
        \\  <a href="https://example.com" class="link">Good link</a>
        \\  <!-- malicious comment -->
        \\  <img src="https://example.com/image.jpg" alt="Safe image" onerror="alert('img')">
        \\  <iframe src="evil.html"></iframe>
        \\  <form><input type="text" name="evil"></form>
        \\</div>
    ;

    const doc = try z.parseFromString(malicious_html);
    defer z.destroyDocument(doc);

    const body_elt = try z.bodyElement(doc);

    try sanitizeWithOptions(allocator, body_elt, .{
        .skip_comments = true,
        .remove_scripts = true,
        .strict_uri_validation = true,
    });

    const result = try z.serializeElement(allocator, body_elt);
    defer allocator.free(result);

    print("Sanitized HTML: {s}\n", .{result});

    // Should remove dangerous elements
    try testing.expect(std.mem.indexOf(u8, result, "script") == null);
    try testing.expect(std.mem.indexOf(u8, result, "iframe") == null);
    try testing.expect(std.mem.indexOf(u8, result, "form") == null);
    try testing.expect(std.mem.indexOf(u8, result, "input") == null);

    // Should remove dangerous attributes
    try testing.expect(std.mem.indexOf(u8, result, "onclick") == null);
    try testing.expect(std.mem.indexOf(u8, result, "onmouseover") == null);
    try testing.expect(std.mem.indexOf(u8, result, "onerror") == null);
    try testing.expect(std.mem.indexOf(u8, result, "style") == null);
    try testing.expect(std.mem.indexOf(u8, result, "javascript:") == null);

    // Should remove comments
    try testing.expect(std.mem.indexOf(u8, result, "comment") == null);

    // Should preserve safe content and attributes
    try testing.expect(std.mem.indexOf(u8, result, "Safe text") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Good link") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Safe image") != null);
    try testing.expect(std.mem.indexOf(u8, result, "safe-class") != null);
    try testing.expect(std.mem.indexOf(u8, result, "class=\"link\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "https://example.com") != null);
}
