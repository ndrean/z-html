//! This module handles the sanitization of HTML content. It is built to ensure that the HTML is safe and clean before it is serialized.
//! It works with _whitelists_ on accepted elements and attributes.
//!
//! It provides functions to
//! - remove unwanted elements, comments
//! - validate and sanitize attributes
//! - ensure safe URI usage
const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;
const print = std.debug.print;

const testing = std.testing;

// Whitelist definitions
pub const AttrSet = std.StaticStringMap(void);
const special_common = AttrSet.initComptime(.{ .{"phx-"}, .{":if"}, .{":for"}, .{":let"}, .{"data-"} });

pub const allowed_a = AttrSet.initComptime(.{ .{"href"}, .{"title"}, .{"target"}, .{"id"}, .{"aria"}, .{"role"}, .{"class"}, .{"id"}, .{"aria"}, .{"hidden"} });

pub const allowed_img = AttrSet.initComptime(.{ .{"src"}, .{"alt"}, .{"title"}, .{"sizes"}, .{"height"}, .{"width"}, .{"lazy"}, .{"loading"}, .{"class"}, .{"id"}, .{"aria"}, .{"hidden"} });

pub const allowed_common = AttrSet.initComptime(.{ .{"aria"}, .{"hidden"}, .{"class"}, .{"id"}, .{"aria"}, .{"hidden"} });

pub const allowed_meta = AttrSet.initComptime(.{ .{"charset"}, .{"name"}, .{"content"} });
pub const allowed_link = AttrSet.initComptime(.{ .{"rel"}, .{"href"}, .{"type"}, .{"sizes"}, .{"media"}, .{"as"}, .{"crossorigin"}, .{"class"}, .{"id"}, .{"aria"}, .{"hidden"} });
pub const allowed_input = AttrSet.initComptime(.{ .{"type"}, .{"name"}, .{"value"}, .{"placeholder"}, .{"required"}, .{"minlength"}, .{"maxlength"}, .{"form"}, .{"autocomplete"}, .{"list"}, .{"max"}, .{"min"}, .{"readonly"}, .{"step"}, .{"accept"}, .{"class"}, .{"id"}, .{"aria"}, .{"hidden"} });
pub const allowed_label = AttrSet.initComptime(.{.{"for"}});
pub const allowed_form = AttrSet.initComptime(.{ .{"action"}, .{"method"}, .{"enctype"}, .{"target"}, .{"class"}, .{"id"}, .{"aria"}, .{"hidden"} });
pub const allowed_button = AttrSet.initComptime(.{ .{"type"}, .{"name"}, .{"value"}, .{"disabled"}, .{"class"}, .{"id"}, .{"aria"}, .{"hidden"} });

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
    .{ "button", &allowed_button },
    .{ "strong", &allowed_common },
    .{ "em", &allowed_common },
    .{ "i", &allowed_common },
});

/// [sanitize] Can be improved with lexbor URL module ??
pub fn isSafeUri(value: []const u8) bool {
    return std.mem.startsWith(u8, value, "http://") or
        std.mem.startsWith(u8, value, "https://") or
        std.mem.startsWith(u8, value, "mailto:") or
        std.mem.startsWith(u8, value, "/") or // relative URLs
        std.mem.startsWith(u8, value, "#"); // anchors
}

/// [sanitize] Check if element is a custom element (Web Components spec)
pub fn isCustomElement(tag_name: []const u8) bool {
    // Web Components spec: custom elements must contain a hyphen
    return std.mem.indexOf(u8, tag_name, "-") != null;
}

