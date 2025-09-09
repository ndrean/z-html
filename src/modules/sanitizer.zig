//! This module handles the sanitization of HTML content. It is built to ensure that the HTML is safe and clean before it is serialized.
//! It works with _whitelists_ on accepted elements and attributes.
//!
//! It provides functions to
//! - remove unwanted elements, comments
//! - validate and sanitize attributes
//! - ensure safe URI usage
const std = @import("std");
const z = @import("../root.zig");
const HtmlTag = z.HtmlTag;
const Err = z.Err;
const print = std.debug.print;

const testing = std.testing;

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

/// [sanitize] Check if iframe is safe (has sandbox attribute)
fn isIframeSafe(element: *z.HTMLElement) bool {
    // iframe is only safe if it has the sandbox attribute
    if (!z.hasAttribute(element, "sandbox")) {
        return false; // No sandbox = unsafe
    }

    // Additional validation: check src for dangerous protocols
    if (z.getAttribute_zc(element, "src")) |src_value| {
        // Block javascript: and data: protocols in src
        if (std.mem.startsWith(u8, src_value, "javascript:") or
            std.mem.startsWith(u8, src_value, "data:"))
        {
            return false;
        }
    }

    return true; // Has sandbox and safe src
}

/// [sanitize] Check if an element and attribute combination is allowed using unified specification
pub fn isElementAttributeAllowed(element_tag: []const u8, attr_name: []const u8) bool {
    return z.isAttributeAllowedFast(element_tag, attr_name);
}

