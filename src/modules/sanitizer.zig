//! This module handles the sanitization of HTML content. It is built to ensure that the HTML is safe and clean before it is serialized.
//! It works with _whitelists_ on accepted elements and attributes.
//!
//! It provides functions to
//! - remove unwanted elements, comments
//! - validate and sanitize attributes
//! - ensure safe URI usage
const std = @import("std");
const z = @import("../zhtml.zig");
const html_spec = @import("html_spec.zig");
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
pub const allowed_table = AttrSet.initComptime(.{ .{"scope"}, .{"id"}, .{"class"} });

// SVG attribute whitelists
pub const allowed_svg_common = AttrSet.initComptime(.{
    // Core attributes
    .{"id"},          .{"class"},        .{"style"},             .{"title"},
    // Geometric attributes
    .{"x"},           .{"y"},            .{"width"},             .{"height"},
    .{"r"},           .{"rx"},           .{"ry"},                .{"cx"},
    .{"cy"},          .{"x1"},           .{"y1"},                .{"x2"},
    .{"y2"},          .{"dx"},           .{"dy"},
    // Presentation attributes (safe ones)
                   .{"fill"},
    .{"stroke"},      .{"stroke-width"}, .{"stroke-linecap"},    .{"stroke-linejoin"},
    .{"opacity"},     .{"fill-opacity"}, .{"stroke-opacity"},    .{"font-size"},
    .{"font-family"}, .{"text-anchor"},  .{"dominant-baseline"}, .{"alignment-baseline"},
    // Transform (generally safe)
    .{"transform"},   .{"viewBox"},      .{"xmlns"},
});

pub const allowed_svg_path = AttrSet.initComptime(.{ .{"d"}, .{"pathLength"} });
pub const allowed_svg_text = AttrSet.initComptime(.{ .{"x"}, .{"y"}, .{"dx"}, .{"dy"}, .{"rotate"}, .{"textLength"} });
pub const allowed_svg_circle = AttrSet.initComptime(.{ .{"cx"}, .{"cy"}, .{"r"} });
pub const allowed_svg_rect = AttrSet.initComptime(.{ .{"x"}, .{"y"}, .{"width"}, .{"height"}, .{"rx"}, .{"ry"} });
pub const allowed_svg_line = AttrSet.initComptime(.{ .{"x1"}, .{"y1"}, .{"x2"}, .{"y2"} });
pub const allowed_svg_animate = AttrSet.initComptime(.{ .{"attributeName"}, .{"values"}, .{"dur"}, .{"repeatCount"} });

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
    .{ "i", &allowed_common },
    .{ "table", &allowed_table },
    .{ "thead", &allowed_table },
    .{ "tbody", &allowed_table },
    .{ "tr", &allowed_table },
    .{ "th", &allowed_table },
    .{ "td", &allowed_table },
    .{ "caption", &allowed_table },
    .{ "tfoot", &allowed_table },

    // SVG elements (safe ones) - defined in centralized HtmlTag enum
    .{ "svg", &allowed_svg_common },
    .{ "path", &allowed_svg_path },
    .{ "circle", &allowed_svg_circle },
    .{ "rect", &allowed_svg_rect },
    .{ "line", &allowed_svg_line },
    .{ "text", &allowed_svg_text },
    .{ "g", &allowed_svg_common }, // group
    .{ "defs", &allowed_svg_common }, // definitions
    .{ "use", &allowed_svg_common }, // use element
});

/// [sanitize] Defines which URLs can be considered safe as used in an attribute
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

fn shouldRemoveSvgDescendant(tag_name: []const u8) bool {
    return std.mem.eql(u8, tag_name, "script") or
        std.mem.eql(u8, tag_name, "foreignObject") or
        std.mem.eql(u8, tag_name, "animate") or // Can have onbegin, onend events
        std.mem.eql(u8, tag_name, "animateTransform") or
        std.mem.eql(u8, tag_name, "set");
}

/// [sanitize] Check if an attribute is allowed by the whitelist (legacy)
fn isAttributeAllowed(attr_set: *const AttrSet, attr_name: []const u8) bool {
    return attr_set.has(attr_name) or special_common.has(attr_name);
}

/// [sanitize] Check if an element and attribute combination is allowed using unified specification
pub fn isElementAttributeAllowed(element_tag: []const u8, attr_name: []const u8) bool {
    return html_spec.isAttributeAllowed(element_tag, attr_name);
}