/// [sanitize] Check if attribute is a framework directive or custom attribute
pub fn isFrameworkAttribute(attr_name: []const u8) bool {
    return std.mem.startsWith(u8, attr_name, "phx-") or     // Phoenix LiveView
           std.mem.startsWith(u8, attr_name, "data-") or     // Data attributes
           std.mem.startsWith(u8, attr_name, "v-") or        // Vue.js directives
           std.mem.startsWith(u8, attr_name, "@") or         // Vue.js events, Alpine events
           std.mem.startsWith(u8, attr_name, ":") or         // Vue.js/Alpine binding
           std.mem.startsWith(u8, attr_name, "x-") or        // Alpine.js directives
           std.mem.startsWith(u8, attr_name, "*ng") or       // Angular structural directives
           std.mem.startsWith(u8, attr_name, "[") or         // Angular property binding
           std.mem.startsWith(u8, attr_name, "(") or         // Angular event binding
           std.mem.startsWith(u8, attr_name, "bind:") or     // Svelte binding
           std.mem.startsWith(u8, attr_name, "on:") or       // Svelte events
           std.mem.startsWith(u8, attr_name, "use:") or      // Svelte actions
           std.mem.startsWith(u8, attr_name, ".") or         // Lit property binding
           std.mem.startsWith(u8, attr_name, "?") or         // Lit boolean attributes
           std.mem.startsWith(u8, attr_name, "aria-") or     // Accessibility
           std.mem.startsWith(u8, attr_name, "slot");        // Web Components slots
}

pub const SanitizerOptions = struct {
    skip_comments: bool = true,
    remove_scripts: bool = true,
    remove_styles: bool = true,
    strict_uri_validation: bool = true,
    allow_custom_elements: bool = false,  // Enable permissive custom element handling
};

const AttributeAction = struct {
    element: *z.HTMLElement,
    attr_name: []u8, // owned copy for deferred removal
    needs_free: bool,
};

/// Stack memory configuration
const STACK_ATTR_BUFFER_SIZE = 2048; // 2KB for attribute name storage
const MAX_STACK_REMOVALS = 32; // Stack space for removal operations
const MAX_STACK_TEMPLATES = 8; // Most documents have few templates

// Context for sanitization - following your normalize pattern
const SanitizeContext = struct {
    allocator: std.mem.Allocator,
    options: SanitizerOptions,

    // Stack attribute name storage
    attr_name_buffer: [STACK_ATTR_BUFFER_SIZE]u8,
    attr_name_fba: std.heap.FixedBufferAllocator,

    // Stack arrays (same names as before)
    nodes_to_remove: [MAX_STACK_REMOVALS]*z.DomNode,
    attributes_to_remove: [MAX_STACK_REMOVALS]AttributeAction,
    template_nodes: [MAX_STACK_TEMPLATES]*z.DomNode,

    // Counters
    nodes_count: usize,
    attrs_count: usize,
    templates_count: usize,

    // Correct init signature - returns new instance
    fn init(alloc: std.mem.Allocator, opts: SanitizerOptions) @This() {
        var self = @This(){
            .allocator = alloc,
            .options = opts,
            .attr_name_buffer = undefined,
            .attr_name_fba = undefined,
            .nodes_to_remove = undefined,
            .attributes_to_remove = undefined,
            .template_nodes = undefined,
            .nodes_count = 0,
            .attrs_count = 0,
            .templates_count = 0,
        };
        self.attr_name_fba = std.heap.FixedBufferAllocator.init(&self.attr_name_buffer);
        return self;
    }

    fn deinit(self: *@This()) void {
        // Stack-only cleanup - only free heap fallback attribute names
        for (self.attributes_to_remove[0..self.attrs_count]) |action| {
            if (action.needs_free) {
                self.allocator.free(action.attr_name);
            }
        }
    }

    fn addNodeToRemove(self: *@This(), node: *z.DomNode) !void {
        if (self.nodes_count >= MAX_STACK_REMOVALS) {
            return error.TooManyNodesToRemove;
        }
        self.nodes_to_remove[self.nodes_count] = node;
        self.nodes_count += 1;
    }

    fn addAttributeToRemove(self: *@This(), element: *z.HTMLElement, attr_name: []const u8) !void {
        if (self.attrs_count >= MAX_STACK_REMOVALS) {
            return error.TooManyAttributesToRemove;
        }

        const owned_name = try self.allocator.dupe(u8, attr_name);

        self.attributes_to_remove[self.attrs_count] = AttributeAction{
            .element = element,
            .attr_name = owned_name,
            .needs_free = true,
        };
        self.attrs_count += 1;
    }

    fn addTemplate(self: *@This(), template_node: *z.DomNode) !void {
        if (self.templates_count >= MAX_STACK_TEMPLATES) {
            return error.TooManyTemplates;
        }
        self.template_nodes[self.templates_count] = template_node;
        self.templates_count += 1;
    }
};

