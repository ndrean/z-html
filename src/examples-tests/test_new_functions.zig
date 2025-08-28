const std = @import("std");
const z = @import("zhtml.zig");
const print = std.debug.print;

test "Newly added lexbor functions" {
    const allocator = std.testing.allocator;

    print("\n🔧 Testing Newly Added Lexbor Functions:\n", .{});

    // Test qualified name function
    print("\n1. Element Qualified Name:\n", .{});
    const html = "<div><svg:circle xmlns:svg='http://www.w3.org/2000/svg' r='10'/><p>Regular paragraph</p></div>";
    const doc = try z.printDocStruct(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const div = z.firstChild(z.elementToNode(body)).?;
    const div_element = z.nodeToElement(div).?;

    // Test on regular HTML element
    const div_qualified = try z.qualifiedName(allocator, div_element);
    defer allocator.free(div_qualified);
    print("  DIV qualified name: '{s}'\n", .{div_qualified});
    try std.testing.expectEqualStrings("div", div_qualified);

    // Test on paragraph element
    const p = z.firstChild(div).?;
    const p_element = z.nodeToElement(p).?;
    const p_qualified = try z.qualifiedName(allocator, p_element);
    defer allocator.free(p_qualified);
    print("  P qualified name: '{s}'\n", .{p_qualified});
    try std.testing.expectEqualStrings("p", p_qualified);

    // Test string comparison function
    print("\n2. String Comparison:\n", .{});

    // Test identical strings
    const str1 = "hello";
    const str2 = "hello";
    const equal = z.compareStrings(str1, str2);
    print("  '{s}' == '{s}': {}\n", .{ str1, str2, equal });
    try std.testing.expect(equal);

    // Test different strings
    const str3 = "hello";
    const str4 = "world";
    const not_equal = z.compareStrings(str3, str4);
    print("  '{s}' == '{s}': {}\n", .{ str3, str4, not_equal });
    try std.testing.expect(!not_equal);

    // Test different length strings
    const str5 = "hello";
    const str6 = "hello world";
    const diff_length = z.compareStrings(str5, str6);
    print("  '{s}' == '{s}': {}\n", .{ str5, str6, diff_length });
    try std.testing.expect(!diff_length);

    // Test empty strings
    const empty1 = "";
    const empty2 = "";
    const empty_equal = z.compareStrings(empty1, empty2);
    print("  '' == '': {}\n", .{empty_equal});
    try std.testing.expect(empty_equal);

    print("\n✅ All newly added lexbor functions working correctly!\n", .{});
}
