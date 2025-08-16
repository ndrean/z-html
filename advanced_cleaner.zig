//! Advanced DOM cleaning with LazyHTML-level sophistication

const std = @import("std");
const z = @import("../zhtml.zig");

/// Calculate leading whitespace size in text content
pub fn leadingWhitespaceSize(data: []const u8) usize {
    var size: usize = 0;

    for (data) |ch| {
        switch (ch) {
            ' ', '\t', '\n', '\r' => size += 1,
            else => return size,
        }
    }

    return size;
}

/// Check if a text node should not be escaped (inside script, style, etc.)
/// OPTIMIZED: Uses zero-copy enum-based lookup for maximum performance
pub fn isNoEscapeTextNode(node: *z.DomNode) bool {
    const parent = z.parentNode(node) orelse return false;

    if (z.nodeToElement(parent)) |parent_element| {
        const qualified_name = z.qualifiedNameBorrow(parent_element);
        return z.isNoEscapeElementFast(qualified_name);
    }

    return false;
}

/// Smart text node processing with context-aware escaping
pub fn appendNodeHtmlSmart(allocator: std.mem.Allocator, node: *z.DomNode, skip_whitespace_nodes: bool, html: *std.ArrayList(u8)) !void {
    const node_type = z.nodeType(node);

    switch (node_type) {
        .text => {
            // Zero-copy text content access for immediate processing
            if (z.getTextContentBorrow(node)) |text_content| {
                const whitespace_size = leadingWhitespaceSize(text_content);

                // Skip whitespace-only nodes if requested
                if (whitespace_size == text_content.len and skip_whitespace_nodes) {
                    return;
                }

                if (isNoEscapeTextNode(node)) {
                    // No escaping for script/style content
                    try html.appendSlice(text_content);
                } else {
                    // Smart escaping with whitespace preservation
                    try appendEscapingSmart(html, text_content, whitespace_size);
                }
            }
            // Note: If getTextContentBorrow returns null, we simply skip the node
        },

        .comment => {
            // Comments still need allocation since we need to handle potential empty content
            const text_content = try z.getTextContent(allocator, node);
            defer allocator.free(text_content);

            try html.appendSlice("<!--");
            try html.appendSlice(text_content);
            try html.appendSlice("-->");
        },

        .element => {
            // Handle template elements specially
            if (z.isTemplateElement(node)) {
                try appendTemplateElementHtml(allocator, node, skip_whitespace_nodes, html);
            } else {
                try appendRegularElementHtml(allocator, node, skip_whitespace_nodes, html);
            }
        },

        else => {},
    }
}

/// Smart escaping that preserves meaningful whitespace
fn appendEscapingSmart(html: *std.ArrayList(u8), content: []const u8, whitespace_size: usize) !void {
    // Preserve leading whitespace as-is
    if (whitespace_size > 0) {
        try html.appendSlice(content[0..whitespace_size]);
    }

    // Escape the rest
    for (content[whitespace_size..]) |ch| {
        switch (ch) {
            '<' => try html.appendSlice("&lt;"),
            '>' => try html.appendSlice("&gt;"),
            '&' => try html.appendSlice("&amp;"),
            '"' => try html.appendSlice("&quot;"),
            '\'' => try html.appendSlice("&#39;"),
            else => try html.append(ch),
        }
    }
}

/// Handle template elements with proper content access
fn appendTemplateElementHtml(allocator: std.mem.Allocator, node: *z.DomNode, skip_whitespace_nodes: bool, html: *std.ArrayList(u8)) !void {
    if (z.nodeToElement(node)) |element| {
        // Start tag
        const tag_name = z.tagName(element);
        try html.append('<');
        try html.appendSlice(tag_name);

        // Attributes
        if (try z.getAttributes(allocator, element)) |attrs| {
            defer {
                for (attrs) |attr| {
                    allocator.free(attr.name);
                    allocator.free(attr.value);
                }
                allocator.free(attrs);
            }

            for (attrs) |attr| {
                try html.append(' ');
                try html.appendSlice(attr.name);
                try html.appendSlice("=\"");
                // Escape attribute value
                for (attr.value) |ch| {
                    switch (ch) {
                        '"' => try html.appendSlice("&quot;"),
                        '&' => try html.appendSlice("&amp;"),
                        else => try html.append(ch),
                    }
                }
                try html.append('"');
            }
            try html.append('>');

            // Template content - use template-aware traversal
            var child = z.templateAwareFirstChild(node);
            while (child != null) {
                try appendNodeHtmlSmart(allocator, child.?, skip_whitespace_nodes, html);
                child = z.nextSibling(child.?);
            }

            // End tag
            try html.appendSlice("</");
            try html.appendSlice(tag_name);
            try html.append('>');
        }
    }
}