/// Sanitization collector callback - follows your collectorCallBack pattern
fn sanitizeCollectorCB(node: *z.DomNode, ctx: ?*anyopaque) callconv(.c) c_int {
    const context_ptr: *SanitizeContext = z.castContext(SanitizeContext, ctx);

    switch (z.nodeType(node)) {
        .comment => {
            if (context_ptr.options.skip_comments) {
                context_ptr.addNodeToRemove(node) catch {
                    return z._STOP;
                };
            }
        },
        .element => {
            if (z.isTemplate(node)) {
                context_ptr.addTemplate(node) catch {
                    return z._STOP;
                };
                return z._CONTINUE;
            }

            const element = z.nodeToElement(node) orelse return z._CONTINUE;

            // Try to get lexbor's tag enum first
            const maybe_tag = z.tagFromElement(element);
            
            if (maybe_tag) |tag| {
                // Known HTML tag
                if (shouldRemoveTag(context_ptr.options, tag)) {
                    context_ptr.addNodeToRemove(node) catch {
                        return z._STOP;
                    };
                    return z._CONTINUE;
                }

                const tag_str = @tagName(tag);
                
                // Check if it's a standard HTML tag first
                if (ALLOWED_TAGS.get(tag_str)) |_| {
                    // Standard HTML element - use strict whitelist
                    collectDangerousAttributes(context_ptr, element, tag_str) catch {
                        return z._STOP;
                    };
                } else {
                    // Known tag but not in our whitelist - remove
                    context_ptr.addNodeToRemove(node) catch {
                        return z._STOP;
                    };
                    return z._CONTINUE;
                }
            } else {
                // Unknown tag - check if it's a custom element
                const tag_name = z.qualifiedName_zc(element);
                
                if (context_ptr.options.allow_custom_elements and isCustomElement(tag_name)) {
                    // Custom element - use permissive sanitization
                    collectCustomElementAttributes(context_ptr, element) catch |err| {
                        print("Error in collectCustomElementAttributes: {}\n", .{err});
                        return z._STOP;
                    };
                } else {
                    // Unknown element and custom elements not allowed - remove
                    context_ptr.addNodeToRemove(node) catch {
                        return z._STOP;
                    };
                    return z._CONTINUE;
                }
            }
            
            return z._CONTINUE;
        },

        else => {},
    }

    return z._CONTINUE;
}

inline fn shouldRemoveTag(options: SanitizerOptions, tag: z.HtmlTag) bool {
    return switch (tag) {
        .script => options.remove_scripts,
        .style => options.remove_styles,
        .iframe,
        .object,
        .embed,
        => true,
        else => false,
        // .form, .input, .button, .select, .textarea
    };
}

/// Permissive sanitization for custom elements - only remove truly dangerous attributes
fn collectCustomElementAttributes(context: *SanitizeContext, element: *z.HTMLElement) !void {
    const attrs = z.getAttributes_bf(context.allocator, element) catch return;
    defer {
        for (attrs) |attr| {
            context.allocator.free(attr.name);
            context.allocator.free(attr.value);
        }
        context.allocator.free(attrs);
    }

    for (attrs) |attr_pair| {
        var should_remove = false;

        // Allow framework attributes and data attributes
        if (isFrameworkAttribute(attr_pair.name)) {
            continue;
        }

        // Only remove truly dangerous attributes for custom elements
        if (std.mem.startsWith(u8, attr_pair.value, "javascript:") or
            std.mem.startsWith(u8, attr_pair.value, "vbscript:"))
        {
            should_remove = true;
        } else if (std.mem.startsWith(u8, attr_pair.value, "data:") and
            (std.mem.indexOf(u8, attr_pair.value, "base64") != null or
                std.mem.startsWith(u8, attr_pair.value, "data:text/html") or
                std.mem.startsWith(u8, attr_pair.value, "data:text/javascript")))
        {
            should_remove = true;
        } else if (std.mem.startsWith(u8, attr_pair.name, "on") and
                   !isFrameworkAttribute(attr_pair.name))  // Allow @click, on:click, etc.
        {
            // Remove traditional event handlers but allow framework events
            should_remove = true;
        } else if (std.mem.eql(u8, attr_pair.name, "style") and context.options.remove_styles) {
            // Remove inline styles only if configured
            should_remove = true;
        } else if ((std.mem.eql(u8, attr_pair.name, "href") or std.mem.eql(u8, attr_pair.name, "src")) and
                   context.options.strict_uri_validation and !isSafeUri(attr_pair.value)) {
            should_remove = true;
        }

        if (should_remove) {
            try context.addAttributeToRemove(element, attr_pair.name);
        }
    }
}