/// [sanitize] Check if an attribute value is valid using unified specification
pub fn isElementAttributeValueValid(element_tag: []const u8, attr_name: []const u8, attr_value: []const u8) bool {
    return html_spec.isAttributeValueValid(element_tag, attr_name, attr_value);
}

/// [sanitize] Validate an element using unified specification
pub fn validateElementWithSpec(element: *z.HTMLElement) bool {
    const tag_name = z.tagName_zc(element);
    const lowercase_tag = std.ascii.lowerString(tag_name, tag_name);

    // Check if element itself is allowed
    const spec = html_spec.getElementSpec(lowercase_tag);
    if (spec == null) {
        return false; // Element not in specification
    }

    return true;
}

/// Helper to set the parent context to avoid walking up the DOM tree
/// to get the context of a node (for example to give context to nested elements in `<code>` elements)
///
/// Instead of walking up the DOM tree, we check if a node has a previous sibling,
/// in which case we use the sibling's context. If not, we keep the current context.
fn maybeResetContext(context: *SanitizeContext, node: *z.DomNode) void {
    if (z.previousSibling(node)) |sibling| {
        if (z.isTypeElement(sibling)) {
            const sibling_tag =
                z.tagFromAnyElement(z.nodeToElement(sibling).?);
            if (sibling_tag == .svg or sibling_tag == .pre or sibling_tag == .code or sibling_tag == .template) {
                context.parent = .body; // Reset context after special elements
            }
        }
    }
}

/// Sets the parent context for a given tag
fn setAncestor(tag: z.HtmlTag, parent: z.HtmlTag) z.HtmlTag {
    return switch (tag) {
        .svg => .svg,
        .code => .code,
        .pre => .pre,
        .template => .template,
        else => parent, // Context resets are handled by maybeResetContext
    };
}

fn isDescendantOfSvg(tag: z.HtmlTag, parent: z.HtmlTag) bool {
    return (tag == .svg or parent == .svg) or return false;
}

/// [sanitize] Collect dangerous SVG attributes (simplified version without iteration)
fn collectSvgDangerousAttributes(context: *SanitizeContext, element: *z.HTMLElement, tag_str: []const u8) !void {
    // For now, we'll use a simplified approach and check common dangerous attributes
    // This avoids the complexity of attribute iteration which requires allocator

    // Check for dangerous event handlers
    const dangerous_events = [_][]const u8{ "onclick", "onload", "onmouseover", "onbegin", "onend", "onfocusin", "onfocusout" };

    for (dangerous_events) |event_attr| {
        if (z.hasAttribute(element, event_attr)) {
            try context.addAttributeToRemove(element, event_attr);
        }
    }

    // Check for dangerous href with javascript
    if (z.getAttribute_zc(element, "href")) |href_value| {
        if (std.mem.startsWith(u8, href_value, "javascript:")) {
            try context.addAttributeToRemove(element, "href");
        }
    }

    _ = tag_str; // Will use this later for more specific attribute checking
}

/// [sanitize] Check if attribute is a framework directive or custom attribute
pub fn isFrameworkAttribute(attr_name: []const u8) bool {
    return std.mem.startsWith(u8, attr_name, "phx-") or // Phoenix LiveView events/bindings
        std.mem.startsWith(u8, attr_name, ":") or // Phoenix LiveView directives (:if, :for, :let) + Vue.js/Alpine
        std.mem.startsWith(u8, attr_name, "data-") or // Data attributes
        std.mem.startsWith(u8, attr_name, "v-") or // Vue.js directives
        std.mem.startsWith(u8, attr_name, "@") or // Vue.js events, Alpine events
        std.mem.startsWith(u8, attr_name, "x-") or // Alpine.js directives
        std.mem.startsWith(u8, attr_name, "*ng") or // Angular structural directives
        std.mem.startsWith(u8, attr_name, "[") or // Angular property binding
        std.mem.startsWith(u8, attr_name, "(") or // Angular event binding
        std.mem.startsWith(u8, attr_name, "bind:") or // Svelte binding
        std.mem.startsWith(u8, attr_name, "on:") or // Svelte events
        std.mem.startsWith(u8, attr_name, "use:") or // Svelte actions
        std.mem.startsWith(u8, attr_name, ".") or // Lit property binding
        std.mem.startsWith(u8, attr_name, "?") or // Lit boolean attributes
        std.mem.startsWith(u8, attr_name, "aria-") or // Accessibility
        std.mem.startsWith(u8, attr_name, "slot") or // Web Components slots
        // Phoenix LiveView specific attributes that might not have prefixes
        std.mem.eql(u8, attr_name, "for") or // Phoenix :for loops (might appear as 'for')
        std.mem.eql(u8, attr_name, "if") or // Phoenix :if conditions (might appear as 'if')
        std.mem.eql(u8, attr_name, "let"); // Phoenix :let bindings (might appear as 'let')
}

