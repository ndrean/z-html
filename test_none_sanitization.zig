const std = @import("std");
const z = @import("src/root.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create a document
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // Parse some content into the body
    try z.parseString(doc, "<div id='container'></div>");
    const body = z.bodyNode(doc).?;
    const container = z.getElementById(body, "container").?;

    // Test content with potentially dangerous elements
    const test_content = "<script>alert('XSS')</script><p onclick='alert(123)'>Click me</p><style>body{color:red}</style>";

    // Test with different sanitization options
    std.debug.print("Testing SanitizeOptions...\n");

    // 1. No sanitization
    var parser = try z.Parser.init(allocator);
    defer parser.deinit();

    try parser.insertFragment(z.elementToNode(container), test_content, .div, .none // No sanitization at all
    );

    const result_none = try z.innerHTML(allocator, container);
    defer allocator.free(result_none);
    std.debug.print("With .none: {s}\n", .{result_none});

    // Clear content
    _ = try z.setInnerHTML(container, "");

    // 2. Strict sanitization
    try parser.insertFragment(z.elementToNode(container), test_content, .div, .strict // Strict sanitization
    );

    const result_strict = try z.innerHTML(allocator, container);
    defer allocator.free(result_strict);
    std.debug.print("With .strict: {s}\n", .{result_strict});

    // Clear content
    _ = try z.setInnerHTML(container, "");

    // 3. Permissive sanitization
    try parser.insertFragment(z.elementToNode(container), test_content, .div, .permissive // Permissive sanitization
    );

    const result_permissive = try z.innerHTML(allocator, container);
    defer allocator.free(result_permissive);
    std.debug.print("With .permissive: {s}\n", .{result_permissive});

    std.debug.print("\nSanitization options API successfully implemented!\n");
    std.debug.print("Available options: .none, .strict, .permissive, .{{.custom = SanitizerOptions{{...}}}}\n");
}