/// Strict sanitization for standard HTML elements - uses whitelist
fn collectDangerousAttributes(context: *SanitizeContext, element: *z.HTMLElement, tag_name: []const u8) !void {
    const allowed_attrs = ALLOWED_TAGS.get(tag_name) orelse return;
    // uses buffer collected attributes
    const attrs = z.getAttributes_bf(context.allocator, element) catch return;

    defer {
        for (attrs) |attr| {
            context.allocator.free(attr.name);
            context.allocator.free(attr.value);
        }
        context.allocator.free(attrs);
    }

    for (attrs) |attr_pair| {
        var should_remove = false;

        if (isFrameworkAttribute(attr_pair.name)) {
            // Always allow framework-specific attributes
            continue;
        } else if (!allowed_attrs.has(attr_pair.name)) {
            should_remove = true;
        } else {
            // Check for dangerous schemes in ANY attribute value first
            if (std.mem.startsWith(u8, attr_pair.value, "javascript:") or
                std.mem.startsWith(u8, attr_pair.value, "vbscript:"))
            {
                should_remove = true;
            } else if (std.mem.startsWith(u8, attr_pair.value, "data:") and
                (std.mem.indexOf(u8, attr_pair.value, "base64") != null or
                    std.mem.startsWith(u8, attr_pair.value, "data:text/html") or
                    std.mem.startsWith(u8, attr_pair.value, "data:text/javascript")))
            {
                should_remove = true;
            } else if (std.mem.startsWith(u8, attr_pair.name, "on")) {
                // Remove all event handlers
                should_remove = true;
            } else if (std.mem.eql(u8, attr_pair.name, "style")) {
                // Remove inline styles
                should_remove = true;
            } else if (std.mem.eql(u8, attr_pair.name, "href") or std.mem.eql(u8, attr_pair.name, "src")) {
                if (context.options.strict_uri_validation and !isSafeUri(attr_pair.value)) {
                    should_remove = true;
                }
            } else if (std.mem.eql(u8, attr_pair.name, "target")) {
                if (!isValidTarget(attr_pair.value)) {
                    should_remove = true;
                }
            }
        }
        if (should_remove) {
            try context.addAttributeToRemove(element, attr_pair.name);
        }
    }
}

fn isValidTarget(value: []const u8) bool {
    return std.mem.eql(u8, value, "_blank") or
        std.mem.eql(u8, value, "_self") or
        std.mem.eql(u8, value, "_parent") or
        std.mem.eql(u8, value, "_top");
}

fn sanitizePostWalkOperations(allocator: std.mem.Allocator, context: *SanitizeContext, options: SanitizerOptions) (std.mem.Allocator.Error || z.Err)!void {
    for (context.attributes_to_remove[0..context.attrs_count]) |action| {
        try z.removeAttribute(action.element, action.attr_name);
    }

    for (context.nodes_to_remove[0..context.nodes_count]) |node| {
        z.removeNode(node);
        z.destroyNode(node);
    }

    for (context.template_nodes[0..context.templates_count]) |template_node| {
        try sanitizeTemplateContent(
            allocator,
            template_node,
            options,
        );
    }
}

fn sanitizeTemplateContent(allocator: std.mem.Allocator, template_node: *z.DomNode, options: SanitizerOptions) (std.mem.Allocator.Error || z.Err)!void {
    const template = z.nodeToTemplate(template_node) orelse return;
    const content = z.templateContent(template);
    const content_node = z.fragmentToNode(content);

    var template_context = SanitizeContext.init(allocator, options);
    defer template_context.deinit();

    z.simpleWalk(
        content_node,
        sanitizeCollectorCB,
        &template_context,
    );

    try sanitizePostWalkOperations(allocator, &template_context, options);
}