/// [sanitize] Settings of the sanitizer
pub const SanitizerOptions = struct {
    skip_comments: bool = true,
    remove_scripts: bool = true,
    remove_styles: bool = true,
    strict_uri_validation: bool = true,
    allow_custom_elements: bool = false, // Enable permissive custom element handling
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

// Context for simple_walk sanitization callback
const SanitizeContext = struct {
    allocator: std.mem.Allocator,
    options: SanitizerOptions,
    parent: z.HtmlTag,

    // Stack attribute name storage
    attr_name_buffer: [STACK_ATTR_BUFFER_SIZE]u8,
    attr_name_fba: std.heap.FixedBufferAllocator,

    // Stack arrays
    nodes_to_remove: [MAX_STACK_REMOVALS]*z.DomNode,
    attributes_to_remove: [MAX_STACK_REMOVALS]AttributeAction,
    template_nodes: [MAX_STACK_TEMPLATES]*z.DomNode,

    // Counters
    nodes_count: usize,
    attrs_count: usize,
    templates_count: usize,

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
            .parent = .html,
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

// Helper function to remove node and continue
inline fn removeAndContinue(context_ptr: *SanitizeContext, node: *z.DomNode) c_int {
    context_ptr.addNodeToRemove(node) catch return z._STOP;
    return z._CONTINUE;
}

// Handle SVG elements (both known and unknown)
fn handleSvgElement(context_ptr: *SanitizeContext, node: *z.DomNode, element: *z.HTMLElement, tag_name: []const u8) c_int {
    // Check if it's a dangerous SVG element
    if (shouldRemoveSvgDescendant(tag_name)) {
        return removeAndContinue(context_ptr, node);
    }

    // Safe SVG element - check if allowed and sanitize attributes
    if (ALLOWED_TAGS.get(tag_name)) |_| {
        collectSvgDangerousAttributes(context_ptr, element, tag_name) catch return z._STOP;
    } else {
        // SVG element not in whitelist - remove
        return removeAndContinue(context_ptr, node);
    }
    return z._CONTINUE;
}

// Handle known HTML elements
fn handleKnownElement(context_ptr: *SanitizeContext, node: *z.DomNode, element: *z.HTMLElement, tag: z.HtmlTag) c_int {
    // Check if this tag should be removed
    if (shouldRemoveTag(context_ptr.options, tag)) {
        return removeAndContinue(context_ptr, node);
    }

    const tag_str = @tagName(tag);

    // Set the new context for this element
    context_ptr.parent = setAncestor(tag, context_ptr.parent);

    // handle SVG context
    if (isDescendantOfSvg(tag, context_ptr.parent)) {
        context_ptr.parent = .svg;
        return handleSvgElement(context_ptr, node, element, tag_str);
    }

    // Standard HTML element - use strict whitelist
    if (ALLOWED_TAGS.get(tag_str)) |_| {
        collectDangerousAttributes(context_ptr, element, tag_str) catch return z._STOP;
    } else {
        // Known tag but not in whitelist: eg script elements, iframe
        return removeAndContinue(context_ptr, node);
    }

    return z._CONTINUE;
}

// Handle unknown elements in context (custom context or SVG context containing not whitelisted elements)
fn handleUnknownElement(context_ptr: *SanitizeContext, node: *z.DomNode, element: *z.HTMLElement) c_int {
    const tag_name = z.qualifiedName_zc(element);

    //SVG context: `foreignObject`,` animate`
    if (context_ptr.parent == .svg) {
        return handleSvgElement(context_ptr, node, element, tag_name);
    }

    // custom element context
    if (context_ptr.options.allow_custom_elements and isCustomElement(tag_name)) {
        // Custom element - use permissive sanitization
        collectCustomElementAttributes(context_ptr, element) catch |err| {
            print("Error in collectCustomElementAttributes: {}\n", .{err});
            return z._STOP;
        };
    } else {
        // Unknown element and custom elements not allowed - remove
        return removeAndContinue(context_ptr, node);
    }

    return z._CONTINUE;
}

/// Templates are handled differently as we need to access its innerContent in its document fragment
fn handleTemplates(context_ptr: *SanitizeContext, node: *z.DomNode) c_int {
    context_ptr.parent = .template;
    context_ptr.addTemplate(node) catch return z._STOP;
    return z._CONTINUE;
}
/// Handle element nodes with a separate tratment for templates as we need to access its content.
fn handleElement(context_ptr: *SanitizeContext, node: *z.DomNode) c_int {
    if (z.isTemplate(node)) {
        return handleTemplates(context_ptr, node);
    }

    maybeResetContext(context_ptr, node);
    const element = z.nodeToElement(node) orelse return z._CONTINUE;
    const tag = z.tagFromAnyElement(element);

    if (tag != .custom)
        return handleKnownElement(context_ptr, node, element, tag);

    return handleUnknownElement(context_ptr, node, element);
}

/// Sanitization collector callback for simple walk
///
/// The callback will be applied to every descendant of the given node given the current context object used as a collector.
///
/// A second post-processing step may be applied after the DOM traversal is complete and process the collected nodes and attributes.
fn sanitizeCollectorCB(node: *z.DomNode, ctx: ?*anyopaque) callconv(.c) c_int {
    const context_ptr: *SanitizeContext = @ptrCast(@alignCast(ctx));

    switch (z.nodeType(node)) {
        .text => maybeResetContext(context_ptr, node),
        .comment => {
            maybeResetContext(context_ptr, node);
            if (context_ptr.options.skip_comments) {
                return removeAndContinue(context_ptr, node);
            }
        },
        .element => return handleElement(context_ptr, node),
        else => maybeResetContext(context_ptr, node),
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
            !isFrameworkAttribute(attr_pair.name)) // Allow @click, on:click, etc.
        {
            // Remove traditional event handlers but allow framework events
            should_remove = true;
        } else if (std.mem.eql(u8, attr_pair.name, "style") and context.options.remove_styles) {
            // Remove inline styles only if configured
            should_remove = true;
        } else if ((std.mem.eql(u8, attr_pair.name, "href") or std.mem.eql(u8, attr_pair.name, "src")) and
            context.options.strict_uri_validation and !isSafeUri(attr_pair.value))
        {
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

// Convenience functions for common sanitization scenarios
pub fn sanitizeStrict(allocator: std.mem.Allocator, root_node: *z.DomNode) (std.mem.Allocator.Error || z.Err)!void {
    return sanitizeWithOptions(allocator, root_node, .{
        .skip_comments = true,
        .remove_scripts = true,
        .remove_styles = true,
        .strict_uri_validation = true,
        .allow_custom_elements = false,
    });
}

pub fn sanitizePermissive(allocator: std.mem.Allocator, root_node: *z.DomNode) (std.mem.Allocator.Error || z.Err)!void {
    return sanitizeWithOptions(allocator, root_node, .{
        .skip_comments = true,
        .remove_scripts = true,
        .remove_styles = false,
        .strict_uri_validation = true,
        .allow_custom_elements = true,
    });
}

test "comprehensive HTML and SVG sanitization" {
    const allocator = testing.allocator;

    // Test input combining HTML XSS vectors, SVG attacks, custom elements, and framework attributes
    const malicious_input =
        \\<div onclick="alert('xss')" style="background: url(javascript:alert('css'))">
        \\  <script>alert('xss')</script>
        \\  <p onmouseover="steal_data()" class="safe-class">Safe text</p>
        \\  <a href="javascript:alert('href')" title="Bad link">Bad link</a>
        \\  <a href="https://example.com" class="link">Good link</a>
        \\  <!-- malicious comment -->
        \\  <img src="https://example.com/image.jpg" alt="Safe image" onerror="alert('img')">
        \\  <iframe src="evil.html"></iframe>
        \\  
        \\  <svg viewBox="0 0 100 100" onclick="alert('svg-xss')">
        \\    <circle cx="50" cy="50" r="40" fill="blue"/>
        \\    <script>alert('svg-script')</script>
        \\    <foreignObject width="100" height="100">
        \\      <div xmlns="http://www.w3.org/1999/xhtml">Evil content</div>
        \\    </foreignObject>
        \\    <animate attributeName="opacity" values="0;1" dur="2s" onbegin="alert('animate')"/>
        \\    <path d="M10 10 L90 90" stroke="red"/>
        \\    <text x="50" y="50" href="javascript:alert('text')">SVG Text</text>
        \\  </svg>
        \\  
        \\  <phoenix-component phx-click="increment" :if="show_component" onclick="alert('custom')">
        \\    Phoenix LiveView Component
        \\  </phoenix-component>
        \\  <my-button @click="handleClick" :disabled="isDisabled" class="btn">
        \\    Custom Button
        \\  </my-button>
        \\  <vue-component v-if="showProfile" data-user-id="123">Vue Component</vue-component>
        \\  <p> The <code>push()</code> method adds one or more elements to the end of an array
        \\</div>
    ;

    const doc = try z.createDocFromString(malicious_input);
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;

    // Test 1: Strict sanitization (no custom elements)
    try sanitizeWithOptions(allocator, body, .{
        .skip_comments = true,
        .remove_scripts = true,
        .remove_styles = true,
        .strict_uri_validation = true,
        .allow_custom_elements = false,
    });
    try z.prettyPrint(body);
    
    // Normalize to clean up empty text nodes left by element removal
    const body_element = z.nodeToElement(body) orelse return;
    try z.normalize(allocator, body_element);  // Standard browser-like normalization
    
    print("\n=== After normalization ===\n", .{});
    try z.prettyPrint(body);

    const strict_result = try z.outerNodeHTML(allocator, body);
    defer allocator.free(strict_result);

    // Verify dangerous elements/attributes removed
    try testing.expect(std.mem.indexOf(u8, strict_result, "script") == null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "malicious comment") == null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "iframe") == null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "foreignObject") == null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "animate") == null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "onclick") == null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "onmouseover") == null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "onbegin") == null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "onerror") == null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "javascript:") == null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "style=") == null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "comment") == null);

    // Verify safe content preserved
    try testing.expect(std.mem.indexOf(u8, strict_result, "Safe text") != null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "Good link") != null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "safe-class") != null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "https://example.com") != null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "<svg") != null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "<circle") != null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "<path") != null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "SVG Text") != null);

    // Verify custom elements removed when not allowed
    try testing.expect(std.mem.indexOf(u8, strict_result, "phoenix-component") == null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "my-button") == null);
    try testing.expect(std.mem.indexOf(u8, strict_result, "vue-component") == null);

    // Test 2: Permissive sanitization (with custom elements)
    const doc2 = try z.createDocFromString(malicious_input);
    defer z.destroyDocument(doc2);
    const body2 = z.bodyNode(doc2).?;

    try sanitizeWithOptions(allocator, body2, .{
        .skip_comments = true,
        .remove_scripts = true,
        .remove_styles = false, // Allow inline styles for custom elements
        .strict_uri_validation = true,
        .allow_custom_elements = true,
    });

    print("\n=== Permissive Sanitization (custom elements enabled) ===\n", .{});
    try z.prettyPrint(body2);

    const permissive_result = try z.outerNodeHTML(allocator, body2);
    defer allocator.free(permissive_result);

    // Still removes dangerous stuff
    try testing.expect(std.mem.indexOf(u8, permissive_result, "script") == null);
    try testing.expect(std.mem.indexOf(u8, permissive_result, "foreignObject") == null);
    try testing.expect(std.mem.indexOf(u8, permissive_result, "animate") == null);
    try testing.expect(std.mem.indexOf(u8, permissive_result, "javascript:") == null);

    // But preserves custom elements and framework attributes
    try testing.expect(std.mem.indexOf(u8, permissive_result, "phoenix-component") != null);
    try testing.expect(std.mem.indexOf(u8, permissive_result, "my-button") != null);
    try testing.expect(std.mem.indexOf(u8, permissive_result, "vue-component") != null);
    try testing.expect(std.mem.indexOf(u8, permissive_result, "phx-click") != null);
    try testing.expect(std.mem.indexOf(u8, permissive_result, ":if") != null);
    try testing.expect(std.mem.indexOf(u8, permissive_result, "@click") != null);
    try testing.expect(std.mem.indexOf(u8, permissive_result, "v-if") != null);
    try testing.expect(std.mem.indexOf(u8, permissive_result, "data-user-id") != null);

    // Traditional onclick removed even from custom elements
    try testing.expect(std.mem.indexOf(u8, permissive_result, "onclick") == null);
}
