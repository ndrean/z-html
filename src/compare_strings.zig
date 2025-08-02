const std = @import("std");
const testing = std.testing;
const Print = std.debug.print;

test "slice comparison examples" {
    const allocator = testing.allocator;

    // String/slice content comparison
    const text1 = try allocator.dupe(u8, "hello");
    defer allocator.free(text1);
    const text2 = "hello";

    // ✅ Compare slice contents
    try testing.expectEqualStrings(text1, text2);

    // ❌ This would fail - different pointers
    // try testing.expectEqual(text1, text2);

    // Numbers and primitives
    const num1: u32 = 42;
    const num2: u32 = 42;

    // ✅ Compare primitive values
    try testing.expectEqual(num1, num2);

    // Optional comparison
    const maybe_text: ?[]const u8 = "hello";

    // ✅ Compare optional contents
    try testing.expect(maybe_text != null);
    try testing.expectEqualStrings("hello", maybe_text.?);

    // Array comparison
    const arr1 = [_]u8{ 1, 2, 3 };
    const arr2 = [_]u8{ 1, 2, 3 };

    // ✅ Compare array contents
    try testing.expectEqualSlices(u8, &arr1, &arr2);
}