pub fn sanitizeWithOptions(allocator: std.mem.Allocator, root_node: *z.DomNode, options: SanitizerOptions) (std.mem.Allocator.Error || z.Err)!void {
    var context = SanitizeContext.init(allocator, options);
    defer context.deinit();

    z.simpleWalk(
        root_node,
        sanitizeCollectorCB,
        &context,
    );

    try sanitizePostWalkOperations(
        allocator,
        &context,
        options,
    );
}

pub fn sanitizeNode(allocator: std.mem.Allocator, root_node: *z.DomNode) (std.mem.Allocator.Error || z.Err)!void {
    return sanitizeWithOptions(allocator, root_node, .{});
}

test "simple custom element sanitization" {
    const allocator = testing.allocator;

    const simple_html = "<div><my-button>Click me</my-button></div>";

    const doc = try z.createDocFromString(simple_html);
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;

    // Test with custom elements ENABLED
    try sanitizeWithOptions(allocator, body, .{
        .allow_custom_elements = true,
        .remove_scripts = false,
        .remove_styles = false,
        .strict_uri_validation = false,
    });

    const result = try z.outerNodeHTML(allocator, body);
    defer allocator.free(result);

    print("Simple test result: {s}\n", .{result});

    // Custom element should be preserved
    try testing.expect(std.mem.indexOf(u8, result, "<my-button") != null);
}

test "custom element sanitization" {
    const allocator = testing.allocator;

    const custom_elements_html =
        \\<div>
        \\  <my-button @click="handleClick" :disabled="isDisabled" class="btn">Custom Button</my-button>
        \\  <user-profile data-user-id="123" v-if="showProfile" phx-click="select_user">
        \\    <user-avatar slot="avatar" .src="avatarUrl"></user-avatar>
        \\  </user-profile>
        \\  <lit-element ?hidden="true" .property="value" onclick="alert('bad')">Lit Component</lit-element>
        \\  <angular-component [ngclass]="classes" (click)="handler" *ngif="condition">Angular</angular-component>
        \\  <svelte-component bind:value use:action on:custom="handleCustom">Svelte</svelte-component>
        \\  <script>alert('evil')</script>
        \\  <unknown-element>Should be removed</unknown-element>
        \\</div>
    ;

    const doc = try z.createDocFromString(custom_elements_html);
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;

    // Test with custom elements ENABLED
    try sanitizeWithOptions(allocator, body, .{
        .allow_custom_elements = true,
        .remove_scripts = true,
        .strict_uri_validation = true,
    });

    const result = try z.outerNodeHTML(allocator, body);
    defer allocator.free(result);

    print("Custom elements result: {s}\n", .{result});

    // Custom elements should be preserved
    try testing.expect(std.mem.indexOf(u8, result, "<my-button") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<user-profile") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<lit-element") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<angular-component") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<svelte-component") != null);

    // Framework attributes should be preserved
    try testing.expect(std.mem.indexOf(u8, result, "@click") != null);
    try testing.expect(std.mem.indexOf(u8, result, ":disabled") != null);
    try testing.expect(std.mem.indexOf(u8, result, "v-if") != null);
    try testing.expect(std.mem.indexOf(u8, result, "phx-click") != null);
    try testing.expect(std.mem.indexOf(u8, result, ".property") != null);
    try testing.expect(std.mem.indexOf(u8, result, "?hidden") != null);
    try testing.expect(std.mem.indexOf(u8, result, "[ngclass]") != null);
    try testing.expect(std.mem.indexOf(u8, result, "(click)") != null);
    try testing.expect(std.mem.indexOf(u8, result, "bind:value") != null);
    try testing.expect(std.mem.indexOf(u8, result, "on:custom") != null);

    // Dangerous attributes should be removed
    try testing.expect(std.mem.indexOf(u8, result, "onclick") == null);

    // Scripts should be removed
    try testing.expect(std.mem.indexOf(u8, result, "script") == null);
    
    // NOTE: unknown-element has hyphen so it's treated as custom element too
    // This is by Web Components spec - any element with hyphen is potentially custom
}

test "comprehensive sanitization" {
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

    const doc = try z.createDocFromString(malicious_html);
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;

    try sanitizeWithOptions(allocator, body, .{
        .skip_comments = true,
        .remove_scripts = true,
        .strict_uri_validation = true,
    });

    const result = try z.outerNodeHTML(allocator, body);
    defer allocator.free(result);

    // print("Sanitized HTML: {s}\n", .{result});

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