/// [sanitize] Fast enum-based element and attribute validation
pub fn isElementAttributeAllowedEnum(tag: HtmlTag, attr_name: []const u8) bool {
    return z.isAttributeAllowedEnum(tag, attr_name);
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

fn isDescendantOfSvg(tag: z.HtmlTag, parent: z.HtmlTag) bool {
    return (tag == .svg or parent == .svg) or return false;
}

fn isDangerousSvgDescendant(tag_name: []const u8) bool {
    return std.mem.eql(u8, tag_name, "script") or
        std.mem.eql(u8, tag_name, "foreignObject") or
        std.mem.eql(u8, tag_name, "animate") or // Can have onbegin, onend events
        std.mem.eql(u8, tag_name, "animateTransform") or
        std.mem.eql(u8, tag_name, "set");
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

pub const SanitizeOptions = union(enum) {
    none: void,
    minimum: void,
    strict: void,
    permissive: void,
    custom: SanitizerOptions,

    pub inline fn get(self: @This()) SanitizerOptions {
        return switch (self) {
            .none => unreachable, // Should never reach here - early exit in sanitizeWithOptions
            .minimum => SanitizerOptions{
                .skip_comments = false,
                .remove_scripts = false,
                .remove_styles = false,
                .strict_uri_validation = false,
                .allow_custom_elements = true,
            },
            .strict => SanitizerOptions{
                .skip_comments = true,
                .remove_scripts = true,
                .remove_styles = true,
                .strict_uri_validation = true,
                .allow_custom_elements = false,
            },
            .permissive => SanitizerOptions{
                .skip_comments = true,
                .remove_scripts = true,
                .remove_styles = true,
                .strict_uri_validation = true,
                .allow_custom_elements = true,
            },
            .custom => |opts| opts,
        };
    }
};

/// [sanitize] Settings of the sanitizer
///
/// The `.minimum` option does:
/// 1. Dangerous URL schemes: javascript:,
///  vbscript: in ANY attribute value
///  2. Dangerous data URLs: data:text/html,
///  data:text/javascript, data: with base64
///  3. Event handlers: All on* attributes
///  (onclick, onerror, etc.)
///  4. Invalid targets: Non-standard target
///  attribute values
///  5. Inline styles: style attributes (removes
///  CSS injection)
///  6. Dangerous SVG elements: script,
///  foreignObject, animate, etc. in SVG context
///  7. Unsafe iframes: iframes without sandbox
///  attribute
pub const SanitizerOptions = struct {
    skip_comments: bool = true,
    remove_scripts: bool = true,
    remove_styles: bool = true,
    strict_uri_validation: bool = true,
    allow_custom_elements: bool = false,
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
    parent: z.HtmlTag = .html,

    // Stack attribute name storage
    attr_name_buffer: [STACK_ATTR_BUFFER_SIZE]u8 = undefined,
    attr_name_fba: std.heap.FixedBufferAllocator = undefined,

    // Stack arrays
    nodes_to_remove: [MAX_STACK_REMOVALS]*z.DomNode = undefined,
    attributes_to_remove: [MAX_STACK_REMOVALS]AttributeAction = undefined,
    template_nodes: [MAX_STACK_TEMPLATES]*z.DomNode = undefined,

    // Counters
    nodes_count: usize = 0,
    attrs_count: usize = 0,
    templates_count: usize = 0,

    fn init(alloc: std.mem.Allocator, opts: SanitizerOptions) @This() {
        var self = @This(){
            .allocator = alloc,
            .options = opts,
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
    if (isDangerousSvgDescendant(tag_name)) {
        return removeAndContinue(context_ptr, node);
    }

    // Safe SVG element - check if allowed using centralized spec
    if (z.getElementSpecFast(tag_name) != null) {
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

    // Standard HTML element - use centralized spec
    if (z.getElementSpecByEnum(tag) != null) {
        // Special handling for iframe - check sandbox requirement
        if (tag == .iframe) {
            if (!isIframeSafe(element)) {
                return removeAndContinue(context_ptr, node);
            }
        }
        collectDangerousAttributesEnum(context_ptr, element, tag) catch return z._STOP;
    } else {
        // Known tag but not in whitelist - check if it's a custom element
        if (context_ptr.options.allow_custom_elements and isCustomElement(tag_str)) {
            // Custom element - use permissive sanitization
            collectCustomElementAttributes(context_ptr, element) catch |err| {
                print("Error in collectCustomElementAttributes: {}\n", .{err});
                return z._STOP;
            };
        } else {
            // Known tag but not in whitelist: eg script elements
            return removeAndContinue(context_ptr, node);
        }
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
        .object,
        .embed,
        => true,
        else => false,
        // Note: iframe is handled separately with sandbox validation
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

/// Fast enum-based attribute sanitization for standard HTML elements
fn collectDangerousAttributesEnum(context: *SanitizeContext, element: *z.HTMLElement, tag: HtmlTag) !void {
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
        } else if (!isElementAttributeAllowedEnum(tag, attr_pair.name)) {
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

pub fn sanitizeWithOptions(
    allocator: std.mem.Allocator,
    root_node: *z.DomNode,
    options: SanitizeOptions,
) (std.mem.Allocator.Error || z.Err)!void {
    // Early exit for .none - do absolutely nothing
    if (options == .none) return;

    const sanitizer_options = options.get();
    var context = SanitizeContext.init(allocator, sanitizer_options);
    defer context.deinit();

    z.simpleWalk(
        root_node,
        sanitizeCollectorCB,
        &context,
    );

    try sanitizePostWalkOperations(
        allocator,
        &context,
        sanitizer_options,
    );
}

pub fn sanitizeNode(allocator: std.mem.Allocator, root_node: *z.DomNode, options: SanitizeOptions) (std.mem.Allocator.Error || z.Err)!void {
    return sanitizeWithOptions(allocator, root_node, options);
}

// Convenience functions for common sanitization scenarios
pub fn sanitizeStrict(allocator: std.mem.Allocator, root_node: *z.DomNode) (std.mem.Allocator.Error || z.Err)!void {
    return sanitizeWithOptions(allocator, root_node, .strict);
}

pub fn sanitizePermissive(allocator: std.mem.Allocator, root_node: *z.DomNode) (std.mem.Allocator.Error || z.Err)!void {
    return sanitizeWithOptions(allocator, root_node, .permissive);
}

test "iframe sandbox validation" {
    const allocator = testing.allocator;

    const test_html =
        \\<iframe sandbox src="https://example.com">Safe iframe</iframe>
        \\<iframe src="https://example.com">Unsafe - no sandbox</iframe>
        \\<iframe sandbox src="javascript:alert('XSS')">Unsafe - dangerous src</iframe>
        \\<iframe sandbox>Safe - empty sandbox, no src</iframe>
    ;

    const doc = try z.createDocFromString(test_html);
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;

    try sanitizeStrict(allocator, body);

    // Normalize to clean up whitespace left by element removal
    const body_element = z.nodeToElement(body) orelse return;
    try z.normalizeDOM(allocator, body_element);

    const result = try z.outerNodeHTML(allocator, body);
    defer allocator.free(result);

    const expected = "<body><iframe sandbox src=\"https://example.com\">Safe iframe</iframe><iframe sandbox>Safe - empty sandbox, no src</iframe></body>";
    try testing.expectEqualStrings(expected, result);

    // // Should keep safe sandboxed iframes
    // try testing.expect(std.mem.indexOf(u8, result, "Safe iframe") != null);
    // try testing.expect(std.mem.indexOf(u8, result, "Safe - empty sandbox") != null);

    // // Should remove unsafe iframes
    // try testing.expect(std.mem.indexOf(u8, result, "Unsafe - no sandbox") == null);
    // try testing.expect(std.mem.indexOf(u8, result, "Unsafe - dangerous src") == null);
}

// -----------------[TODO] ----------------
test "comprehensive sanitization modes" {
    const allocator = testing.allocator;

    // Comprehensive malicious HTML content covering all attack vectors
    const comprehensive_malicious_html =
        \\<div onclick="alert('xss')" style="background: url(javascript:alert('css'))">
        \\  <script>alert('xss')</script>
        \\  <!-- malicious comment with <script>alert('comment')</script> -->
        \\  <style>body { background: url(javascript:alert('css')); }</style>
        \\  <p onmouseover="steal_data()" class="safe-class">Safe text</p>
        \\  <a href="javascript:alert('href')" title="Bad link">Bad link</a>
        \\  <a href="https://example.com" class="link">Good link</a>
        \\  <img src="https://example.com/image.jpg" alt="Safe image" onerror="alert('img')">
        \\  <iframe src="evil.html">Unsafe iframe</iframe>
        \\  <iframe sandbox src="https://example.com">Safe iframe</iframe>
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
        \\  <phoenix-component phx-click="increment" :if="show_component" onclick="alert('custom')">
        \\    Phoenix LiveView Component
        \\  </phoenix-component>
        \\  <my-button @click="handleClick" :disabled="isDisabled" class="btn">
        \\    Custom Button
        \\  </my-button>
        \\  <vue-component v-if="showProfile" data-user-id="123">Vue Component</vue-component>
        \\  <button disabled hidden onclick="alert('XSS')" phx-click="increment">Potentially dangerous</button>
        \\  <div data-time="{@current}"> The current value is: {@counter} </div>
        \\  <a href="http://example.org/results?search=<img src=x onerror=alert('hello')>">URL Escaped</a>
        \\  <img src="data:text/html,<script>alert('XSS')</script>" alt="escaped">
        \\  <a href="data:text/html;base64,PHNjcmlwdD5hbGVydCgnWFNTJyk8L3NjcmlwdD4=">Potential dangerous b64</a>
        \\  <a href="file:///etc/passwd">Dangerous Local file access</a>
        \\  <p> The <code>push()</code> method adds one or more elements to the end of an array</p>
        \\  <pre> <code>Node.clone();</code>
        \\ method creates a copy of an element</pre>
        \\  <pre>function dangerous() {
        \\    <script>alert('pre-script')</script>
        \\    return "formatted code";
        \\  }</pre>
        \\</div>
        \\<link href="/shared-assets/misc/link-element-example.css" rel="stylesheet">
        \\<template><script>alert('XSS');</script><li id="{}">Item-"{}"</li></template>
    ;

    // print("\n=== Comprehensive Sanitization Test ===\n", .{});

    // Test 1: .minimum mode (minimal sanitization - only truly dangerous content)
    {
        const doc = try z.createDocFromString(comprehensive_malicious_html);
        defer z.destroyDocument(doc);
        const body = z.bodyNode(doc).?;

        try sanitizeWithOptions(allocator, body, .minimum);

        const result = try z.outerNodeHTML(allocator, body);
        defer allocator.free(result);

        // print("\n=== .minimum mode (minimal sanitization) ===\n", .{});

        // Should preserve most content including scripts and custom elements
        try testing.expect(std.mem.indexOf(u8, result, "script") != null);
        try testing.expect(std.mem.indexOf(u8, result, "malicious comment") != null);
        try testing.expect(std.mem.indexOf(u8, result, "phoenix-component") != null);
        try testing.expect(std.mem.indexOf(u8, result, "my-button") != null);
        try testing.expect(std.mem.indexOf(u8, result, "vue-component") != null);

        // Should preserve pre/code elements and their text content
        try testing.expect(std.mem.indexOf(u8, result, "<pre") != null);
        try testing.expect(std.mem.indexOf(u8, result, "<code") != null);
        try testing.expect(std.mem.indexOf(u8, result, "Node.clone()") != null);
        try testing.expect(std.mem.indexOf(u8, result, "push()") != null);
        try testing.expect(std.mem.indexOf(u8, result, "function dangerous()") != null);
        // Note: onclick and javascript: URIs might still be filtered at parser level
    }

    // Test 2: .strict mode (no custom elements, remove all dangerous content)
    {
        const doc = try z.createDocFromString(comprehensive_malicious_html);
        defer z.destroyDocument(doc);
        const body = z.bodyNode(doc).?;

        try sanitizeWithOptions(allocator, body, .strict);

        // Normalize to clean up empty text nodes
        const body_element = z.nodeToElement(body) orelse return;
        try z.normalizeDOM(allocator, body_element);

        const result = try z.outerNodeHTML(allocator, body);
        defer allocator.free(result);

        // print("\n=== .strict mode (secure, no custom elements) ===\n", .{});

        // Should remove dangerous content
        try testing.expect(std.mem.indexOf(u8, result, "script") == null);
        try testing.expect(std.mem.indexOf(u8, result, "onclick") == null);
        try testing.expect(std.mem.indexOf(u8, result, "javascript:") == null);
        try testing.expect(std.mem.indexOf(u8, result, "malicious comment") == null);
        try testing.expect(std.mem.indexOf(u8, result, "foreignObject") == null);
        try testing.expect(std.mem.indexOf(u8, result, "animate") == null);

        // Should remove custom elements in strict mode
        try testing.expect(std.mem.indexOf(u8, result, "phoenix-component") == null);
        try testing.expect(std.mem.indexOf(u8, result, "my-button") == null);
        try testing.expect(std.mem.indexOf(u8, result, "vue-component") == null);

        // Should preserve safe content
        try testing.expect(std.mem.indexOf(u8, result, "Safe text") != null);
        try testing.expect(std.mem.indexOf(u8, result, "Good link") != null);
        try testing.expect(std.mem.indexOf(u8, result, "safe-class") != null);
        try testing.expect(std.mem.indexOf(u8, result, "https://example.com") != null);
        try testing.expect(std.mem.indexOf(u8, result, "<svg") != null);
        try testing.expect(std.mem.indexOf(u8, result, "<circle") != null);
        try testing.expect(std.mem.indexOf(u8, result, "SVG Text") != null);

        // Should preserve pre/code elements and text content but remove dangerous scripts inside them
        try testing.expect(std.mem.indexOf(u8, result, "<pre") != null);
        try testing.expect(std.mem.indexOf(u8, result, "<code") != null);
        try testing.expect(std.mem.indexOf(u8, result, "Node.clone()") != null);
        try testing.expect(std.mem.indexOf(u8, result, "push()") != null);
        try testing.expect(std.mem.indexOf(u8, result, "function dangerous()") != null);
        // But script tags inside pre should be removed
        try testing.expect(std.mem.indexOf(u8, result, "pre-script") == null);
    }

    // Test 3: .permissive mode (allow custom elements, still secure)
    {
        const doc = try z.createDocFromString(comprehensive_malicious_html);
        defer z.destroyDocument(doc);
        const body = z.bodyNode(doc).?;

        try sanitizeWithOptions(allocator, body, .permissive);

        const result = try z.outerNodeHTML(allocator, body);
        defer allocator.free(result);

        // print("\n=== .permissive mode (custom elements enabled) ===\n", .{});

        // Should still remove dangerous content
        try testing.expect(std.mem.indexOf(u8, result, "script") == null);
        try testing.expect(std.mem.indexOf(u8, result, "foreignObject") == null);
        try testing.expect(std.mem.indexOf(u8, result, "animate") == null);
        try testing.expect(std.mem.indexOf(u8, result, "javascript:") == null);

        // Should preserve custom elements and framework attributes
        try testing.expect(std.mem.indexOf(u8, result, "phoenix-component") != null);
        try testing.expect(std.mem.indexOf(u8, result, "my-button") != null);
        try testing.expect(std.mem.indexOf(u8, result, "vue-component") != null);
        try testing.expect(std.mem.indexOf(u8, result, "phx-click") != null);
        try testing.expect(std.mem.indexOf(u8, result, ":if") != null);
        try testing.expect(std.mem.indexOf(u8, result, "@click") != null);
        try testing.expect(std.mem.indexOf(u8, result, "v-if") != null);
        try testing.expect(std.mem.indexOf(u8, result, "data-user-id") != null);

        // Traditional onclick should still be removed even from custom elements
        try testing.expect(std.mem.indexOf(u8, result, "onclick") == null);

        // Should preserve pre/code elements and text content
        try testing.expect(std.mem.indexOf(u8, result, "<pre") != null);
        try testing.expect(std.mem.indexOf(u8, result, "<code") != null);
        try testing.expect(std.mem.indexOf(u8, result, "Node.clone()") != null);
        try testing.expect(std.mem.indexOf(u8, result, "function dangerous()") != null);
        // But script tags inside pre should still be removed
        try testing.expect(std.mem.indexOf(u8, result, "pre-script") == null);
    }

    // Test 4: .custom mode (preserve comments, allow scripts, allow custom elements)
    {
        const doc = try z.createDocFromString(comprehensive_malicious_html);
        defer z.destroyDocument(doc);
        const body = z.bodyNode(doc).?;

        try sanitizeWithOptions(allocator, body, .{
            .custom = SanitizerOptions{
                .skip_comments = false, // Preserve comments
                .remove_scripts = false, // Allow scripts
                .remove_styles = true, // Remove styles
                .strict_uri_validation = false, // Allow more URIs
                .allow_custom_elements = true, // Allow custom elements
            },
        });

        const result = try z.outerNodeHTML(allocator, body);
        defer allocator.free(result);

        // print("\n=== .custom mode (comments preserved, scripts allowed) ===\n", .{});

        // Should preserve comments and scripts
        try testing.expect(std.mem.indexOf(u8, result, "malicious comment") != null);
        try testing.expect(std.mem.indexOf(u8, result, "script") != null);

        // Should preserve custom elements
        try testing.expect(std.mem.indexOf(u8, result, "phoenix-component") != null);
        try testing.expect(std.mem.indexOf(u8, result, "my-button") != null);
        try testing.expect(std.mem.indexOf(u8, result, "vue-component") != null);

        // Should still remove styles (as configured)
        try testing.expect(std.mem.indexOf(u8, result, "<style") == null);

        // Should preserve pre/code elements and all text content (including scripts if configured)
        try testing.expect(std.mem.indexOf(u8, result, "<pre") != null);
        try testing.expect(std.mem.indexOf(u8, result, "<code") != null);
        try testing.expect(std.mem.indexOf(u8, result, "Node.clone()") != null);
        try testing.expect(std.mem.indexOf(u8, result, "push()") != null);
        try testing.expect(std.mem.indexOf(u8, result, "function dangerous()") != null);
        // In custom mode with scripts allowed, might preserve script content
        // (but the script tags themselves might still be parsed/handled)
    }
}
