const std = @import("std");
const z = @import("zhtml.zig");
const print = std.debug.print;

test "Smart text processing features" {
    const allocator = std.testing.allocator;

    print("\n🧠 Testing Smart Text Processing Features:\n", .{});

    // Test 1: Leading whitespace detection
    print("\n1. Leading Whitespace Detection:\n", .{});
    const test_cases = [_]struct { input: []const u8, expected: usize }{
        .{ .input = "hello", .expected = 0 },
        .{ .input = "  hello", .expected = 2 },
        .{ .input = "\t\n hello", .expected = 3 },
        .{ .input = "     ", .expected = 5 },
        .{ .input = " \t\r\n text", .expected = 4 },
    };

    for (test_cases) |case| {
        const result = z.leadingWhitespaceSize(case.input);
        print("  '{s}' -> {} whitespace chars", .{ case.input, result });
        try std.testing.expectEqual(case.expected, result);
        print(" ✅\n", .{});
    }

    // Test 2: Context-aware escaping detection
    print("\n2. Context-Aware Escaping Detection:\n", .{});
    const html = "<div><script>alert('test');</script><style>body { color: red; }</style><p>normal text</p></div>";
    const doc = try z.printDocStruct(html);
    defer z.destroyDocument(doc);

    const body = z.bodyElement(doc).?;
    const div = z.firstChild(z.elementToNode(body)).?;

    // Check script element
    const script = z.firstChild(div).?;
    const script_text = z.firstChild(script);
    if (script_text) |text| {
        const should_not_escape = z.isNoEscapeTextNode(text);
        print("  Script text should NOT be escaped: {}\n", .{should_not_escape});
        try std.testing.expect(should_not_escape);
    }

    // Check style element
    const style = z.nextSibling(script).?;
    const style_text = z.firstChild(style);
    if (style_text) |text| {
        const should_not_escape = z.isNoEscapeTextNode(text);
        print("  Style text should NOT be escaped: {}\n", .{should_not_escape});
        try std.testing.expect(should_not_escape);
    }

    // Check regular p element
    const p = z.nextSibling(style).?;
    const p_text = z.firstChild(p);
    if (p_text) |text| {
        const should_escape = !z.isNoEscapeTextNode(text);
        print("  Regular text SHOULD be escaped: {}\n", .{should_escape});
        try std.testing.expect(should_escape);
    }

    // Test 3: Smart HTML escaping with whitespace preservation
    print("\n3. Smart HTML Escaping (LazyHTML-style):\n", .{});
    const basic = try z.escapeHtmlSmart(allocator, "Hello <world>");
    defer allocator.free(basic);
    print("  Basic: 'Hello <world>' -> '{s}'\n", .{basic});
    try std.testing.expectEqualStrings("Hello &lt;world&gt;", basic);

    const with_whitespace = try z.escapeHtmlSmart(allocator, "  \t  <script>alert('xss')</script>");
    defer allocator.free(with_whitespace);
    print("  With whitespace: '  \\t  <script>...' -> '{s}'\n", .{with_whitespace});
    try std.testing.expect(std.mem.startsWith(u8, with_whitespace, "  \t  "));
    try std.testing.expect(std.mem.indexOf(u8, with_whitespace, "&lt;script&gt;") != null);

    // Test 4: Context-aware text processing integration
    print("\n4. Context-Aware Text Processing Integration:\n", .{});
    const integration_html = "<div><script>console.log('hello');</script><p>  <strong>Hello</strong> & world!</p></div>";
    const integration_doc = try z.printDocStruct(integration_html);
    defer z.destroyDocument(integration_doc);

    const integration_body = try z.bodyElement(integration_doc);
    const integration_div = z.firstChild(z.elementToNode(integration_body)).?;
    const integration_script = z.firstChild(integration_div).?;
    const integration_script_text = z.firstChild(integration_script);

    if (integration_script_text) |text| {
        // Script content should not be escaped
        const script_result = try z.processTextContentSmart(allocator, text, false);
        if (script_result) |result| {
            defer allocator.free(result);
            print("  Script text (unescaped): '{s}'\n", .{result});
            try std.testing.expect(std.mem.indexOf(u8, result, "console.log('hello');") != null);
        }
    }

    const integration_p = z.nextSibling(integration_script).?;
    const integration_p_text = z.firstChild(integration_p);

    if (integration_p_text) |text| {
        // Regular text should be escaped with whitespace preservation
        const p_result = try z.processTextContentSmart(allocator, text, false);
        if (p_result) |result| {
            defer allocator.free(result);
            print("  Regular text (escaped): '{s}'\n", .{result});
            // Should start with preserved whitespace
            try std.testing.expect(std.mem.startsWith(u8, result, "  "));
        }
    }

    print("\n🎯 All Smart Text Processing tests passed! LazyHTML-level features working!\n", .{});
}