/// Handle regular elements
fn appendRegularElementHtml(allocator: std.mem.Allocator, node: *z.DomNode, skip_whitespace_nodes: bool, html: *std.ArrayList(u8)) !void {
    if (z.nodeToElement(node)) |element| {
        const tag_name = z.tagName(element);

        // Start tag
        try html.append('<');
        try html.appendSlice(tag_name);

        // Attributes
        const attrs = try z.getAttributes(allocator, element);
        defer {
            for (attrs) |attr| {
                allocator.free(attr.name);
                allocator.free(attr.value);
            }
            allocator.free(attrs);
        }

        for (attrs) |attr| {
            try html.append(' ');
            try html.appendSlice(attr.name);
            try html.appendSlice("=\"");
            // Escape attribute value
            for (attr.value) |ch| {
                switch (ch) {
                    '"' => try html.appendSlice("&quot;"),
                    '&' => try html.appendSlice("&amp;"),
                    else => try html.append(ch),
                }
            }
            try html.append('"');
        }

        // Check if it's a void element - OPTIMIZED: Zero-copy enum-based lookup
        const qualified_name = z.qualifiedNameBorrow(element);
        if (z.isVoidElementFast(qualified_name)) {
            try html.appendSlice(" />");
            return;
        }

        try html.append('>');

        // Children
        var child = z.firstChild(node);
        while (child != null) {
            try appendNodeHtmlSmart(allocator, child.?, skip_whitespace_nodes, html);
            child = z.nextSibling(child.?);
        }

        // End tag
        try html.appendSlice("</");
        try html.appendSlice(tag_name);
        try html.append('>');
    }
}

/// Advanced DOM cleaning with LazyHTML-level sophistication
pub fn cleanDomTreeAdvanced(allocator: std.mem.Allocator, root: *z.DomNode, options: AdvancedCleanOptions) !void {
    try cleanNodeAdvanced(allocator, root, options);
}

pub const AdvancedCleanOptions = struct {
    skip_whitespace_nodes: bool = true,
    context_aware_escaping: bool = true,
    preserve_template_content: bool = true,
    smart_attribute_handling: bool = true,
};

fn cleanNodeAdvanced(allocator: std.mem.Allocator, node: *z.DomNode, options: AdvancedCleanOptions) !void {
    const node_type = z.nodeType(node);

    switch (node_type) {
        .text => {
            if (options.skip_whitespace_nodes) {
                // Zero-copy whitespace detection
                if (z.getTextContentBorrow(node)) |text_content| {
                    const whitespace_size = leadingWhitespaceSize(text_content);
                    if (whitespace_size == text_content.len) {
                        // Remove whitespace-only text nodes
                        z.destroyNode(node);
                        return;
                    }
                }
            }
        },

        .element => {
            if (options.smart_attribute_handling) {
                try cleanElementAttributesAdvanced(allocator, node);
            }
        },

        else => {},
    }

    // Recursively process children with template awareness
    var child = if (options.preserve_template_content and z.isTemplateElement(node))
        z.templateAwareFirstChild(node)
    else
        z.firstChild(node);

    while (child != null) {
        const next_child = z.nextSibling(child.?);
        try cleanNodeAdvanced(allocator, child.?, options);
        child = next_child;
    }
}

fn cleanElementAttributesAdvanced(allocator: std.mem.Allocator, node: *z.DomNode) !void {
    if (z.nodeToElement(node)) |element| {
        // Get all attributes
        const attrs = try z.getAttributes(allocator, element);
        defer {
            for (attrs) |attr| {
                allocator.free(attr.name);
                allocator.free(attr.value);
            }
            allocator.free(attrs);
        }

        // Clean and normalize attributes
        for (attrs) |attr| {
            const clean_name = std.mem.trim(u8, attr.name, " \t\n\r");
            const clean_value = std.mem.trim(u8, attr.value, " \t\n\r");

            // Remove and re-add with clean values
            try z.removeAttribute(element, attr.name);
            try z.setAttribute(element, clean_name, clean_value);
        }
    }
}

const testing = std.testing;

test "leading whitespace detection" {
    try testing.expectEqual(@as(usize, 0), leadingWhitespaceSize("hello"));
    try testing.expectEqual(@as(usize, 2), leadingWhitespaceSize("  hello"));
    try testing.expectEqual(@as(usize, 3), leadingWhitespaceSize("\t\n hello"));
    try testing.expectEqual(@as(usize, 5), leadingWhitespaceSize("     "));
}

test "no-escape text node detection" {
    const allocator = testing.allocator;

    const html = "<div><script>alert('test');</script><p>normal text</p></div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const div = z.firstChild(z.elementToNode(body)).?;
    const script = z.firstChild(div).?;
    const script_text = z.firstChild(script);

    // Script text should not be escaped (if it exists)
    if (script_text) |text| {
        try testing.expect(isNoEscapeTextNode(text));
    }

    const p = z.nextSibling(script).?;
    const p_text = z.firstChild(p);

    // Regular text should be escaped (if it exists)
    if (p_text) |text| {
        try testing.expect(!isNoEscapeTextNode(text));
    }

    _ = allocator; // Suppress unused warning
}

test "zero-copy text content functions" {
    const html = "<div>Hello <span>World</span>!</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const div = z.firstChild(z.elementToNode(body)).?;

    // Test zero-copy text content access
    if (z.getTextContentBorrow(div)) |text_content| {
        try testing.expect(std.mem.eql(u8, text_content, "Hello World!"));
    } else {
        try testing.expect(false); // Should have text content
    }

    // Test that it's actually zero-copy by checking we get the same pointer
    const borrowed1 = z.getTextContentBorrow(div);
    const borrowed2 = z.getTextContentBorrow(div);
    try testing.expect(borrowed1 != null);
    try testing.expect(borrowed2 != null);
    // Same pointer means zero-copy (lexbor's internal buffer)
    try testing.expect(borrowed1.?.ptr == borrowed2.?.ptr);
}
